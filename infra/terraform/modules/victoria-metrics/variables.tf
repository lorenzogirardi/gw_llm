# Victoria Metrics Module Variables

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
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
  description = "ALB listener ARN"
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN"
  type        = string
}

variable "scrape_targets" {
  description = "List of scrape targets with job name, host:port, and metrics path"
  type = list(object({
    job_name     = string
    target       = string
    metrics_path = string
  }))
  default = []
}

# Legacy variables for backward compatibility
variable "kong_metrics_url" {
  description = "Deprecated: Kong metrics URL"
  type        = string
  default     = ""
}

variable "kong_metrics_host" {
  description = "Deprecated: Kong metrics host"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Task Configuration
# -----------------------------------------------------------------------------

variable "task_cpu" {
  description = "Task CPU units"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Task memory in MB"
  type        = number
  default     = 512
}

variable "retention_days" {
  description = "Victoria Metrics data retention in days"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# EFS Configuration (optional)
# -----------------------------------------------------------------------------

variable "efs_file_system_id" {
  description = "EFS file system ID for persistent storage (optional)"
  type        = string
  default     = ""
}

variable "efs_access_point_id" {
  description = "EFS access point ID (required if efs_file_system_id is set)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for restricting internal access)"
  type        = string
  default     = ""
}
