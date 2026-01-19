# Kong LLM Gateway - POC Environment

Low-cost Proof of Concept deployment using AWS managed services.

## Architecture

```
┌─────────────┐     ┌──────────────────────────────────┐     ┌─────────────────┐
│   Clients   │     │       ECS Fargate (Kong)         │     │   AWS Bedrock   │
│(claude-code)│────▶│  ┌────────────────────────────┐  │────▶│                 │
│             │     │  │ Kong Gateway (DB-less)     │  │     │  - Claude Opus  │
└─────────────┘     │  │ + Custom Plugins           │  │     │  - Claude Sonnet│
                    │  └────────────────────────────┘  │     │  - Claude Haiku │
                    └──────────────────────────────────┘     └─────────────────┘
                                    │
                                    ▼
                           ┌──────────────┐
                           │     AMP      │
                           │  (Prometheus)│
                           └──────┬───────┘
                                  │
                                  ▼
                           ┌──────────────┐
                           │     AMG      │
                           │  (Grafana)   │
                           └──────────────┘
```

## Estimated Costs

| Component | Service | Monthly Cost |
|-----------|---------|--------------|
| Kong Gateway | ECS Fargate (0.25 vCPU, 0.5GB) | ~$8 |
| Metrics | Amazon Managed Prometheus (AMP) | ~$5-8 |
| Dashboards | Amazon Managed Grafana (AMG) | ~$9 |
| Network | NAT Gateway (single) | ~$30 |
| **Total Fixed** | | **~$52-55** |
| LLM Usage | Bedrock (Opus/Sonnet/Haiku) | Pay per use |

**Note**: Actual costs depend on usage. NAT Gateway can be eliminated by using VPC endpoints.

## Quick Start

### 1. Prerequisites

- AWS CLI configured
- Terraform >= 1.5.0
- AWS SSO configured (for Grafana access)

### 2. Configure

```bash
cd infra/terraform/environments/poc

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

### 3. Deploy

```bash
# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply
```

### 4. Test

```bash
# Get outputs
terraform output

# Test health endpoint
curl $(terraform output -raw kong_endpoint)/health

# Open Grafana
open $(terraform output -raw grafana_url)
```

## Configuration

### Using Existing VPC

Set `create_vpc = false` and provide VPC details:

```hcl
create_vpc         = false
vpc_id             = "vpc-xxxxxxxxx"
private_subnet_ids = ["subnet-aaaa", "subnet-bbbb"]
public_subnet_ids  = ["subnet-cccc", "subnet-dddd"]
```

### HTTPS

Provide an ACM certificate ARN:

```hcl
certificate_arn = "arn:aws:acm:us-east-1:123456789:certificate/xxxxx"
```

### Grafana Users

Add SSO user IDs for admin access:

```hcl
grafana_admin_user_ids = ["user-id-from-sso"]
```

## Kong Configuration

The Kong gateway is configured in DB-less mode. To update configuration:

1. Build a custom Docker image with your `kong.yaml`
2. Push to ECR
3. Update `kong_image` variable
4. Apply Terraform

Or use EFS to mount configuration dynamically (requires additional setup).

## Cleanup

```bash
terraform destroy
```

## Next Steps

- Configure Kong `kong.yaml` with API keys and routes
- Set up Grafana dashboards
- Add HTTPS certificate
- Configure alerting (SNS topics)
