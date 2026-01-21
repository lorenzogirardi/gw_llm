# Langfuse Module Outputs

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.langfuse.name
}

output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.langfuse.arn
}

output "security_group_id" {
  description = "Security group ID for Langfuse"
  value       = aws_security_group.langfuse.id
}

output "target_group_arn" {
  description = "ALB target group ARN"
  value       = aws_lb_target_group.langfuse.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.langfuse.name
}
