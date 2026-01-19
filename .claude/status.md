# Project Status: Kong LLM Gateway

**Last Updated:** 2026-01-19
**Current Phase:** POC Implementation - ECS Fargate + Victoria Metrics + Grafana

---

## POC Environment (DEPLOYED)

### Live Endpoints

| Service | URL |
|---------|-----|
| **API (CloudFront)** | https://d18l8nt8fin3hz.cloudfront.net |
| **Grafana** | https://d18l8nt8fin3hz.cloudfront.net/grafana |
| **Kong ALB** | kong-llm-gateway-poc-1159371345.us-west-1.elb.amazonaws.com |
| **Kong Metrics** | http://kong-llm-gateway-poc-1159371345.us-west-1.elb.amazonaws.com:8100/metrics |
| **Victoria Metrics** | http://kong-llm-gateway-poc-1159371345.us-west-1.elb.amazonaws.com:9090 |

### Credentials

- **Grafana**: admin / FsdnbxMi7erbiSYg. (stored in Secrets Manager)
- **Kong API Key**: dev-api-key-changeme

### Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────────────────────────┐     ┌─────────────────┐
│   Clients   │────▶│  CloudFront  │────▶│       ECS Fargate Cluster        │────▶│   AWS Bedrock   │
│             │     │   (HTTPS)    │     │  ┌────────────────────────────┐  │     │                 │
└─────────────┘     └──────────────┘     │  │ Kong Gateway (DB-less)     │  │     │  - Claude Opus  │
                                         │  │ + bedrock-proxy plugin     │  │     │  - Claude Sonnet│
                                         │  │ + token-meter plugin       │  │     │  - Claude Haiku │
                                         │  │ + ecommerce-guardrails     │  │     └─────────────────┘
                                         │  └────────────────────────────┘  │
                                         │  ┌────────────────────────────┐  │
                                         │  │ Victoria Metrics           │  │
                                         │  │ (Prometheus scraper)       │  │
                                         │  └────────────────────────────┘  │
                                         │  ┌────────────────────────────┐  │
                                         │  │ Grafana OSS                │  │
                                         │  │ (Dashboards)               │  │
                                         │  └────────────────────────────┘  │
                                         └──────────────────────────────────┘
                                                        │
                                                        ▼
                                               ┌──────────────┐
                                               │     AMP      │
                                               │  (unused)    │
                                               └──────────────┘
```

### POC Components

| Component | Service | Status | Notes |
|-----------|---------|--------|-------|
| Kong Gateway | ECS Fargate (0.25 vCPU, 512MB) | RUNNING | FARGATE (no Spot) |
| Victoria Metrics | ECS Fargate (0.25 vCPU, 512MB) | RUNNING | Scrapes Kong metrics |
| Grafana OSS | ECS Fargate (0.25 vCPU, 512MB) | RUNNING | Custom image with dashboards |
| CloudFront | CDN | RUNNING | HTTPS termination |
| AMP | Managed Prometheus | CREATED | Not used (no ADOT collector) |

### Recent Changes (2026-01-19)

1. **Kong Health Check Fixed**: Changed from `/health` to `/status` on port 8100
2. **Container Health Check Fixed**: Changed from `curl` to `kong health` command
3. **Switched to FARGATE**: Removed FARGATE_SPOT for stability
4. **Victoria Metrics Added**: Scrapes Kong /metrics and exposes Prometheus API on port 9090
5. **Security Group Updated**: Opened ports 8100 and 9090 for metrics access
6. **Grafana Password**: Stored in AWS Secrets Manager
7. **Victoria Metrics Command Fixed**: Fixed shell quoting in task definition using heredoc
8. **Grafana Datasource Updated**: Kong Metrics now points to Victoria Metrics (port 9090)
9. **Dashboards Updated**: kong-gateway.json and llm-usage-overview.json use Prometheus queries
10. **Grafana Image Rebuilt**: Pushed new image with updated datasource config

### POC Terraform Modules

| Module | Status | Path |
|--------|--------|------|
| ECS Fargate | DEPLOYED | `infra/terraform/modules/ecs/` |
| AMP | DEPLOYED | `infra/terraform/modules/amp/` |
| Grafana ECS | DEPLOYED | `infra/terraform/modules/grafana-ecs/` |
| CloudFront | DEPLOYED | `infra/terraform/modules/cloudfront/` |
| Victoria Metrics | DEPLOYED | `infra/terraform/modules/victoria-metrics/` |
| POC Environment | DEPLOYED | `infra/terraform/environments/poc/` |

### Grafana Dashboards

| Dashboard | Datasource | Status |
|-----------|------------|--------|
| Infrastructure | CloudWatch | WORKING |
| Kong Gateway | Victoria Metrics | WORKING |
| LLM Usage Overview | Victoria Metrics | WORKING |

### TODO

1. [x] Wait for Victoria Metrics to be healthy
2. [x] Update Grafana "Kong Metrics" datasource to point to Victoria Metrics (port 9090)
3. [x] Restore kong-gateway.json and llm-usage-overview.json dashboards with Prometheus queries
4. [ ] Test dashboards show Kong metrics data

---

## Test Commands

```bash
# Test Kong health (via CloudFront)
curl https://d18l8nt8fin3hz.cloudfront.net/health

# Test chat endpoint
curl -X POST https://d18l8nt8fin3hz.cloudfront.net/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "apikey: dev-api-key-changeme" \
  -d '{"model":"claude-haiku","messages":[{"role":"user","content":"Hello"}]}'

# View Kong logs
aws logs tail /ecs/kong-llm-gateway-poc/kong --follow --region us-west-1

# View Victoria Metrics logs
aws logs tail /ecs/kong-llm-gateway-poc/victoria-metrics --follow --region us-west-1

# Check ECS services
aws ecs describe-services --cluster kong-llm-gateway-poc --services kong grafana victoria-metrics --region us-west-1 --query 'services[*].{name:serviceName,running:runningCount,desired:desiredCount}'
```

---

## Known Issues

1. **ADOT Collector Disabled**: Caused Kong task crashes, disabled `enable_amp_write`
2. **AMP Not Used**: No metrics being written to AMP since ADOT disabled (using Victoria Metrics instead)

---

## Infrastructure Terraform State

| Resource | State |
|----------|-------|
| VPC | CREATED |
| ECS Cluster | CREATED |
| Kong Service | RUNNING |
| Grafana Service | RUNNING |
| Victoria Metrics Service | RUNNING |
| ALB | CREATED |
| CloudFront | CREATED |
| AMP Workspace | CREATED |

---

*Update this file at the end of each session*
