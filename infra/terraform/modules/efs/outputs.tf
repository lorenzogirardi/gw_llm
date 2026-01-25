# EFS Module Outputs

output "file_system_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.main.id
}

output "file_system_arn" {
  description = "EFS file system ARN"
  value       = aws_efs_file_system.main.arn
}

output "file_system_dns_name" {
  description = "EFS file system DNS name"
  value       = aws_efs_file_system.main.dns_name
}

output "access_point_id" {
  description = "EFS access point ID"
  value       = aws_efs_access_point.main.id
}

output "access_point_arn" {
  description = "EFS access point ARN"
  value       = aws_efs_access_point.main.arn
}

output "security_group_id" {
  description = "EFS security group ID"
  value       = aws_security_group.efs.id
}

output "mount_target_ids" {
  description = "List of EFS mount target IDs"
  value       = aws_efs_mount_target.main[*].id
}

output "mount_target_dns_names" {
  description = "List of EFS mount target DNS names"
  value       = aws_efs_mount_target.main[*].dns_name
}
