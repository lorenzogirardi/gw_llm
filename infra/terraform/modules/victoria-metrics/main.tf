# Victoria Metrics on ECS Fargate
#
# Lightweight Prometheus-compatible metrics storage that:
# - Scrapes Kong /metrics endpoint
# - Stores metrics
# - Exposes Prometheus API for Grafana

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "victoria" {
  name              = "/ecs/${var.project_name}-${var.environment}/victoria-metrics"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "victoria" {
  family                   = "${var.project_name}-victoria-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # EFS volume (optional)
  dynamic "volume" {
    for_each = var.efs_file_system_id != "" ? [1] : []
    content {
      name = "victoria-metrics-data"

      efs_volume_configuration {
        file_system_id     = var.efs_file_system_id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = var.efs_access_point_id
          iam             = "ENABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "victoria-metrics"
      image     = "victoriametrics/victoria-metrics:v1.93.0"
      essential = true

      entryPoint = ["sh", "-c"]
      command = [
        "cat > /tmp/prometheus.yml << 'EOFCONFIG'\nglobal:\n  scrape_interval: 15s\nscrape_configs:\n${join("\n", [for target in var.scrape_targets : "  - job_name: ${target.job_name}\n    static_configs:\n      - targets: [\"${target.target}\"]\n    metrics_path: ${target.metrics_path}"])}${var.kong_metrics_host != "" ? "\n  - job_name: kong\n    static_configs:\n      - targets: [\"${var.kong_metrics_host}:8100\"]\n    metrics_path: /metrics" : ""}\nEOFCONFIG\n/victoria-metrics-prod -promscrape.config=/tmp/prometheus.yml -storageDataPath=/victoria-metrics-data -retentionPeriod=${var.retention_days}d -httpListenAddr=:8428"
      ]

      portMappings = [
        {
          containerPort = 8428
          hostPort      = 8428
          protocol      = "tcp"
        }
      ]

      # Mount EFS volume if configured
      mountPoints = var.efs_file_system_id != "" ? [
        {
          sourceVolume  = "victoria-metrics-data"
          containerPath = "/victoria-metrics-data"
          readOnly      = false
        }
      ] : []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.victoria.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "victoria"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:8428/-/healthy || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "victoria" {
  name            = "victoria-metrics"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.victoria.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 100
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.victoria.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.victoria.arn
    container_name   = "victoria-metrics"
    container_port   = 8428
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "victoria" {
  name        = "${var.project_name}-victoria-${var.environment}"
  description = "Security group for Victoria Metrics"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8428
    to_port         = 8428
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "Victoria Metrics from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-victoria-${var.environment}"
  })
}

# -----------------------------------------------------------------------------
# ALB Target Group & Listener
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "victoria" {
  name        = "${var.project_name}-victoria-${var.environment}"
  port        = 8428
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    path                = "/-/healthy"
    port                = "8428"
    protocol            = "HTTP"
    timeout             = 5
  }

  tags = var.tags
}

# Listener on port 9090 for Prometheus API (internal only - accessed by Grafana)
# This listener is NOT exposed via CloudFront, only accessible within the VPC
resource "aws_lb_listener" "victoria" {
  load_balancer_arn = var.alb_arn
  port              = 9090
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.victoria.arn
  }
}

# -----------------------------------------------------------------------------
# IAM Roles
# -----------------------------------------------------------------------------

resource "aws_iam_role" "execution" {
  name = "${var.project_name}-victoria-execution-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${var.project_name}-victoria-task-${var.environment}"

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

# EFS access policy (only when EFS is configured)
resource "aws_iam_role_policy" "efs_access" {
  count = var.efs_file_system_id != "" ? 1 : 0

  name = "efs-access"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ]
      Resource = "arn:aws:elasticfilesystem:${data.aws_region.current.name}:*:file-system/${var.efs_file_system_id}"
      Condition = {
        StringEquals = {
          "elasticfilesystem:AccessPointArn" = "arn:aws:elasticfilesystem:${data.aws_region.current.name}:*:access-point/${var.efs_access_point_id}"
        }
      }
    }]
  })
}
