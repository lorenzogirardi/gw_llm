# ECS Module Outputs

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

output "cluster_id" {
  description = "ECS Cluster ID"
  value       = aws_ecs_cluster.kong.id
}

output "cluster_name" {
  description = "ECS Cluster name"
  value       = aws_ecs_cluster.kong.name
}

output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.kong.arn
}

# -----------------------------------------------------------------------------
# Service
# -----------------------------------------------------------------------------

output "service_name" {
  description = "ECS Service name"
  value       = aws_ecs_service.kong.name
}

output "service_id" {
  description = "ECS Service ID"
  value       = aws_ecs_service.kong.id
}

output "task_definition_arn" {
  description = "Task Definition ARN"
  value       = aws_ecs_task_definition.kong.arn
}

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.kong.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.kong.dns_name
}

output "alb_zone_id" {
  description = "ALB Route53 zone ID"
  value       = aws_lb.kong.zone_id
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.kong.arn
}

output "alb_listener_http_arn" {
  description = "ALB HTTP Listener ARN"
  value       = aws_lb_listener.http.arn
}

output "alb_listener_https_arn" {
  description = "ALB HTTPS Listener ARN (if configured)"
  value       = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : null
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

output "kong_security_group_id" {
  description = "Kong ECS tasks security group ID"
  value       = aws_security_group.kong.id
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

output "task_role_arn" {
  description = "ECS Task Role ARN (for Bedrock access)"
  value       = aws_iam_role.ecs_task.arn
}

output "execution_role_arn" {
  description = "ECS Execution Role ARN"
  value       = aws_iam_role.ecs_execution.arn
}

# -----------------------------------------------------------------------------
# Endpoints
# -----------------------------------------------------------------------------

output "kong_endpoint" {
  description = "Kong API endpoint URL"
  value       = "http://${aws_lb.kong.dns_name}"
}

output "kong_endpoint_https" {
  description = "Kong API endpoint URL (HTTPS)"
  value       = var.certificate_arn != "" ? "https://${aws_lb.kong.dns_name}" : null
}

# -----------------------------------------------------------------------------
# CloudWatch
# -----------------------------------------------------------------------------

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.kong.name
}

output "log_group_arn" {
  description = "CloudWatch Log Group ARN"
  value       = aws_cloudwatch_log_group.kong.arn
}
