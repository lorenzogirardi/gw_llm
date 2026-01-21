# LiteLLM on ECS Fargate
#
# OpenAI-compatible proxy for AWS Bedrock with:
# - User management and API keys
# - Token tracking per user
# - Prometheus metrics for Grafana
# - Claude Code compatibility

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "litellm" {
  name              = "/ecs/${var.project_name}-${var.environment}/litellm"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "litellm" {
  family                   = "${var.project_name}-litellm-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.litellm_execution.arn
  task_role_arn            = aws_iam_role.litellm_task.arn

  container_definitions = jsonencode([
    {
      name      = "litellm"
      image     = var.litellm_image
      essential = true

      # Write config.yaml at startup and run LiteLLM
      entryPoint = ["sh", "-c"]
      command = [
        "mkdir -p /tmp/prometheus_multiproc && cat > /app/config.yaml << 'EOFCONFIG'\n${var.litellm_config}\nEOFCONFIG\nexec litellm --config /app/config.yaml --port 4000 --num_workers 1"
      ]

      portMappings = [
        {
          containerPort = 4000
          hostPort      = 4000
          protocol      = "tcp"
        }
      ]

      environment = concat(
        [
          {
            name  = "AWS_REGION"
            value = data.aws_region.current.name
          },
          {
            name  = "LITELLM_LOG"
            value = "INFO"
          },
          {
            name  = "STORE_MODEL_IN_DB"
            value = "True"
          },
          {
            name  = "PROMETHEUS_MULTIPROC_DIR"
            value = "/tmp/prometheus_multiproc"
          }
        ],
        var.langfuse_host != "" ? [
          {
            name  = "LANGFUSE_HOST"
            value = var.langfuse_host
          }
        ] : []
      )

      secrets = concat(
        [
          {
            name      = "LITELLM_MASTER_KEY"
            valueFrom = var.master_key_secret_arn
          }
        ],
        var.database_url_secret_arn != "" ? [
          {
            name      = "DATABASE_URL"
            valueFrom = var.database_url_secret_arn
          }
        ] : [],
        var.langfuse_public_key_secret_arn != "" ? [
          {
            name      = "LANGFUSE_PUBLIC_KEY"
            valueFrom = var.langfuse_public_key_secret_arn
          }
        ] : [],
        var.langfuse_secret_key_secret_arn != "" ? [
          {
            name      = "LANGFUSE_SECRET_KEY"
            valueFrom = var.langfuse_secret_key_secret_arn
          }
        ] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.litellm.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "litellm"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')\" || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 90
      }
    }
  ])

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "litellm" {
  name            = "litellm"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.litellm.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 100
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.litellm.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.litellm.arn
    container_name   = "litellm"
    container_port   = 4000
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "litellm" {
  name        = "${var.project_name}-litellm-${var.environment}"
  description = "Security group for LiteLLM ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "LiteLLM API from ALB"
  }

  # Allow Victoria Metrics to scrape /metrics
  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Metrics scraping from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (Bedrock, etc)"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-litellm-${var.environment}"
  })
}

# -----------------------------------------------------------------------------
# ALB Target Group
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "litellm" {
  name        = "${var.project_name}-litellm-${var.environment}"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    path                = "/health/liveliness"
    port                = "4000"
    protocol            = "HTTP"
    timeout             = 10
  }

  # Longer deregistration for graceful shutdown
  deregistration_delay = 30

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ALB Listener Rules (path-based routing)
# -----------------------------------------------------------------------------

# Main API routes (/v1/*)
resource "aws_lb_listener_rule" "litellm_api" {
  listener_arn = var.alb_listener_arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.litellm.arn
  }

  condition {
    path_pattern {
      values = ["/v1/*", "/health/*", "/metrics", "/metrics/*"]
    }
  }
}

# Admin routes (/key/*, /user/*, /model/*, /spend/*)
resource "aws_lb_listener_rule" "litellm_admin" {
  listener_arn = var.alb_listener_arn
  priority     = 51

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.litellm.arn
  }

  condition {
    path_pattern {
      values = ["/key/*", "/user/*", "/model/*", "/spend/*"]
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Roles
# -----------------------------------------------------------------------------

# Execution Role (for pulling images, writing logs, reading secrets)
resource "aws_iam_role" "litellm_execution" {
  name = "${var.project_name}-litellm-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "litellm_execution" {
  role       = aws_iam_role.litellm_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets Manager access for execution role
resource "aws_iam_role_policy" "litellm_secrets" {
  name = "secrets-access"
  role = aws_iam_role.litellm_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = compact([
        var.master_key_secret_arn,
        var.database_url_secret_arn,
        var.langfuse_public_key_secret_arn,
        var.langfuse_secret_key_secret_arn
      ])
    }]
  })
}

# Task Role (for Bedrock access)
resource "aws_iam_role" "litellm_task" {
  name = "${var.project_name}-litellm-task-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# Bedrock access policy
resource "aws_iam_role_policy" "litellm_bedrock" {
  name = "bedrock-access"
  role = aws_iam_role.litellm_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = var.allowed_bedrock_models
    }]
  })
}
