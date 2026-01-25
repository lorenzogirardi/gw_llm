# Langfuse on ECS Fargate Module
#
# Deploys Langfuse (LLM Observability) on ECS Fargate with:
# - ECS Task Definition
# - ECS Service
# - ALB Target Group and Listener Rule
# - Uses existing RDS PostgreSQL

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
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "langfuse" {
  name              = "/ecs/${var.project_name}-${var.environment}/langfuse"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "langfuse" {
  family                   = "${var.project_name}-langfuse-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.langfuse_execution.arn
  task_role_arn            = aws_iam_role.langfuse_task.arn

  container_definitions = jsonencode([
    {
      name      = "langfuse"
      image     = var.langfuse_image
      essential = true

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "NEXTAUTH_URL"
          value = var.langfuse_url
        },
        {
          name  = "HOSTNAME"
          value = "0.0.0.0"
        },
        {
          name  = "TELEMETRY_ENABLED"
          value = "false"
        },
        {
          name  = "LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES"
          value = "true"
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = var.database_url_secret_arn
        },
        {
          name      = "NEXTAUTH_SECRET"
          valueFrom = var.nextauth_secret_arn
        },
        {
          name      = "SALT"
          valueFrom = var.salt_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.langfuse.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "langfuse"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:3000/api/public/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120
      }
    }
  ])

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "langfuse" {
  name            = "langfuse"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.langfuse.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 100
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.langfuse.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.langfuse.arn
    container_name   = "langfuse"
    container_port   = 3000
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "langfuse" {
  name        = "${var.project_name}-langfuse-${var.environment}"
  description = "Security group for Langfuse ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "Langfuse from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-langfuse-${var.environment}"
  })
}

# -----------------------------------------------------------------------------
# ALB Target Group
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "langfuse" {
  name        = "${var.project_name}-langfuse-${var.environment}"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    path                = "/api/public/health"
    port                = "3000"
    protocol            = "HTTP"
    timeout             = 10
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ALB Listener on port 8080 for Langfuse (dedicated)
# -----------------------------------------------------------------------------

resource "aws_lb_listener" "langfuse" {
  load_balancer_arn = var.alb_arn
  port              = 8080
  protocol          = "HTTP"

  # Default action: block if origin_verify_secret is set, otherwise forward
  default_action {
    type = var.origin_verify_secret != "" ? "fixed-response" : "forward"

    dynamic "fixed_response" {
      for_each = var.origin_verify_secret != "" ? [1] : []
      content {
        content_type = "application/json"
        message_body = jsonencode({
          error = {
            code    = "DIRECT_ACCESS_FORBIDDEN"
            message = "Direct ALB access is not allowed. Use CloudFront."
          }
        })
        status_code = "403"
      }
    }

    target_group_arn = var.origin_verify_secret == "" ? aws_lb_target_group.langfuse.arn : null
  }

  tags = var.tags
}

# Listener rule to forward when X-Origin-Verify header is present
resource "aws_lb_listener_rule" "langfuse_verified" {
  count = var.origin_verify_secret != "" ? 1 : 0

  listener_arn = aws_lb_listener.langfuse.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.langfuse.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }
}

# Listener rule to allow internal VPC traffic without X-Origin-Verify
# This enables LiteLLM callbacks to Langfuse for tracing
resource "aws_lb_listener_rule" "langfuse_internal" {
  count = var.origin_verify_secret != "" && var.vpc_cidr != "" ? 1 : 0

  listener_arn = aws_lb_listener.langfuse.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.langfuse.arn
  }

  condition {
    source_ip {
      values = [var.vpc_cidr]
    }
  }
}

# NOTE: Port 8080 ingress is managed in ECS module's ALB security group
# to prevent inline rules from overwriting external rules

# -----------------------------------------------------------------------------
# IAM Roles
# -----------------------------------------------------------------------------

# Execution Role
resource "aws_iam_role" "langfuse_execution" {
  name = "${var.project_name}-langfuse-execution-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "langfuse_execution" {
  role       = aws_iam_role.langfuse_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets Manager access
resource "aws_iam_role_policy" "langfuse_secrets" {
  name = "secrets-access"
  role = aws_iam_role.langfuse_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        var.database_url_secret_arn,
        var.nextauth_secret_arn,
        var.salt_secret_arn
      ]
    }]
  })
}

# Task Role
resource "aws_iam_role" "langfuse_task" {
  name = "${var.project_name}-langfuse-task-${var.environment}"

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
