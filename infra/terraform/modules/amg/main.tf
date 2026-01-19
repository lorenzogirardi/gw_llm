# Amazon Managed Grafana (AMG) Module
#
# Creates an AMG workspace with:
# - Grafana workspace
# - IAM role for service account
# - Data source permissions for AMP

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
# AMG Workspace
# -----------------------------------------------------------------------------

resource "aws_grafana_workspace" "kong" {
  name                     = "${var.project_name}-${var.environment}"
  description              = "Kong LLM Gateway monitoring dashboard"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = var.authentication_providers
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn

  data_sources = ["PROMETHEUS", "CLOUDWATCH"]

  configuration = jsonencode({
    plugins = {
      pluginAdminEnabled = true
    }
    unifiedAlerting = {
      enabled = true
    }
  })

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IAM Role for Grafana
# -----------------------------------------------------------------------------

resource "aws_iam_role" "grafana" {
  name = "${var.project_name}-grafana-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "grafana.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        StringLike = {
          "aws:SourceArn" = "arn:aws:grafana:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:/workspaces/*"
        }
      }
    }]
  })

  tags = var.tags
}

# AMP query permissions
resource "aws_iam_role_policy" "grafana_amp" {
  count = var.amp_workspace_arns != [] ? 1 : 0

  name = "amp-query"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AMPQuery"
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = var.amp_workspace_arns
      },
      {
        Sid    = "AMPListWorkspaces"
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch permissions
resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name = "cloudwatch-query"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchReadOnly"
      Effect = "Allow"
      Action = [
        "cloudwatch:DescribeAlarmsForMetric",
        "cloudwatch:DescribeAlarmHistory",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetInsightRuleReport",
        "logs:DescribeLogGroups",
        "logs:GetLogGroupFields",
        "logs:StartQuery",
        "logs:StopQuery",
        "logs:GetQueryResults",
        "logs:GetLogEvents"
      ]
      Resource = "*"
    }]
  })
}

# SNS for alerting
resource "aws_iam_role_policy" "grafana_sns" {
  count = var.enable_sns_alerting ? 1 : 0

  name = "sns-alerting"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SNSPublish"
      Effect = "Allow"
      Action = [
        "sns:Publish"
      ]
      Resource = var.sns_topic_arns
    }]
  })
}

# -----------------------------------------------------------------------------
# Grafana Role Association (for SSO users)
# -----------------------------------------------------------------------------

resource "aws_grafana_role_association" "admin" {
  count = length(var.admin_user_ids) > 0 ? 1 : 0

  role         = "ADMIN"
  user_ids     = var.admin_user_ids
  workspace_id = aws_grafana_workspace.kong.id
}

resource "aws_grafana_role_association" "editor" {
  count = length(var.editor_user_ids) > 0 ? 1 : 0

  role         = "EDITOR"
  user_ids     = var.editor_user_ids
  workspace_id = aws_grafana_workspace.kong.id
}

resource "aws_grafana_role_association" "viewer" {
  count = length(var.viewer_user_ids) > 0 ? 1 : 0

  role         = "VIEWER"
  user_ids     = var.viewer_user_ids
  workspace_id = aws_grafana_workspace.kong.id
}
