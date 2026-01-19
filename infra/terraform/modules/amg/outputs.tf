# AMG Module Outputs

output "workspace_id" {
  description = "AMG Workspace ID"
  value       = aws_grafana_workspace.kong.id
}

output "workspace_arn" {
  description = "AMG Workspace ARN"
  value       = aws_grafana_workspace.kong.arn
}

output "workspace_endpoint" {
  description = "AMG Workspace URL"
  value       = aws_grafana_workspace.kong.endpoint
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "https://${aws_grafana_workspace.kong.endpoint}"
}

output "grafana_role_arn" {
  description = "IAM role ARN used by Grafana"
  value       = aws_iam_role.grafana.arn
}

output "grafana_role_name" {
  description = "IAM role name used by Grafana"
  value       = aws_iam_role.grafana.name
}
