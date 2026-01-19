# AMP Module Variables

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

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Alert Manager Configuration
# -----------------------------------------------------------------------------

variable "enable_alertmanager" {
  description = "Enable Alert Manager definition"
  type        = bool
  default     = false
}

variable "sns_topic_arn_critical" {
  description = "SNS topic ARN for critical alerts"
  type        = string
  default     = ""
}

variable "sns_topic_arn_warning" {
  description = "SNS topic ARN for warning alerts"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Recording Rules
# -----------------------------------------------------------------------------

variable "enable_recording_rules" {
  description = "Enable Prometheus recording rules"
  type        = bool
  default     = true
}
