# CloudFront Module Outputs

output "distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "https_endpoint" {
  description = "HTTPS endpoint URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "grafana_url" {
  description = "Grafana URL via CloudFront"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/grafana"
}

output "langfuse_url" {
  description = "Langfuse URL via CloudFront"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/langfuse"
}
