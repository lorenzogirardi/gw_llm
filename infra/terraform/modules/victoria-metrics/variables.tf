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

variable "kong_metrics_url" {
  description = "Kong metrics URL (ALB DNS)"
  type        = string
}

variable "kong_metrics_host" {
  description = "Kong metrics host (ALB DNS without protocol)"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
