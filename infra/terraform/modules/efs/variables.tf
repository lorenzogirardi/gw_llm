# EFS Module Variables

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., poc, sandbox, prod)"
  type        = string
}

variable "name" {
  description = "Name for the EFS file system (e.g., victoria-metrics)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EFS will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for mount targets (one per AZ)"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to access EFS via NFS"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access EFS via NFS"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Performance
# -----------------------------------------------------------------------------

variable "performance_mode" {
  description = "EFS performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "Performance mode must be 'generalPurpose' or 'maxIO'."
  }
}

variable "throughput_mode" {
  description = "EFS throughput mode (bursting, provisioned, or elastic)"
  type        = string
  default     = "bursting"

  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.throughput_mode)
    error_message = "Throughput mode must be 'bursting', 'provisioned', or 'elastic'."
  }
}

variable "provisioned_throughput_mibps" {
  description = "Provisioned throughput in MiB/s (only when throughput_mode = provisioned)"
  type        = number
  default     = null
}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

variable "transition_to_ia" {
  description = "Transition to Infrequent Access after N days (AFTER_7_DAYS, AFTER_14_DAYS, etc.)"
  type        = string
  default     = "AFTER_30_DAYS"
}

# -----------------------------------------------------------------------------
# Access Point
# -----------------------------------------------------------------------------

variable "posix_user_uid" {
  description = "POSIX user ID for the access point"
  type        = number
  default     = 1000
}

variable "posix_user_gid" {
  description = "POSIX group ID for the access point"
  type        = number
  default     = 1000
}

variable "root_directory_path" {
  description = "Root directory path for the access point"
  type        = string
  default     = "/data"
}

# -----------------------------------------------------------------------------
# Backup
# -----------------------------------------------------------------------------

variable "enable_backup" {
  description = "Enable automatic backups via AWS Backup"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
