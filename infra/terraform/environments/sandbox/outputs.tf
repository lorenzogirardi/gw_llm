# Sandbox Environment Outputs

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = var.create_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------

output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = module.ecs.cluster_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.ecs.alb_dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = module.ecs.alb_arn
}

# -----------------------------------------------------------------------------
# CloudFront
# -----------------------------------------------------------------------------

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.cloudfront.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.cloudfront.distribution_id
}

output "api_endpoint" {
  description = "API endpoint URL (CloudFront)"
  value       = "https://${module.cloudfront.domain_name}"
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "https://${module.cloudfront.domain_name}/grafana"
}

output "langfuse_url" {
  description = "Langfuse URL"
  value       = module.cloudfront.langfuse_url
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

# -----------------------------------------------------------------------------
# EFS
# -----------------------------------------------------------------------------

output "efs_file_system_id" {
  description = "EFS file system ID for Victoria Metrics"
  value       = module.efs_victoria_metrics.file_system_id
}

output "efs_access_point_id" {
  description = "EFS access point ID"
  value       = module.efs_victoria_metrics.access_point_id
}

# -----------------------------------------------------------------------------
# Service URLs
# -----------------------------------------------------------------------------

output "litellm_api_url" {
  description = "LiteLLM API URL (OpenAI-compatible)"
  value       = "https://${module.cloudfront.domain_name}/v1/chat/completions"
}

output "litellm_models_url" {
  description = "LiteLLM models endpoint"
  value       = "https://${module.cloudfront.domain_name}/v1/models"
}

output "litellm_health_url" {
  description = "LiteLLM health check URL"
  value       = "https://${module.cloudfront.domain_name}/health/liveliness"
}

output "victoria_metrics_url" {
  description = "Victoria Metrics internal URL (for Grafana datasource)"
  value       = "http://${module.ecs.alb_dns_name}:9090"
}
