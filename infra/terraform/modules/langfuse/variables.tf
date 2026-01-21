# Langfuse Module Variables

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., poc, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group ID"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALB listener ARN for adding rules (not used, kept for compatibility)"
  type        = string
  default     = ""
}

variable "alb_arn" {
  description = "ALB ARN for creating dedicated Langfuse listener"
  type        = string
}

variable "database_url_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DATABASE_URL"
  type        = string
}

variable "nextauth_secret_arn" {
  description = "ARN of the Secrets Manager secret containing NEXTAUTH_SECRET"
  type        = string
}

variable "salt_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SALT"
  type        = string
}

# -----------------------------------------------------------------------------
# Optional Variables
# -----------------------------------------------------------------------------

variable "langfuse_image" {
  description = "Langfuse Docker image"
  type        = string
  default     = "langfuse/langfuse:latest"
}

variable "langfuse_url" {
  description = "Public URL for Langfuse (NEXTAUTH_URL)"
  type        = string
  default     = "http://localhost:3000"
}

variable "task_cpu" {
  description = "CPU units for Langfuse task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Memory for Langfuse task in MB"
  type        = number
  default     = 1024
}

variable "use_spot" {
  description = "Use Fargate Spot for cost savings"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
