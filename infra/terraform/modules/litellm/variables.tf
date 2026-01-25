# LiteLLM ECS Module Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "llm-gateway"
}

variable "environment" {
  description = "Environment name (poc, dev, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group ID"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALB listener ARN for routing"
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN"
  type        = string
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------

variable "ecs_cluster_id" {
  description = "ECS Cluster ID"
  type        = string
}

variable "litellm_image" {
  description = "LiteLLM Docker image"
  type        = string
  default     = "ghcr.io/berriai/litellm:main-latest"
}

variable "task_cpu" {
  description = "Task CPU units"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Task memory in MB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Auto-Scaling Configuration
# -----------------------------------------------------------------------------

variable "enable_autoscaling" {
  description = "Enable auto-scaling for LiteLLM service"
  type        = bool
  default     = false
}

variable "min_capacity" {
  description = "Minimum number of tasks (auto-scaling)"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks (auto-scaling)"
  type        = number
  default     = 4
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

variable "scale_in_cooldown" {
  description = "Cooldown period in seconds before scaling in"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Cooldown period in seconds before scaling out"
  type        = number
  default     = 60
}

variable "use_spot" {
  description = "Use Fargate Spot"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# LiteLLM Configuration
# -----------------------------------------------------------------------------

variable "master_key_secret_arn" {
  description = "Secrets Manager ARN for LiteLLM master key"
  type        = string
}

variable "database_url_secret_arn" {
  description = "Secrets Manager ARN for database URL (optional, uses SQLite if empty)"
  type        = string
  default     = ""
}

variable "litellm_config" {
  description = "LiteLLM config.yaml content"
  type        = string
}

# -----------------------------------------------------------------------------
# Bedrock Configuration
# -----------------------------------------------------------------------------

variable "allowed_bedrock_models" {
  description = "List of Bedrock model ARNs to allow"
  type        = list(string)
  default = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-5-haiku-20241022-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250514-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-5-20250514-v1:0",
    "arn:aws:bedrock:*:*:inference-profile/*"
  ]
}

# -----------------------------------------------------------------------------
# Langfuse Integration (optional)
# -----------------------------------------------------------------------------

variable "langfuse_host" {
  description = "Langfuse host URL (optional, enables Langfuse tracing)"
  type        = string
  default     = ""
}

variable "langfuse_public_key_secret_arn" {
  description = "Secrets Manager ARN for Langfuse public key"
  type        = string
  default     = ""
}

variable "langfuse_secret_key_secret_arn" {
  description = "Secrets Manager ARN for Langfuse secret key"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Origin Security
# -----------------------------------------------------------------------------

variable "origin_verify_secret" {
  description = "Secret header value to verify requests come from CloudFront (X-Origin-Verify header)"
  type        = string
  default     = ""
  sensitive   = true
}
