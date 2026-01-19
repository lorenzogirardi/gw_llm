# Amazon Managed Prometheus (AMP) Module
#
# Creates an AMP workspace for Kong metrics with:
# - Prometheus workspace
# - Alert manager definition (optional)
# - Logging configuration

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# AMP Workspace
# -----------------------------------------------------------------------------

resource "aws_prometheus_workspace" "kong" {
  alias = "${var.project_name}-${var.environment}"

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.amp.arn}:*"
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for AMP
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "amp" {
  name              = "/aws/prometheus/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Alert Manager Definition (Optional)
# -----------------------------------------------------------------------------

resource "aws_prometheus_alert_manager_definition" "kong" {
  count = var.enable_alertmanager ? 1 : 0

  workspace_id = aws_prometheus_workspace.kong.id

  definition = <<-EOT
alertmanager_config: |
  global:
    resolve_timeout: 5m
  route:
    group_by: ['alertname', 'severity']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    receiver: 'default'
    routes:
      - match:
          severity: critical
        receiver: 'critical'
      - match:
          severity: warning
        receiver: 'warning'
  receivers:
    - name: 'default'
    - name: 'critical'
      sns_configs:
        - topic_arn: '${var.sns_topic_arn_critical}'
          send_resolved: true
    - name: 'warning'
      sns_configs:
        - topic_arn: '${var.sns_topic_arn_warning}'
          send_resolved: true
EOT
}

# -----------------------------------------------------------------------------
# Recording Rules (Optional)
# -----------------------------------------------------------------------------

resource "aws_prometheus_rule_group_namespace" "kong" {
  count = var.enable_recording_rules ? 1 : 0

  name         = "kong-rules"
  workspace_id = aws_prometheus_workspace.kong.id

  data = <<-EOT
groups:
  - name: kong_llm_gateway
    interval: 60s
    rules:
      # Token usage rate
      - record: kong:llm_tokens_rate:5m
        expr: sum(rate(kong_llm_tokens_total[5m])) by (consumer, model)

      # Cost rate per hour
      - record: kong:llm_cost_rate:hourly
        expr: sum(rate(kong_llm_cost_total[1h])) by (consumer) * 3600

      # Request success rate
      - record: kong:request_success_rate:5m
        expr: |
          sum(rate(kong_http_requests_total{code=~"2.."}[5m])) by (service)
          /
          sum(rate(kong_http_requests_total[5m])) by (service)

      # P99 latency
      - record: kong:latency_p99:5m
        expr: histogram_quantile(0.99, sum(rate(kong_request_latency_ms_bucket[5m])) by (le, service))

      # Guardrail block rate
      - record: kong:guardrail_block_rate:5m
        expr: sum(rate(kong_guardrail_blocks_total[5m])) by (category)

  - name: kong_alerts
    interval: 60s
    rules:
      # High error rate alert
      - alert: KongHighErrorRate
        expr: |
          sum(rate(kong_http_requests_total{code=~"5.."}[5m])) by (service)
          /
          sum(rate(kong_http_requests_total[5m])) by (service)
          > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate on {{ $labels.service }}"
          description: "Error rate is {{ $value | humanizePercentage }}"

      # High latency alert
      - alert: KongHighLatency
        expr: kong:latency_p99:5m > 30000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High latency on {{ $labels.service }}"
          description: "P99 latency is {{ $value }}ms"

      # Token quota exceeded
      - alert: KongTokenQuotaExceeded
        expr: |
          sum(increase(kong_llm_tokens_total[24h])) by (consumer) > 100000
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Token quota exceeded for {{ $labels.consumer }}"
          description: "Consumer has used {{ $value }} tokens in 24h"

      # High cost alert
      - alert: KongHighCost
        expr: kong:llm_cost_rate:hourly > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High LLM cost rate"
          description: "Cost rate is $${{ $$value }}/hour"
EOT
}
