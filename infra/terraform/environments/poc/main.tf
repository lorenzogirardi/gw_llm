# LLM Gateway - POC Environment
#
# Low-cost POC deployment with:
# - ECS Fargate (LiteLLM Gateway)
# - Victoria Metrics (Prometheus-compatible)
# - Grafana OSS on ECS
# - NAT Instance (t3.nano) instead of NAT Gateway
# - Bedrock access (Haiku 4.5, Opus, Sonnet)
#
# Estimated cost: ~$54/month fixed + Bedrock usage

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

  enable_nat_gateway   = false # Using NAT instance instead
  single_nat_gateway   = true  # Single route table for all private subnets
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Amazon Managed Prometheus (AMP) - DISABLED for cost savings
# -----------------------------------------------------------------------------
# module "amp" {
#   source = "../../modules/amp"
#
#   project_name = local.project_name
#   environment  = local.environment
#
#   log_retention_days     = 7
#   enable_alertmanager    = false
#   enable_recording_rules = false
#
#   tags = local.tags
# }

# -----------------------------------------------------------------------------
# NAT Instance (cost-effective alternative to NAT Gateway)
# -----------------------------------------------------------------------------

# fck-nat AMI - pre-configured NAT instance (no iptables setup needed)
# https://fck-nat.dev/
data "aws_ami" "fck_nat" {
  most_recent = true
  owners      = ["568608671756"] # fck-nat owner

  filter {
    name   = "name"
    values = ["fck-nat-al2023-*-x86_64*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_security_group" "nat_instance" {
  name        = "nat-instance-sg" # Match existing CLI-created SG
  description = "Security group for NAT instance"
  vpc_id      = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id

  ingress {
    description = "Allow all from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.project_name}-nat-instance-${local.environment}"
  })
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.fck_nat.id
  instance_type               = "t3.nano"
  subnet_id                   = var.create_vpc ? module.vpc[0].public_subnets[0] : var.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.nat_instance.id]
  associate_public_ip_address = true
  source_dest_check           = false

  # Enforce IMDSv2 (CKV_AWS_79)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  # fck-nat comes pre-configured, no user_data needed

  tags = merge(local.tags, {
    Name = "${local.project_name}-nat-instance-${local.environment}"
  })

  lifecycle {
    ignore_changes = [ami] # Don't replace on AMI updates
  }
}

resource "aws_route" "private_nat" {
  count = var.create_vpc ? length(module.vpc[0].private_route_table_ids) : 0

  route_table_id         = module.vpc[0].private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# -----------------------------------------------------------------------------
# ECS Fargate (Kong Gateway)
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

  # Task configuration (minimal for POC)
  kong_image    = var.kong_image
  task_cpu      = 256 # 0.25 vCPU
  task_memory   = 512 # 512 MB
  desired_count = 1
  use_spot      = false # Use regular Fargate for stability

  # Scaling disabled for POC
  enable_autoscaling = false

  # ALB
  internal_alb               = false
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = false # Easy cleanup for POC

  # Observability
  enable_container_insights = true
  log_retention_days        = 7
  amp_workspace_id          = ""    # AMP disabled
  enable_amp_write          = false # AMP disabled

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

  # AMP integration - disabled, using Victoria Metrics
  amp_workspace_arn         = ""
  amp_remote_write_endpoint = ""

  # Admin password from Secrets Manager
  grafana_admin_password_secret_arn = var.grafana_admin_password_secret_arn

  tags = local.tags
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL (for LiteLLM user management)
# -----------------------------------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  project_name = local.project_name
  environment  = local.environment

  # Network
  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids

  # Allow connections from VPC (LiteLLM and other services)
  allowed_cidr_blocks = [var.vpc_cidr]

  # Instance config (minimal for POC)
  instance_class    = "db.t4g.micro" # ~$12/month
  allocated_storage = 20
  engine_version    = "16.6"

  # POC settings (not production-ready)
  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 1

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

  # Scrape targets - LiteLLM metrics (trailing slash required)
  scrape_targets = [
    {
      job_name     = "litellm"
      target       = "${module.ecs.alb_dns_name}:80"
      metrics_path = "/metrics/"
    }
  ]

  tags = local.tags

  depends_on = [module.litellm]
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
  price_class     = "PriceClass_100" # US, Canada, Europe only
  enable_waf      = false            # Disable WAF for POC (cost savings)
  enable_langfuse = true             # Enable Langfuse via /langfuse/*

  tags = local.tags
}

# -----------------------------------------------------------------------------
# LiteLLM Gateway (OpenAI-compatible proxy for Bedrock)
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
  task_cpu       = 1024
  task_memory    = 2048
  desired_count  = 1
  use_spot       = false # Use regular Fargate for stability

  # Secrets
  master_key_secret_arn   = var.litellm_master_key_secret_arn
  database_url_secret_arn = module.rds.database_url_secret_arn

  # Langfuse integration
  langfuse_host                  = "https://d18l8nt8fin3hz.cloudfront.net"
  langfuse_public_key_secret_arn = "arn:aws:secretsmanager:us-west-1:170674040462:secret:kong-llm-gateway-poc/langfuse-public-key-JMZGH3"
  langfuse_secret_key_secret_arn = "arn:aws:secretsmanager:us-west-1:170674040462:secret:kong-llm-gateway-poc/langfuse-secret-key-mWJMJP"

  # Bedrock models
  allowed_bedrock_models = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-5-20251101-v1:0",
    "arn:aws:bedrock:*:*:inference-profile/*"
  ]

  # LiteLLM config - using US inference profiles
  litellm_config = <<-YAML
model_list:
  # Claude Haiku 4.5 - default model (using US inference profile)
  - model_name: claude-haiku-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_region_name: us-west-1
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.0000008
      output_cost_per_token: 0.000004

  # Claude Sonnet 4.5 (using US inference profile)
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_region_name: us-west-1
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.000003
      output_cost_per_token: 0.000015

  # Claude Opus 4.5 (using US inference profile)
  - model_name: claude-opus-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-opus-4-5-20251101-v1:0
      aws_region_name: us-west-1
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.000015
      output_cost_per_token: 0.000075

  # Aliases for Claude Code compatibility
  - model_name: claude-3-5-sonnet-20241022
    litellm_params:
      model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_region_name: us-west-1

  - model_name: claude-sonnet-4-5-20250514
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_region_name: us-west-1

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
  max_budget: 100
  budget_duration: 1mo
YAML

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Langfuse (LLM Observability)
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
  task_cpu       = 512
  task_memory    = 1024
  use_spot       = true

  # Secrets
  database_url_secret_arn = var.langfuse_database_url_secret_arn
  nextauth_secret_arn     = var.langfuse_nextauth_secret_arn
  salt_secret_arn         = var.langfuse_salt_secret_arn

  tags = local.tags

  depends_on = [module.rds, module.cloudfront]
}
