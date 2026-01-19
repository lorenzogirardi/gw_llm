# Grafana ECS Module Outputs

output "service_name" {
  description = "Grafana ECS Service name"
  value       = aws_ecs_service.grafana.name
}

output "task_definition_arn" {
  description = "Task Definition ARN"
  value       = aws_ecs_task_definition.grafana.arn
}

output "security_group_id" {
  description = "Grafana security group ID"
  value       = aws_security_group.grafana.id
}

output "target_group_arn" {
  description = "Grafana Target Group ARN"
  value       = aws_lb_target_group.grafana.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.grafana.name
}

output "grafana_path" {
  description = "Grafana URL path"
  value       = "/grafana"
}
