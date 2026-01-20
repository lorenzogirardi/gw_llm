# Kong LLM Gateway - Development Environment
#
# This configuration creates:
# - EKS cluster with managed node group
# - IAM roles for Bedrock access (IRSA)
# - VPC with public/private subnets
#
# Usage:
#   terraform init
#   terraform plan -out=tfplan
#   terraform apply tfplan

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Uncomment for remote state (recommended for team environments)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "kong-llm-gateway/dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "kong-llm-gateway"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

# Configure kubernetes provider after cluster is created
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "kong-llm-gateway-dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "Instance types for worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # VPC Configuration (creates new VPC)
  vpc_cidr             = "10.0.0.0/16"
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # Node Group
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = 1
  node_max_size       = 5
  node_capacity_type  = "ON_DEMAND"

  # Logging
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = {
    Environment = "dev"
    Project     = "kong-llm-gateway"
  }
}

# -----------------------------------------------------------------------------
# Bedrock IAM (IRSA)
# -----------------------------------------------------------------------------

module "bedrock" {
  source = "../../modules/bedrock"

  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer       = module.eks.oidc_issuer

  namespace       = "kong"
  service_account = "kong"

  # Allow access to Claude and Titan models
  allowed_model_arns = [
    "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-5-sonnet-*",
    "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-sonnet-*",
    "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku-*",
    "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-text-*"
  ]

  enable_cloudwatch_logs    = true
  enable_cloudwatch_metrics = true
  cloudwatch_namespace      = "Kong/LLMGateway"

  tags = {
    Environment = "dev"
    Project     = "kong-llm-gateway"
  }

  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "kong_role_arn" {
  description = "IAM role ARN for Kong service account"
  value       = module.bedrock.kong_role_arn
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "helm_install_command" {
  description = "Command to install Kong via Helm (manual alternative)"
  value       = <<-EOT
    helm upgrade --install kong kong/kong \
      --namespace kong \
      --create-namespace \
      --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${module.bedrock.kong_role_arn}" \
      -f ../../helm/kong-values.yaml
  EOT
}

# -----------------------------------------------------------------------------
# Kong Gateway (via Terraform)
# -----------------------------------------------------------------------------

# Read Kong configuration file
data "local_file" "kong_config" {
  filename = "${path.module}/../../helm/kong.yaml"
}

# Read custom plugins
data "local_file" "bedrock_proxy_handler" {
  filename = "${path.module}/../../../../kong/plugins/bedrock-proxy/handler.lua"
}

data "local_file" "bedrock_proxy_schema" {
  filename = "${path.module}/../../../../kong/plugins/bedrock-proxy/schema.lua"
}

data "local_file" "token_meter_handler" {
  filename = "${path.module}/../../../../kong/plugins/token-meter/handler.lua"
}

data "local_file" "token_meter_schema" {
  filename = "${path.module}/../../../../kong/plugins/token-meter/schema.lua"
}

data "local_file" "guardrails_handler" {
  filename = "${path.module}/../../../../kong/plugins/ecommerce-guardrails/handler.lua"
}

data "local_file" "guardrails_schema" {
  filename = "${path.module}/../../../../kong/plugins/ecommerce-guardrails/schema.lua"
}

module "kong" {
  source = "../../modules/kong"

  namespace      = "kong"
  release_name   = "kong"
  chart_version  = "2.33.0"
  kong_image_tag = "3.6"

  # IRSA for Bedrock access
  service_account_name     = "kong"
  service_account_role_arn = module.bedrock.kong_role_arn

  # Kong declarative config
  kong_config_yaml = data.local_file.kong_config.content

  # Custom plugins
  custom_plugins = {
    "bedrock-proxy" = {
      "handler.lua" = data.local_file.bedrock_proxy_handler.content
      "schema.lua"  = data.local_file.bedrock_proxy_schema.content
    }
    "token-meter" = {
      "handler.lua" = data.local_file.token_meter_handler.content
      "schema.lua"  = data.local_file.token_meter_schema.content
    }
    "ecommerce-guardrails" = {
      "handler.lua" = data.local_file.guardrails_handler.content
      "schema.lua"  = data.local_file.guardrails_schema.content
    }
  }

  # Dev environment settings
  enable_admin_api       = true  # Enable for dev, disable in prod
  enable_autoscaling     = false # Disable in dev for cost savings
  min_replicas           = 1
  enable_service_monitor = true

  # Resources (smaller for dev)
  resources = {
    requests = {
      cpu    = "250m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "1Gi"
    }
  }

  # ALB configuration for dev
  proxy_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
  }

  depends_on = [module.eks, module.bedrock]
}

# -----------------------------------------------------------------------------
# Kong Outputs
# -----------------------------------------------------------------------------

output "kong_namespace" {
  description = "Kong namespace"
  value       = module.kong.namespace
}

output "kong_proxy_service" {
  description = "Kong proxy service name"
  value       = module.kong.proxy_service_name
}

output "kong_ingress_class" {
  description = "Kong ingress class"
  value       = module.kong.ingress_class
}
