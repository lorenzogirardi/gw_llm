# LiteLLM Module Outputs

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.litellm.name
}

output "task_definition_arn" {
  description = "Task definition ARN"
  value       = aws_ecs_task_definition.litellm.arn
}

output "security_group_id" {
  description = "Security group ID for LiteLLM tasks"
  value       = aws_security_group.litellm.id
}

output "target_group_arn" {
  description = "ALB target group ARN"
  value       = aws_lb_target_group.litellm.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.litellm.name
}

output "task_role_arn" {
  description = "Task role ARN (for Bedrock access)"
  value       = aws_iam_role.litellm_task.arn
}

output "metrics_endpoint" {
  description = "Prometheus metrics endpoint path"
  value       = "/metrics"
}
