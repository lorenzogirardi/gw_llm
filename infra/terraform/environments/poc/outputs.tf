# POC Environment Outputs

# -----------------------------------------------------------------------------
# Kong Gateway
# -----------------------------------------------------------------------------

output "kong_endpoint" {
  description = "Kong API endpoint URL"
  value       = module.ecs.kong_endpoint
}

output "kong_endpoint_https" {
  description = "Kong API endpoint URL (HTTPS)"
  value       = module.ecs.kong_endpoint_https
}

output "kong_alb_dns" {
  description = "Kong ALB DNS name"
  value       = module.ecs.alb_dns_name
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "${module.ecs.kong_endpoint}/grafana"
}

output "prometheus_endpoint" {
  description = "AMP Prometheus endpoint"
  value       = module.amp.workspace_endpoint
}

output "prometheus_remote_write_url" {
  description = "URL for Prometheus remote write"
  value       = module.amp.remote_write_url
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------

output "ecs_cluster_name" {
  description = "ECS Cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS Service name"
  value       = module.ecs.service_name
}

output "ecs_task_role_arn" {
  description = "ECS Task Role ARN (for Bedrock access)"
  value       = module.ecs.task_role_arn
}

# -----------------------------------------------------------------------------
# CloudWatch
# -----------------------------------------------------------------------------

output "kong_log_group" {
  description = "Kong CloudWatch Log Group"
  value       = module.ecs.log_group_name
}

output "amp_log_group" {
  description = "AMP CloudWatch Log Group"
  value       = module.amp.log_group_name
}

output "grafana_log_group" {
  description = "Grafana CloudWatch Log Group"
  value       = module.grafana.log_group_name
}

# -----------------------------------------------------------------------------
# VPC (if created)
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
}

# -----------------------------------------------------------------------------
# Quick Start Commands
# -----------------------------------------------------------------------------

output "quick_start" {
  description = "Quick start commands"
  value       = <<-EOT

    # Test Kong health
    curl ${module.ecs.kong_endpoint}/health

    # Test chat endpoint (requires API key configuration)
    curl -X POST ${module.ecs.kong_endpoint}/v1/chat/developer \
      -H "Content-Type: application/json" \
      -H "apikey: your-api-key" \
      -d '{"model":"claude-haiku","messages":[{"role":"user","content":"Hello"}]}'

    # View logs
    aws logs tail ${module.ecs.log_group_name} --follow

    # Open Grafana (default: admin/admin)
    open ${module.ecs.kong_endpoint}/grafana

  EOT
}
