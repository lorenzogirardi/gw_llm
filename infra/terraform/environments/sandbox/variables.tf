# Sandbox Environment Variables
#
# Production-ready configuration for 100 concurrent users
# Region: us-east-1

# -----------------------------------------------------------------------------
# AWS Configuration
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------

variable "create_vpc" {
  description = "Create a new VPC (set to false to use existing)"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "Existing VPC ID (required if create_vpc = false)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for new VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for VPC (3 AZs for HA)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs (required if create_vpc = false)"
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "Existing public subnet IDs (required if create_vpc = false)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# NAT Gateway Configuration
# -----------------------------------------------------------------------------

variable "use_nat_gateway" {
  description = "Use NAT Gateway instead of NAT Instance (recommended for production)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Network Access
# -----------------------------------------------------------------------------

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the gateway"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# TLS Configuration
# -----------------------------------------------------------------------------

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# LiteLLM Configuration
# -----------------------------------------------------------------------------

variable "litellm_task_cpu" {
  description = "LiteLLM task CPU units"
  type        = number
  default     = 2048 # 2 vCPU
}

variable "litellm_task_memory" {
  description = "LiteLLM task memory in MB"
  type        = number
  default     = 4096 # 4 GB
}

variable "litellm_desired_count" {
  description = "Desired number of LiteLLM tasks"
  type        = number
  default     = 2
}

variable "litellm_min_capacity" {
  description = "Minimum number of LiteLLM tasks (auto-scaling)"
  type        = number
  default     = 2
}

variable "litellm_max_capacity" {
  description = "Maximum number of LiteLLM tasks (auto-scaling)"
  type        = number
  default     = 6
}

variable "litellm_master_key_secret_arn" {
  description = "Secrets Manager ARN for LiteLLM master key"
  type        = string
}

# -----------------------------------------------------------------------------
# Grafana Configuration
# -----------------------------------------------------------------------------

variable "grafana_image" {
  description = "Grafana Docker image"
  type        = string
  default     = "grafana/grafana:11.0.0"
}

variable "grafana_task_cpu" {
  description = "Grafana task CPU units"
  type        = number
  default     = 512
}

variable "grafana_task_memory" {
  description = "Grafana task memory in MB"
  type        = number
  default     = 1024
}

variable "grafana_desired_count" {
  description = "Desired number of Grafana tasks"
  type        = number
  default     = 2
}

variable "grafana_admin_password_secret_arn" {
  description = "Secrets Manager ARN for Grafana admin password"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Langfuse Configuration
# -----------------------------------------------------------------------------

variable "langfuse_task_cpu" {
  description = "Langfuse task CPU units"
  type        = number
  default     = 1024
}

variable "langfuse_task_memory" {
  description = "Langfuse task memory in MB"
  type        = number
  default     = 2048
}

variable "langfuse_desired_count" {
  description = "Desired number of Langfuse tasks"
  type        = number
  default     = 2
}

variable "langfuse_database_url_secret_arn" {
  description = "Secrets Manager ARN for Langfuse DATABASE_URL"
  type        = string
}

variable "langfuse_nextauth_secret_arn" {
  description = "Secrets Manager ARN for Langfuse NEXTAUTH_SECRET"
  type        = string
}

variable "langfuse_salt_secret_arn" {
  description = "Secrets Manager ARN for Langfuse SALT"
  type        = string
}

variable "langfuse_public_key_secret_arn" {
  description = "Secrets Manager ARN for Langfuse public key (for LiteLLM integration)"
  type        = string
  default     = ""
}

variable "langfuse_secret_key_secret_arn" {
  description = "Secrets Manager ARN for Langfuse secret key (for LiteLLM integration)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Victoria Metrics Configuration
# -----------------------------------------------------------------------------

variable "victoria_metrics_task_cpu" {
  description = "Victoria Metrics task CPU units"
  type        = number
  default     = 512
}

variable "victoria_metrics_task_memory" {
  description = "Victoria Metrics task memory in MB"
  type        = number
  default     = 1024
}

variable "victoria_metrics_retention_days" {
  description = "Victoria Metrics data retention in days"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# RDS Configuration
# -----------------------------------------------------------------------------

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large" # Production-grade
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "rds_max_allocated_storage" {
  description = "RDS max allocated storage for autoscaling in GB"
  type        = number
  default     = 200
}

variable "rds_multi_az" {
  description = "Enable RDS Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "rds_backup_retention_period" {
  description = "RDS backup retention in days"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# CloudFront & WAF Configuration
# -----------------------------------------------------------------------------

variable "enable_waf" {
  description = "Enable WAF for CloudFront"
  type        = bool
  default     = true
}

variable "enable_waf_bot_control" {
  description = "Enable Bot Control (additional cost ~$10/month)"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "WAF rate limit (requests per 5 minutes per IP)"
  type        = number
  default     = 1000
}

variable "admin_header_secret_arn" {
  description = "Secrets Manager ARN for admin header secret"
  type        = string
  default     = ""
}

variable "origin_verify_secret_arn" {
  description = "Secrets Manager ARN for origin verification secret (prevents direct ALB access bypass)"
  type        = string
}
