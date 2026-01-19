# Victoria Metrics Module Outputs

output "endpoint" {
  description = "Victoria Metrics Prometheus API endpoint"
  value       = "http://${var.kong_metrics_host}:9090"
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.victoria.name
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.victoria.id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.victoria.arn
}
