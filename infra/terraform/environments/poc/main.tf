# Kong LLM Gateway - POC Environment
#
# Low-cost POC deployment with:
# - ECS Fargate (Kong Gateway)
# - Amazon Managed Prometheus (AMP)
# - Grafana OSS on ECS (instead of AMG - not available in us-west-1)
# - Bedrock access (Opus 4.5, Sonnet, Haiku)
#
# Estimated cost: ~$20/month fixed + Bedrock usage

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state
  backend "s3" {
    bucket         = "kong-llm-gateway-tfstate-170674040462"
    key            = "poc/terraform.tfstate"
    region         = "us-west-1"
    encrypt        = true
    dynamodb_table = "kong-llm-gateway-tfstate-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "kong-llm-gateway"
      Environment = "poc"
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  project_name = "kong-llm-gateway"
  environment  = "poc"

  tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# VPC (use existing or create new)
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  count = var.create_vpc ? 1 : 0

  name = "${local.project_name}-${local.environment}"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = true  # Cost optimization for POC
  enable_dns_hostnames   = true
  enable_dns_support     = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Amazon Managed Prometheus (AMP)
# -----------------------------------------------------------------------------

module "amp" {
  source = "../../modules/amp"

  project_name = local.project_name
  environment  = local.environment

  log_retention_days     = 7
  enable_alertmanager    = false  # No alerting in POC
  enable_recording_rules = false  # Temporarily disabled due to API conflict

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ECS Fargate (Kong Gateway)
# -----------------------------------------------------------------------------

module "ecs" {
  source = "../../modules/ecs"

  project_name = local.project_name
  environment  = local.environment

  # Network
  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  public_subnet_ids  = var.create_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids
  allowed_cidr_blocks = var.allowed_cidr_blocks

  # Task configuration (minimal for POC)
  kong_image     = var.kong_image
  task_cpu       = 256   # 0.25 vCPU
  task_memory    = 512   # 512 MB
  desired_count  = 1
  use_spot       = false  # Use regular Fargate for stability

  # Scaling disabled for POC
  enable_autoscaling = false

  # ALB
  internal_alb                = false
  certificate_arn             = var.certificate_arn
  enable_deletion_protection  = false  # Easy cleanup for POC

  # Observability
  enable_container_insights = true
  log_retention_days        = 7
  amp_workspace_id          = module.amp.workspace_id
  enable_amp_write          = false  # Disabled - ADOT causing issues

  # Bedrock models
  allowed_model_arns = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-20250514-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
  ]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Grafana on ECS (instead of AMG - not available in us-west-1)
# -----------------------------------------------------------------------------

module "grafana" {
  source = "../../modules/grafana-ecs"

  project_name = local.project_name
  environment  = local.environment

  # Network
  vpc_id                = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnet_ids    = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  alb_security_group_id = module.ecs.alb_security_group_id
  alb_listener_arn      = module.ecs.alb_listener_http_arn

  # ECS
  ecs_cluster_id = module.ecs.cluster_id
  grafana_image  = var.grafana_image
  use_spot       = true

  # AMP integration
  amp_workspace_arn         = module.amp.workspace_arn
  amp_remote_write_endpoint = module.amp.remote_write_url

  # Admin password from Secrets Manager
  grafana_admin_password_secret_arn = var.grafana_admin_password_secret_arn

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Victoria Metrics (Prometheus-compatible metrics storage)
# -----------------------------------------------------------------------------

module "victoria_metrics" {
  source = "../../modules/victoria-metrics"

  project_name = local.project_name
  environment  = local.environment

  # Network
  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids

  # ECS
  ecs_cluster_id        = module.ecs.cluster_id
  alb_security_group_id = module.ecs.alb_security_group_id
  alb_listener_arn      = module.ecs.alb_listener_http_arn
  alb_arn               = module.ecs.alb_arn

  # Kong metrics endpoint
  kong_metrics_url  = "http://${module.ecs.alb_dns_name}:8100"
  kong_metrics_host = module.ecs.alb_dns_name

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CloudFront (HTTPS termination)
# -----------------------------------------------------------------------------

module "cloudfront" {
  source = "../../modules/cloudfront"

  project_name = local.project_name
  environment  = local.environment

  # Origin
  alb_dns_name = module.ecs.alb_dns_name

  # Settings
  price_class = "PriceClass_100"  # US, Canada, Europe only
  enable_waf  = false             # Disable WAF for POC (cost savings)

  tags = local.tags
}
