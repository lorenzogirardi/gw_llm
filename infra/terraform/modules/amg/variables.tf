# AMG Module Variables

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
# Authentication
# -----------------------------------------------------------------------------

variable "authentication_providers" {
  description = "Authentication providers for Grafana (AWS_SSO, SAML)"
  type        = list(string)
  default     = ["AWS_SSO"]
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

variable "amp_workspace_arns" {
  description = "List of AMP workspace ARNs to allow querying"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Alerting
# -----------------------------------------------------------------------------

variable "enable_sns_alerting" {
  description = "Enable SNS alerting from Grafana"
  type        = bool
  default     = false
}

variable "sns_topic_arns" {
  description = "SNS topic ARNs for Grafana alerting"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# User Permissions
# -----------------------------------------------------------------------------

variable "admin_user_ids" {
  description = "User IDs to grant ADMIN role"
  type        = list(string)
  default     = []
}

variable "editor_user_ids" {
  description = "User IDs to grant EDITOR role"
  type        = list(string)
  default     = []
}

variable "viewer_user_ids" {
  description = "User IDs to grant VIEWER role"
  type        = list(string)
  default     = []
}
