# CloudFront Module Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Origin
# -----------------------------------------------------------------------------

variable "alb_dns_name" {
  description = "ALB DNS name to use as origin"
  type        = string
}

# -----------------------------------------------------------------------------
# Distribution Settings
# -----------------------------------------------------------------------------

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100" # US, Canada, Europe only (cheapest)
}

variable "geo_restriction_type" {
  description = "Geo restriction type (none, whitelist, blacklist)"
  type        = string
  default     = "none"
}

variable "geo_restriction_locations" {
  description = "List of country codes for geo restriction"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------

variable "block_admin_endpoints" {
  description = "Block admin endpoints (/user/*, /key/*, /model/*, /spend/*) from CloudFront"
  type        = bool
  default     = true
}

variable "admin_secret_header" {
  description = "Secret value for X-Admin-Secret header to bypass admin endpoint blocking"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# WAF
# -----------------------------------------------------------------------------

variable "enable_waf" {
  description = "Enable WAF for CloudFront"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "WAF rate limit (requests per 5 minutes per IP)"
  type        = number
  default     = 2000
}

variable "enable_waf_common_rules" {
  description = "Enable AWS Managed Common Rule Set (OWASP Top 10)"
  type        = bool
  default     = true
}

variable "enable_waf_known_bad_inputs" {
  description = "Enable AWS Managed Known Bad Inputs Rule Set (Log4j, Java deserialization)"
  type        = bool
  default     = true
}

variable "enable_waf_ip_reputation" {
  description = "Enable AWS Managed IP Reputation List"
  type        = bool
  default     = true
}

variable "enable_waf_bot_control" {
  description = "Enable AWS Managed Bot Control Rule Set (additional cost)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Origin Security
# -----------------------------------------------------------------------------

variable "origin_verify_secret" {
  description = "Secret header value to verify requests come from CloudFront (prevents direct ALB access)"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Langfuse
# -----------------------------------------------------------------------------

variable "enable_langfuse" {
  description = "Enable Langfuse routing via CloudFront"
  type        = bool
  default     = false
}
