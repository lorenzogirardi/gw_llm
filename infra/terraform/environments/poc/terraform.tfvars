# POC Environment - Configuration
# Region: us-west-1

aws_region = "us-west-1"

# VPC Configuration - Create new VPC
create_vpc = true
vpc_cidr   = "10.10.0.0/16"

availability_zones   = ["us-west-1b", "us-west-1c"]
private_subnet_cidrs = ["10.10.1.0/24", "10.10.2.0/24"]
public_subnet_cidrs  = ["10.10.101.0/24", "10.10.102.0/24"]

# Network access (open for POC - restrict in production)
allowed_cidr_blocks = ["0.0.0.0/0"]

# Kong configuration - custom image with plugins from ECR
kong_image = "170674040462.dkr.ecr.us-west-1.amazonaws.com/kong-llm-gateway:latest"

# Grafana configuration - custom image with dashboards from ECR
grafana_image = "170674040462.dkr.ecr.us-west-1.amazonaws.com/grafana-llm-gateway:latest"

# No HTTPS for POC (HTTP only)
certificate_arn = ""

# Grafana authentication via AWS SSO
grafana_auth_providers = ["AWS_SSO"]

# Grafana admin users - will be configured after deployment
grafana_admin_user_ids = []

# Grafana admin password from Secrets Manager
grafana_admin_password_secret_arn = "arn:aws:secretsmanager:us-west-1:170674040462:secret:kong-llm-gateway/grafana-admin-password-0lbuDK"
