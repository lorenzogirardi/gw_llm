# Grafana ECS Module Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "kong-llm-gateway"
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

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group ID"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALB listener ARN for path-based routing"
  type        = string
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------

variable "ecs_cluster_id" {
  description = "ECS Cluster ID"
  type        = string
}

variable "grafana_image" {
  description = "Grafana Docker image"
  type        = string
  default     = "grafana/grafana:10.2.0"
}

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

variable "use_spot" {
  description = "Use Fargate Spot"
  type        = bool
  default     = true
}

variable "desired_count" {
  description = "Desired number of Grafana tasks"
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Grafana Configuration
# -----------------------------------------------------------------------------

variable "grafana_root_url" {
  description = "Grafana root URL"
  type        = string
  default     = "%(protocol)s://%(domain)s/grafana/"
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password_secret_arn" {
  description = "Secrets Manager ARN for Grafana admin password (optional)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# AMP Integration
# -----------------------------------------------------------------------------

variable "amp_workspace_arn" {
  description = "AMP workspace ARN for Grafana to query"
  type        = string
}

variable "amp_remote_write_endpoint" {
  description = "AMP remote write endpoint (used to derive query endpoint for datasource)"
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
