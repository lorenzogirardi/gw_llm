# POC Environment Variables

# -----------------------------------------------------------------------------
# AWS Configuration
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-1"
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
  default     = "10.10.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for VPC"
  type        = list(string)
  default     = ["us-west-1a", "us-west-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.10.101.0/24", "10.10.102.0/24"]
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
# Network Access
# -----------------------------------------------------------------------------

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the gateway"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# Kong Configuration
# -----------------------------------------------------------------------------

variable "kong_image" {
  description = "Kong Docker image"
  type        = string
  default     = "kong:3.6"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Grafana Configuration
# -----------------------------------------------------------------------------

variable "grafana_image" {
  description = "Grafana Docker image"
  type        = string
  default     = "grafana/grafana:11.0.0"
}

variable "grafana_auth_providers" {
  description = "Authentication providers for Grafana"
  type        = list(string)
  default     = ["AWS_SSO"]
}

variable "grafana_admin_user_ids" {
  description = "SSO user IDs for Grafana admin access"
  type        = list(string)
  default     = []
}

variable "grafana_admin_password_secret_arn" {
  description = "Secrets Manager ARN for Grafana admin password"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# LiteLLM Configuration
# -----------------------------------------------------------------------------

variable "litellm_master_key_secret_arn" {
  description = "Secrets Manager ARN for LiteLLM master key"
  type        = string
}

# -----------------------------------------------------------------------------
# Langfuse Configuration
# -----------------------------------------------------------------------------

variable "langfuse_database_url_secret_arn" {
  description = "Secrets Manager ARN for Langfuse DATABASE_URL"
  type        = string
  default     = "arn:aws:secretsmanager:us-west-1:170674040462:secret:langfuse-poc/database-url-1HPs4X"
}

variable "langfuse_nextauth_secret_arn" {
  description = "Secrets Manager ARN for Langfuse NEXTAUTH_SECRET"
  type        = string
  default     = "arn:aws:secretsmanager:us-west-1:170674040462:secret:langfuse-poc/nextauth-secret-UkBRRl"
}

variable "langfuse_salt_secret_arn" {
  description = "Secrets Manager ARN for Langfuse SALT"
  type        = string
  default     = "arn:aws:secretsmanager:us-west-1:170674040462:secret:langfuse-poc/salt-js5cAy"
}
