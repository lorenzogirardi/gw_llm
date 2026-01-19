# Bedrock Module Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  type        = string
}

variable "oidc_issuer" {
  description = "OIDC issuer URL (without https://)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Kong"
  type        = string
  default     = "kong"
}

variable "service_account" {
  description = "Kubernetes service account name for Kong"
  type        = string
  default     = "kong"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Bedrock Model Access
variable "allowed_model_arns" {
  description = "List of Bedrock model ARNs to allow access to"
  type        = list(string)
  default = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-5-sonnet-*",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet-*",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-*",
    "arn:aws:bedrock:*::foundation-model/amazon.titan-text-*"
  ]
}

variable "bedrock_region" {
  description = "AWS region for Bedrock access"
  type        = string
  default     = "us-east-1"
}

# CloudWatch Integration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs access for Kong"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_metrics" {
  description = "Enable CloudWatch Metrics access for token tracking"
  type        = bool
  default     = true
}

variable "cloudwatch_namespace" {
  description = "CloudWatch namespace for custom metrics"
  type        = string
  default     = "Kong/LLMGateway"
}
