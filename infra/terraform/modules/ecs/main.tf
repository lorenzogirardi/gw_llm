# ECS Fargate Module for Stargate LLM Gateway
#
# Provides shared ECS infrastructure:
# - ECS Cluster (shared by all services)
# - Application Load Balancer (path-based routing)
# - Security Groups
# - CloudWatch Log Groups
#
# Note: Legacy Kong container definitions are kept for backward compatibility
# but are not used in the current LiteLLM-based architecture.

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
# ECS Cluster
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "kong" {
  name = "${var.project_name}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "kong" {
  cluster_name = aws_ecs_cluster.kong.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "kong" {
  name              = "/ecs/${var.project_name}-${var.environment}/kong"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "adot" {
  count             = var.enable_amp_write ? 1 : 0
  name              = "/ecs/${var.project_name}-${var.environment}/adot"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

locals {
  # ADOT collector configuration for scraping Kong metrics and sending to AMP
  adot_config = var.enable_amp_write ? yamlencode({
    receivers = {
      prometheus = {
        config = {
          global = {
            scrape_interval     = "15s"
            evaluation_interval = "15s"
          }
          scrape_configs = [
            {
              job_name        = "kong"
              static_configs  = [{ targets = ["localhost:8100"] }]
              metrics_path    = "/metrics"
              scrape_interval = "15s"
            }
          ]
        }
      }
    }
    exporters = {
      prometheusremotewrite = {
        endpoint = "https://aps-workspaces.${data.aws_region.current.name}.amazonaws.com/workspaces/${var.amp_workspace_id}/api/v1/remote_write"
        auth = {
          authenticator = "sigv4auth"
        }
      }
    }
    extensions = {
      sigv4auth = {
        region  = data.aws_region.current.name
        service = "aps"
      }
    }
    service = {
      extensions = ["sigv4auth"]
      pipelines = {
        metrics = {
          receivers = ["prometheus"]
          exporters = ["prometheusremotewrite"]
        }
      }
    }
  }) : ""

  # Container definitions - Kong + optional ADOT sidecar
  kong_container = {
    name      = "kong"
    image     = var.kong_image
    essential = true

    portMappings = [
      {
        containerPort = 8000
        hostPort      = 8000
        protocol      = "tcp"
      },
      {
        containerPort = 8001
        hostPort      = 8001
        protocol      = "tcp"
      },
      {
        containerPort = 8100
        hostPort      = 8100
        protocol      = "tcp"
      }
    ]

    environment = [
      {
        name  = "KONG_DATABASE"
        value = "off"
      },
      {
        name  = "KONG_DECLARATIVE_CONFIG"
        value = "/kong/kong.yaml"
      },
      {
        name  = "KONG_PROXY_LISTEN"
        value = "0.0.0.0:8000"
      },
      {
        name  = "KONG_ADMIN_LISTEN"
        value = "0.0.0.0:8001"
      },
      {
        name  = "KONG_STATUS_LISTEN"
        value = "0.0.0.0:8100"
      },
      {
        name  = "KONG_PLUGINS"
        value = "bundled,bedrock-proxy,token-meter,ecommerce-guardrails"
      },
      {
        name  = "KONG_LOG_LEVEL"
        value = var.kong_log_level
      },
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "BEDROCK_ENDPOINT"
        value = "https://bedrock-runtime.${data.aws_region.current.name}.amazonaws.com"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.kong.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "kong"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "kong health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }

  adot_container = var.enable_amp_write ? {
    name      = "adot-collector"
    image     = "public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0"
    essential = false

    command = ["--config", "env:AOT_CONFIG_CONTENT"]

    environment = [
      {
        name  = "AOT_CONFIG_CONTENT"
        value = local.adot_config
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.adot[0].name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "adot"
      }
    }
  } : null

  container_definitions = concat(
    [local.kong_container],
    var.enable_amp_write ? [local.adot_container] : []
  )
}

resource "aws_ecs_task_definition" "kong" {
  family                   = "${var.project_name}-kong-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.enable_amp_write ? var.task_cpu + 256 : var.task_cpu
  memory                   = var.enable_amp_write ? var.task_memory + 512 : var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode(local.container_definitions)

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "kong" {
  name        = "${var.project_name}-kong-${var.environment}"
  description = "Security group for Kong ECS tasks"
  vpc_id      = var.vpc_id

  # Proxy port (API traffic)
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Kong proxy from ALB"
  }

  # Admin port (internal only)
  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    description = "Kong admin API"
  }

  # Status/metrics port
  ingress {
    from_port       = 8100
    to_port         = 8100
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Kong status/metrics"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-kong-${var.environment}"
  })
}

# CloudFront managed prefix list (for restricting ALB to CloudFront only)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = var.restrict_to_cloudfront ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-${var.environment}"
  description = "Security group for Stargate LLM Gateway ALB"
  vpc_id      = var.vpc_id

  # HTTPS - CloudFront only or allowed CIDRs
  dynamic "ingress" {
    for_each = var.restrict_to_cloudfront ? [] : [1]
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
      description = "HTTPS from allowed CIDRs"
    }
  }

  dynamic "ingress" {
    for_each = var.restrict_to_cloudfront ? [1] : []
    content {
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront[0].id]
      description     = "HTTPS from CloudFront only"
    }
  }

  # HTTP - CloudFront only or allowed CIDRs
  dynamic "ingress" {
    for_each = var.restrict_to_cloudfront ? [] : [1]
    content {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
      description = "HTTP from allowed CIDRs"
    }
  }

  dynamic "ingress" {
    for_each = var.restrict_to_cloudfront ? [1] : []
    content {
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront[0].id]
      description     = "HTTP from CloudFront only"
    }
  }

  # Metrics port - CloudFront only or open
  dynamic "ingress" {
    for_each = var.restrict_to_cloudfront ? [] : [1]
    content {
      from_port   = 8100
      to_port     = 8100
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "LiteLLM metrics (POC - open)"
    }
  }

  dynamic "ingress" {
    for_each = var.restrict_to_cloudfront ? [1] : []
    content {
      from_port       = 8100
      to_port         = 8100
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront[0].id]
      description     = "LiteLLM metrics from CloudFront only"
    }
  }

  # Victoria Metrics - Internal only (Grafana queries this from within VPC)
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Victoria Metrics API (internal VPC only)"
  }

  # Langfuse - CloudFront only or open
  dynamic "ingress" {
    for_each = var.restrict_to_cloudfront ? [] : [1]
    content {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Langfuse (POC - open)"
    }
  }

  dynamic "ingress" {
    for_each = var.restrict_to_cloudfront ? [1] : []
    content {
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront[0].id]
      description     = "Langfuse from CloudFront only"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-alb-${var.environment}"
  })
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------

resource "aws_lb" "kong" {
  name               = "${var.project_name}-${var.environment}"
  internal           = var.internal_alb
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  # Security: Drop requests with invalid HTTP headers
  # Prevents header injection attacks and malformed requests
  drop_invalid_header_fields = true

  tags = var.tags
}

resource "aws_lb_target_group" "kong" {
  name        = "${var.project_name}-kong-${var.environment}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    path                = "/status"
    port                = "8100"
    protocol            = "HTTP"
    timeout             = 5
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.kong.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.kong.arn
  port              = 80
  protocol          = "HTTP"

  # Default action: block if origin_verify_secret is set, otherwise forward/redirect
  default_action {
    type = var.origin_verify_secret != "" ? "fixed-response" : (var.certificate_arn != "" ? "redirect" : "forward")

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

    dynamic "redirect" {
      for_each = var.origin_verify_secret == "" && var.certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    target_group_arn = var.origin_verify_secret == "" && var.certificate_arn == "" ? aws_lb_target_group.kong.arn : null
  }
}

# Metrics endpoint (for Grafana to scrape)
resource "aws_lb_target_group" "metrics" {
  name        = "${var.project_name}-metrics-${var.environment}"
  port        = 8100
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    path                = "/status"
    port                = "8100"
    protocol            = "HTTP"
    timeout             = 5
  }

  tags = var.tags
}

resource "aws_lb_listener" "metrics" {
  load_balancer_arn = aws_lb.kong.arn
  port              = 8100
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.metrics.arn
  }
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "kong" {
  name            = "kong"
  cluster         = aws_ecs_cluster.kong.id
  task_definition = aws_ecs_task_definition.kong.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 100
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.kong.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kong.arn
    container_name   = "kong"
    container_port   = 8000
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.metrics.arn
    container_name   = "kong"
    container_port   = 8100
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Auto Scaling
# -----------------------------------------------------------------------------

resource "aws_appautoscaling_target" "kong" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.kong.name}/${aws_ecs_service.kong.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "kong_cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.project_name}-kong-cpu-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.kong[0].resource_id
  scalable_dimension = aws_appautoscaling_target.kong[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.kong[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_value
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# -----------------------------------------------------------------------------
# IAM Roles
# -----------------------------------------------------------------------------

# ECS Execution Role (for pulling images, writing logs)
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (for Bedrock access)
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-${var.environment}"

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
resource "aws_iam_role_policy" "bedrock_access" {
  name = "bedrock-access"
  role = aws_iam_role.ecs_task.id

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

# AMP remote write policy
resource "aws_iam_role_policy" "amp_write" {
  count = var.enable_amp_write ? 1 : 0

  name = "amp-remote-write"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AMPRemoteWrite"
      Effect = "Allow"
      Action = [
        "aps:RemoteWrite"
      ]
      Resource = "arn:aws:aps:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workspace/${var.amp_workspace_id}"
    }]
  })
}
