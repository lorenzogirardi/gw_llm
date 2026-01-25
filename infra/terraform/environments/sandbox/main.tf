# Stargate LLM Gateway - Sandbox Environment
#
# Production-ready deployment for 100 concurrent users with:
# - ECS Fargate (LiteLLM Gateway with auto-scaling)
# - Victoria Metrics with EFS persistent storage
# - Grafana OSS on ECS (2 replicas)
# - Langfuse for LLM observability (2 replicas)
# - RDS PostgreSQL Multi-AZ (db.r6g.large)
# - NAT Gateway (high availability)
# - CloudFront with WAF (Bot Control + IP Reputation)
# - Bedrock access (Claude models)
#
# Region: us-east-1
# Estimated cost: ~$493/month fixed + Bedrock usage

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "stargate-llm-gateway"
      Environment = "sandbox"
      ManagedBy   = "terraform"
    }
  }
}

# CloudFront requires us-east-1 for WAF
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "stargate-llm-gateway"
      Environment = "sandbox"
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  project_name = "stargate-llm-gateway"
  environment  = "sandbox"

  tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# VPC (3 AZs for High Availability)
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

  # NAT Gateway for production (high availability)
  enable_nat_gateway   = var.use_nat_gateway
  single_nat_gateway   = true # Single NAT Gateway (cost-effective for sandbox)
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ECS Fargate Cluster & ALB (shared infrastructure)
# -----------------------------------------------------------------------------

module "ecs" {
  source = "../../modules/ecs"

  project_name = local.project_name
  environment  = local.environment

  # Network
  vpc_id              = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  vpc_cidr            = var.vpc_cidr
  private_subnet_ids  = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  public_subnet_ids   = var.create_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids
  allowed_cidr_blocks = var.allowed_cidr_blocks

  # Task configuration (base cluster)
  task_cpu      = 256
  task_memory   = 512
  desired_count = 1
  use_spot      = false # Regular Fargate for stability

  # Scaling disabled for base cluster (services have their own scaling)
  enable_autoscaling = false

  # ALB
  internal_alb               = false
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = true # Production protection
  restrict_to_cloudfront     = false

  # Observability
  enable_container_insights = true
  log_retention_days        = 14 # Longer retention for sandbox
  amp_workspace_id          = ""
  enable_amp_write          = false

  # Bedrock models (all Claude models)
  allowed_model_arns = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-20250514-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-5-20251101-v1:0"
  ]

  # Origin verification (prevents direct ALB access)
  origin_verify_secret = data.aws_secretsmanager_secret_version.origin_verify.secret_string

  tags = local.tags
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL (Multi-AZ for High Availability)
# -----------------------------------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  project_name = local.project_name
  environment  = local.environment

  # Network
  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids

  # Allow connections from VPC
  allowed_cidr_blocks = [var.vpc_cidr]

  # Instance config (production-grade)
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  engine_version    = "16.6"

  # High Availability settings
  multi_az                = var.rds_multi_az
  deletion_protection     = true
  skip_final_snapshot     = false
  backup_retention_period = var.rds_backup_retention_period

  tags = local.tags
}

# -----------------------------------------------------------------------------
# EFS for Victoria Metrics Persistent Storage
# -----------------------------------------------------------------------------

module "efs_victoria_metrics" {
  source = "../../modules/efs"

  project_name = local.project_name
  environment  = local.environment
  name         = "victoria-metrics"

  vpc_id     = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids

  # Allow access from Victoria Metrics security group
  allowed_cidr_blocks = [var.vpc_cidr]

  # Performance
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  # Access point for Victoria Metrics
  posix_user_uid      = 1000
  posix_user_gid      = 1000
  root_directory_path = "/victoria-metrics-data"

  # Backup enabled
  enable_backup = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Victoria Metrics (with EFS Persistent Storage)
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

  # Task configuration
  task_cpu       = var.victoria_metrics_task_cpu
  task_memory    = var.victoria_metrics_task_memory
  retention_days = var.victoria_metrics_retention_days

  # EFS for persistent storage
  efs_file_system_id  = module.efs_victoria_metrics.file_system_id
  efs_access_point_id = module.efs_victoria_metrics.access_point_id

  # VPC CIDR for internal-only access
  vpc_cidr = var.vpc_cidr

  # Scrape targets - LiteLLM metrics
  scrape_targets = [
    {
      job_name     = "litellm"
      target       = "${module.ecs.alb_dns_name}:80"
      metrics_path = "/metrics/"
    }
  ]

  tags = local.tags

  depends_on = [module.litellm, module.efs_victoria_metrics]
}

# -----------------------------------------------------------------------------
# Grafana on ECS (2 replicas for HA)
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
  task_cpu       = var.grafana_task_cpu
  task_memory    = var.grafana_task_memory
  desired_count  = var.grafana_desired_count
  use_spot       = false # Regular Fargate for stability

  # AMP integration - disabled, using Victoria Metrics
  amp_workspace_arn         = ""
  amp_remote_write_endpoint = ""

  # Admin password from Secrets Manager
  grafana_admin_password_secret_arn = var.grafana_admin_password_secret_arn

  # Origin verification (prevents direct ALB access)
  origin_verify_secret = data.aws_secretsmanager_secret_version.origin_verify.secret_string

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Secrets for CloudFront Security
# -----------------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "admin_header" {
  count     = var.admin_header_secret_arn != "" ? 1 : 0
  secret_id = var.admin_header_secret_arn
}

data "aws_secretsmanager_secret_version" "origin_verify" {
  secret_id = var.origin_verify_secret_arn
}

# -----------------------------------------------------------------------------
# CloudFront (HTTPS termination with WAF)
# -----------------------------------------------------------------------------

module "cloudfront" {
  source = "../../modules/cloudfront"

  project_name = local.project_name
  environment  = local.environment

  # Origin
  alb_dns_name = module.ecs.alb_dns_name

  # Settings
  price_class     = "PriceClass_100" # US, Canada, Europe only
  enable_langfuse = true

  # WAF (Advanced rules for production)
  enable_waf                  = var.enable_waf
  enable_waf_common_rules     = true
  enable_waf_known_bad_inputs = true
  enable_waf_ip_reputation    = true
  enable_waf_bot_control      = var.enable_waf_bot_control
  waf_rate_limit              = var.waf_rate_limit

  # Admin secret header
  admin_secret_header = var.admin_header_secret_arn != "" ? data.aws_secretsmanager_secret_version.admin_header[0].secret_string : ""

  # Origin verification (prevents direct ALB access)
  origin_verify_secret = data.aws_secretsmanager_secret_version.origin_verify.secret_string

  tags = local.tags
}

# -----------------------------------------------------------------------------
# LiteLLM Gateway (with Auto-Scaling)
# -----------------------------------------------------------------------------

module "litellm" {
  source = "../../modules/litellm"

  project_name = local.project_name
  environment  = local.environment

  # Network
  vpc_id                = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  vpc_cidr              = var.vpc_cidr
  private_subnet_ids    = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  alb_security_group_id = module.ecs.alb_security_group_id
  alb_listener_arn      = module.ecs.alb_listener_http_arn
  alb_arn               = module.ecs.alb_arn

  # ECS
  ecs_cluster_id = module.ecs.cluster_id
  task_cpu       = var.litellm_task_cpu
  task_memory    = var.litellm_task_memory
  desired_count  = var.litellm_desired_count
  use_spot       = false # Regular Fargate for stability

  # Auto-scaling
  enable_autoscaling     = true
  min_capacity           = var.litellm_min_capacity
  max_capacity           = var.litellm_max_capacity
  autoscaling_cpu_target = 70
  scale_in_cooldown      = 300
  scale_out_cooldown     = 60

  # Secrets
  master_key_secret_arn   = var.litellm_master_key_secret_arn
  database_url_secret_arn = module.rds.database_url_secret_arn

  # Langfuse integration
  langfuse_host                  = module.cloudfront.langfuse_url
  langfuse_public_key_secret_arn = var.langfuse_public_key_secret_arn
  langfuse_secret_key_secret_arn = var.langfuse_secret_key_secret_arn

  # Origin verification (prevents direct ALB access)
  origin_verify_secret = data.aws_secretsmanager_secret_version.origin_verify.secret_string

  # Bedrock models (using US inference profiles)
  allowed_bedrock_models = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-5-20251101-v1:0",
    "arn:aws:bedrock:*:*:inference-profile/*"
  ]

  # LiteLLM config - using US inference profiles
  litellm_config = <<-YAML
model_list:
  # Claude Haiku 4.5 - fast, cost-effective
  - model_name: claude-haiku-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_region_name: us-east-1
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.0000008
      output_cost_per_token: 0.000004

  # Claude Sonnet 4.5 - balanced performance
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_region_name: us-east-1
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.000003
      output_cost_per_token: 0.000015

  # Claude Opus 4.5 - highest capability
  - model_name: claude-opus-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-opus-4-5-20251101-v1:0
      aws_region_name: us-east-1
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.000015
      output_cost_per_token: 0.000075

  # Aliases for Claude Code compatibility
  - model_name: claude-3-5-sonnet-20241022
    litellm_params:
      model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_region_name: us-east-1

  - model_name: claude-sonnet-4-5-20250514
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_region_name: us-east-1

litellm_settings:
  drop_params: true
  set_verbose: false
  cache: false
  callbacks:
    - prometheus
    - langfuse
  success_callback:
    - langfuse
  failure_callback:
    - langfuse

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  alerting:
    - prometheus
  store_model_in_db: true
  max_budget: 500
  budget_duration: 1mo
YAML

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Langfuse (2 replicas for HA)
# -----------------------------------------------------------------------------

module "langfuse" {
  source = "../../modules/langfuse"

  project_name = local.project_name
  environment  = local.environment

  # Network
  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids

  # ECS
  ecs_cluster_id        = module.ecs.cluster_id
  alb_security_group_id = module.ecs.alb_security_group_id
  alb_arn               = module.ecs.alb_arn

  # Langfuse settings
  langfuse_image = "langfuse/langfuse:2"
  langfuse_url   = module.cloudfront.langfuse_url
  task_cpu       = var.langfuse_task_cpu
  task_memory    = var.langfuse_task_memory
  desired_count  = var.langfuse_desired_count
  use_spot       = false # Regular Fargate for stability

  # Secrets
  database_url_secret_arn = var.langfuse_database_url_secret_arn
  nextauth_secret_arn     = var.langfuse_nextauth_secret_arn
  salt_secret_arn         = var.langfuse_salt_secret_arn

  # Origin verification (prevents direct ALB access)
  origin_verify_secret = data.aws_secretsmanager_secret_version.origin_verify.secret_string

  # VPC CIDR for internal traffic (LiteLLM callbacks)
  vpc_cidr = var.vpc_cidr

  tags = local.tags

  depends_on = [module.rds, module.cloudfront]
}
