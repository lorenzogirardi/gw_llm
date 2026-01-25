# EFS Module for Persistent Storage
#
# Creates an EFS file system with:
# - Encryption at rest (AES-256)
# - Multi-AZ mount targets
# - Access point for container access
# - Security group for NFS traffic

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# EFS File System
# -----------------------------------------------------------------------------

resource "aws_efs_file_system" "main" {
  creation_token = "${var.project_name}-${var.name}-${var.environment}"
  encrypted      = true

  performance_mode                = var.performance_mode
  throughput_mode                 = var.throughput_mode
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_mibps : null

  lifecycle_policy {
    transition_to_ia = var.transition_to_ia
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.name}-${var.environment}"
  })
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-${var.name}-efs-${var.environment}"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    description     = "NFS from allowed security groups"
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      from_port   = 2049
      to_port     = 2049
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
      description = "NFS from allowed CIDR blocks"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.name}-efs-${var.environment}"
  })
}

# -----------------------------------------------------------------------------
# Mount Targets (one per subnet for Multi-AZ)
# -----------------------------------------------------------------------------

resource "aws_efs_mount_target" "main" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# -----------------------------------------------------------------------------
# Access Point (for container access with specific UID/GID)
# -----------------------------------------------------------------------------

resource "aws_efs_access_point" "main" {
  file_system_id = aws_efs_file_system.main.id

  posix_user {
    uid = var.posix_user_uid
    gid = var.posix_user_gid
  }

  root_directory {
    path = var.root_directory_path

    creation_info {
      owner_uid   = var.posix_user_uid
      owner_gid   = var.posix_user_gid
      permissions = "755"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.name}-${var.environment}"
  })
}

# -----------------------------------------------------------------------------
# Backup Policy (optional)
# -----------------------------------------------------------------------------

resource "aws_efs_backup_policy" "main" {
  count = var.enable_backup ? 1 : 0

  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = "ENABLED"
  }
}
