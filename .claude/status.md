# Project Status: Kong LLM Gateway

**Last Updated:** 2026-01-19
**Current Phase:** Initial Setup - Claude Code Configuration

---

## Project Overview

Kong OSS API Gateway for Amazon Bedrock LLM proxy with RBAC, token metering, and e-commerce guardrails.

### Key Features
- **Multi-model routing**: Claude Opus, Sonnet, Haiku + Gemini based on user roles
- **RBAC via Kong Consumers/Groups**: developer, analyst, admin, ecommerce_ops, guest
- **Token metering**: CloudWatch + response headers for Bedrock consumption
- **E-commerce guardrails**: Block SQL injection, credit card, password patterns
- **Dual deployment**: EKS (prod) + Docker Compose (local/dev)

---

## Completed Sessions

| Day | Focus | Key Results |
|-----|-------|-------------|
| 1 | Claude Code Setup | Skills configured for Kong/Lua/Bedrock |

---

## Architecture

```
┌─────────────┐     ┌──────────────────────────────────┐     ┌─────────────────┐
│   Clients   │     │         Kong Gateway (OSS)       │     │   AWS Bedrock   │
│  (JWT/Okta) │────▶│  ┌────────────────────────────┐  │────▶│                 │
│             │     │  │ Plugins:                   │  │     │  - Claude Opus  │
└─────────────┘     │  │ - jwt/key-auth             │  │     │  - Claude Sonnet│
                    │  │ - rate-limiting (token)    │  │     │  - Claude Haiku │
                    │  │ - ai-aws-guardrails        │  │     │                 │
                    │  │ - bedrock-proxy (custom)   │  │     └─────────────────┘
                    │  │ - prometheus/datadog       │  │
                    │  └────────────────────────────┘  │
                    └──────────────────────────────────┘
```

---

## Role-Based Model Access

| Role | Model | Model ID | Rate Limit | Notes |
|------|-------|----------|------------|-------|
| `admin` | All models | * | Unlimited | Full access |
| `developer` | Claude 3.5 Sonnet | `anthropic.claude-3-5-sonnet-20240620-v1:0` | 10k tokens/min | claude-code usage |
| `analyst` | Claude 3 Sonnet | `anthropic.claude-3-sonnet-20240229-v1:0` | 5k tokens/min | Analysis tasks |
| `ecommerce_ops` | Claude 3 Sonnet | `anthropic.claude-3-sonnet-20240229-v1:0` | 2k tokens/min | Operations |
| `guest` | Claude 3 Haiku | `anthropic.claude-3-haiku-20240307-v1:0` | 500 tokens/min | Basic queries |
| `other` | Gemini 1.5 Flash | `google/gemini-1.5-flash` | 1k tokens/min | Fallback |

### Kong Consumer Groups

```yaml
consumer_groups:
  - name: admin
    consumers: [admin-user]
  - name: developer
    consumers: [dev-user-1, dev-user-2]
  - name: analyst
    consumers: [analyst-user]
  - name: ecommerce_ops
    consumers: [ops-user]
  - name: guest
    consumers: [guest-user]
```

---

## Deliverables Checklist

### Configuration Files
- [ ] `docker-compose.yml` - Local Kong + Postgres
- [ ] `kong-local.yaml` - Declarative DB-less config
- [ ] `helm/kong-values.yaml` - EKS production values
- [ ] `kong-prod.yaml` - EKS declarative config

### Infrastructure
- [ ] `infra/terraform/modules/eks/` - EKS cluster
- [ ] `infra/terraform/modules/kong/` - Kong Ingress Controller
- [ ] `infra/terraform/modules/bedrock/` - IAM/IRSA for Bedrock

### Custom Plugins
- [ ] `kong/plugins/bedrock-proxy/` - Bedrock integration
- [ ] `kong/plugins/token-meter/` - Token tracking
- [ ] `kong/plugins/ecommerce-guardrails/` - Pattern blocking

### Observability
- [ ] Prometheus metrics exporter
- [ ] Datadog integration (prod)
- [ ] Grafana dashboard (`grafana-local.json`)
- [ ] CloudWatch Bedrock metrics

### Automation
- [ ] `Makefile` - multi-env commands
- [ ] ArgoCD manifests (zero-downtime)
- [ ] HPA configuration (EKS)

### Documentation
- [ ] `docs/architecture/context.md` - C4 Level 1
- [ ] `docs/architecture/container.md` - C4 Level 2
- [ ] `docs/runbooks/deployment.md`
- [ ] `docs/runbooks/incident-response.md`
- [ ] curl examples (local + prod)

---

## Technology Stack

| Component | Local (Dev) | Production (EKS) |
|-----------|-------------|------------------|
| Kong | Docker (kong:latest) | Helm chart (OSS) |
| Database | PostgreSQL (compose) | DB-less mode |
| Auth | JWT (local keys) | Okta/Keycloak |
| Metrics | File-log + Prometheus | Datadog |
| AWS Auth | AWS_PROFILE env | IRSA |
| CDN | - | Akamai |
| GitOps | - | ArgoCD |

---

## Security Considerations

### E-commerce Guardrails (PCI-DSS, GDPR)

**Blocked Patterns** (via `ecommerce-guardrails` plugin):
- `SQL` / `SELECT` / `DROP` / `INSERT` (injection)
- `credit card` / `card number` / `CVV`
- `password` / `secret` / `token`
- `order hack` / `exploit` / `bypass`

### Logging Rules

| Log | Local | Production |
|-----|-------|------------|
| Request metadata | file-log | Datadog |
| Token counts | file-log | CloudWatch + Datadog |
| Model used | file-log | Datadog |
| Latency | Prometheus | Datadog |
| **Request body** | **NO** | **NO** |
| **Response body** | **NO** | **NO** |
| **PII/Credentials** | **NO** | **NO** |

### Compliance Checklist
- [ ] PCI-DSS: No card data in logs, TLS everywhere
- [ ] GDPR: No PII in logs, data minimization
- [ ] Bedrock: Model governance, usage tracking

---

## Observability

### Key Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `kong_bedrock_tokens_input_total` | Counter | Input tokens consumed |
| `kong_bedrock_tokens_output_total` | Counter | Output tokens generated |
| `kong_bedrock_request_duration_seconds` | Histogram | Request latency |
| `kong_bedrock_cost_estimate_dollars` | Gauge | Estimated cost |
| `kong_bedrock_requests_total` | Counter | Total requests by model/role |
| `kong_bedrock_errors_total` | Counter | Errors by type |

### Dashboards

| Environment | Tool | Dashboard |
|-------------|------|-----------|
| Local | Grafana | `grafana-local.json` |
| Production | Datadog | Kong LLM Gateway |

### Alerts (Production)

| Alert | Condition | Severity |
|-------|-----------|----------|
| High token usage | > 100k tokens/hour | Warning |
| Rate limit hits | > 10/min per consumer | Warning |
| Bedrock errors | > 5% error rate | Critical |
| Latency spike | p99 > 30s | Warning |

---

## Next Steps

1. Create project structure (`kong/`, `infra/`, `docs/`)
2. Implement `bedrock-proxy` plugin
3. Configure role-based routing
4. Set up local Docker Compose environment
5. Write Terraform for EKS/IRSA
6. Create Helm values for production
7. Build observability stack
8. Write runbooks and documentation

---

## Blockers

- None currently

---

## Infrastructure Status

| Resource | State | Notes |
|----------|-------|-------|
| EKS Cluster | NOT CREATED | Terraform pending |
| Kong (local) | NOT RUNNING | Docker Compose pending |
| Bedrock Access | PENDING | IAM policy needed |
| Datadog | PENDING | API key required |

---

## Quick Commands

```bash
# === LOCAL DEVELOPMENT ===
make local/up              # Start Kong + Postgres (Docker Compose)
make local/down            # Stop local environment
make local/logs            # View Kong logs
make local/test            # Run plugin tests (Pongo)

# === EKS DEPLOYMENT ===
make eks/plan              # Terraform plan
make eks/apply             # Terraform apply
make eks/deploy            # Helm upgrade Kong
make eks/status            # Check deployment status

# === VALIDATION ===
make validate              # deck validate + luacheck
make test                  # pongo run (all tests)
make security-scan         # trivy scan

# === DOCKER ONE-LINER (alternative) ===
docker run -d --name kong \
  -e "KONG_DATABASE=off" \
  -e "KONG_DECLARATIVE_CONFIG=/kong/kong.yaml" \
  -e "AWS_PROFILE=default" \
  -e "AWS_REGION=us-east-1" \
  -v $(pwd)/kong:/kong \
  -p 8000:8000 -p 8443:8443 \
  kong:latest

# === CURL EXAMPLES ===
# Local test (with API key)
curl -X POST http://localhost:8000/v1/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: dev-key-123" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'

# Production test (with JWT)
curl -X POST https://api.example.com/v1/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <jwt-token>" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

---

*Update this file at the end of each session*
