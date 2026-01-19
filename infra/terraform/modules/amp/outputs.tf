# AMP Module Outputs

output "workspace_id" {
  description = "AMP Workspace ID"
  value       = aws_prometheus_workspace.kong.id
}

output "workspace_arn" {
  description = "AMP Workspace ARN"
  value       = aws_prometheus_workspace.kong.arn
}

output "workspace_endpoint" {
  description = "AMP Workspace Prometheus endpoint"
  value       = aws_prometheus_workspace.kong.prometheus_endpoint
}

output "remote_write_url" {
  description = "URL for Prometheus remote write"
  value       = "${aws_prometheus_workspace.kong.prometheus_endpoint}api/v1/remote_write"
}

output "query_url" {
  description = "URL for Prometheus queries"
  value       = "${aws_prometheus_workspace.kong.prometheus_endpoint}api/v1/query"
}

output "log_group_name" {
  description = "CloudWatch Log Group name for AMP"
  value       = aws_cloudwatch_log_group.amp.name
}

output "log_group_arn" {
  description = "CloudWatch Log Group ARN for AMP"
  value       = aws_cloudwatch_log_group.amp.arn
}
