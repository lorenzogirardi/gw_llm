# Kong LLM Gateway - Production Environment
#
# This configuration creates:
# - EKS cluster with managed node groups (multi-AZ)
# - IAM roles for Bedrock access (IRSA)
# - VPC with public/private subnets
# - Kong Gateway with HA configuration
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

  # Remote state (required for production)
  backend "s3" {
    bucket         = "kong-llm-gateway-terraform-state"
    key            = "kong-llm-gateway/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "kong-llm-gateway"
      Environment = "prod"
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
  default     = "kong-llm-gateway-prod"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "Instance types for worker nodes"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # VPC Configuration (creates new VPC)
  vpc_cidr             = "10.1.0.0/16"
  private_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnet_cidrs  = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]

  # Node Group - Production sizing
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = 3
  node_max_size       = 20
  node_capacity_type  = "ON_DEMAND"

  # Full logging for production
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Environment = "prod"
    Project     = "kong-llm-gateway"
    CostCenter  = "platform"
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

  # Production: Allow access to specific models only
  allowed_model_arns = [
    "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-5-sonnet-*",
    "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-sonnet-*",
    "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku-*",
    "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-text-*"
  ]

  enable_cloudwatch_logs    = true
  enable_cloudwatch_metrics = true
  cloudwatch_namespace      = "Kong/LLMGateway/Prod"

  tags = {
    Environment = "prod"
    Project     = "kong-llm-gateway"
  }

  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# Kong Gateway
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

  namespace            = "kong"
  release_name         = "kong"
  chart_version        = "2.33.0"
  kong_image_tag       = "3.6"

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

  # Production settings
  enable_admin_api       = false  # Disabled in production
  enable_autoscaling     = true
  min_replicas           = 3
  max_replicas           = 20
  target_cpu_utilization = 70
  enable_service_monitor = true
  enable_pdb             = true
  pdb_min_available      = "50%"
  enable_network_policy  = true

  # Production resources
  resources = {
    requests = {
      cpu    = "1000m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "4000m"
      memory = "4Gi"
    }
  }

  # NLB configuration for production
  proxy_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"                    = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"                  = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"         = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
  }

  depends_on = [module.eks, module.bedrock]
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

output "kong_namespace" {
  description = "Kong namespace"
  value       = module.kong.namespace
}

output "kong_proxy_service" {
  description = "Kong proxy service name"
  value       = module.kong.proxy_service_name
}
