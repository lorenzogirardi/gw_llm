# Bedrock IAM Module
# Creates IAM roles and policies for Kong to access AWS Bedrock
#
# Features:
# - IRSA (IAM Roles for Service Accounts) for EKS pods
# - Least-privilege Bedrock access policies
# - Model-specific permissions

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
# IAM Role for Kong Service Account (IRSA)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "kong_bedrock" {
  name = "${var.cluster_name}-kong-bedrock"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account}"
          "${var.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Bedrock Invoke Policy
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "bedrock_invoke" {
  name = "bedrock-invoke"
  role = aws_iam_role.kong_bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeModels"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = var.allowed_model_arns
      },
      {
        Sid    = "BedrockListModels"
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Logs Policy (for token metrics)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "cloudwatch_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name = "cloudwatch-logs"
  role = aws_iam_role.kong_bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = [
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/kong/*",
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/kong/*:*"
      ]
    }]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Metrics Policy (for custom metrics)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "cloudwatch_metrics" {
  count = var.enable_cloudwatch_metrics ? 1 : 0

  name = "cloudwatch-metrics"
  role = aws_iam_role.kong_bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchMetrics"
      Effect = "Allow"
      Action = [
        "cloudwatch:PutMetricData"
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "cloudwatch:namespace" = var.cloudwatch_namespace
        }
      }
    }]
  })
}

# -----------------------------------------------------------------------------
# Kubernetes Service Account Annotation
# -----------------------------------------------------------------------------

# This output should be used to annotate the Kong service account
# kubectl annotate serviceaccount -n kong kong eks.amazonaws.com/role-arn=<role_arn>

output "role_arn" {
  description = "ARN of the IAM role for Kong service account"
  value       = aws_iam_role.kong_bedrock.arn
}

output "role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.kong_bedrock.name
}

output "service_account_annotation" {
  description = "Annotation to add to Kubernetes service account for IRSA"
  value       = "eks.amazonaws.com/role-arn: ${aws_iam_role.kong_bedrock.arn}"
}
