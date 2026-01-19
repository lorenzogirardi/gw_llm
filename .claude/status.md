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

| Role | Models | Rate Limit | Notes |
|------|--------|------------|-------|
| `admin` | All models | Unlimited | Full access |
| `developer` | Opus, Sonnet, Haiku | 10 req/s, 100K tokens/day | AI coding, feature development |
| `analyst` | Haiku, Titan | 5 req/s, 50K tokens/day | Data analysis |
| `ecommerce_ops` | Haiku | 3 req/s, 20K tokens/day | Product descriptions |
| `guest` | Haiku | 1 req/s, 1K tokens/day | Limited demo access |

### Model IDs

| Model | Bedrock Model ID |
|-------|------------------|
| Claude Opus 4 | `anthropic.claude-opus-4-20250514-v1:0` |
| Claude Sonnet 4 | `anthropic.claude-sonnet-4-20250514-v1:0` |
| Claude Haiku | `anthropic.claude-3-haiku-20240307-v1:0` |
| Titan Text | `amazon.titan-text-express-v1` |

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
- [x] `docker-compose.yml` - Local Kong + Postgres + Mock Bedrock
- [x] `kong/kong.yaml` - Declarative DB-less config with RBAC
- [x] `infra/helm/kong/values-*.yaml` - EKS Helm values (base, dev, prod)

### Infrastructure
- [x] `infra/terraform/modules/eks/` - EKS cluster
- [x] `infra/terraform/modules/kong/` - Kong Helm deployment
- [x] `infra/terraform/modules/bedrock/` - IAM/IRSA for Bedrock
- [x] `infra/terraform/environments/dev/` - Dev environment
- [x] `infra/terraform/environments/prod/` - Prod environment

### Custom Plugins
- [x] `kong/plugins/bedrock-proxy/` - Bedrock integration + SigV4
- [x] `kong/plugins/token-meter/` - Token tracking + cost estimation
- [x] `kong/plugins/ecommerce-guardrails/` - PCI-DSS/GDPR pattern blocking

### Observability
- [x] Prometheus configuration (metrics scraping)
- [x] Datadog integration (prod alerting)
- [x] Grafana dashboard JSON
- [ ] CloudWatch Bedrock metrics (pending AWS deploy)

### Automation
- [x] `Makefile` - multi-env commands
- [x] ArgoCD manifests (dev + prod)
- [x] `infra/k8s/kong-config/` - Kustomize for ConfigMaps

### Documentation
- [x] `docs/architecture/c4-architecture.md` - C4 diagrams with Mermaid
- [x] `docs/runbooks/high-error-rate.md`
- [x] `docs/runbooks/high-latency.md`
- [x] `docs/runbooks/token-quota-exceeded.md`
- [x] `docs/examples/curl-examples.md` - API testing examples
- [x] `README.md` - Complete usage guide

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

## Next Steps (Pending)

### CI/CD & Testing
- [ ] GitHub Actions CI workflow (lint, test, security scan)
- [ ] GitHub Actions deploy workflow (EKS via ArgoCD)
- [ ] Plugin test suite (Pongo/Busted)
  - [ ] `kong/plugins/bedrock-proxy/spec/handler_spec.lua`
  - [ ] `kong/plugins/token-meter/spec/handler_spec.lua`
  - [ ] `kong/plugins/ecommerce-guardrails/spec/handler_spec.lua`

### AWS Deployment
- [ ] Deploy to EKS (pending AWS account readiness)
- [ ] Configure IRSA for Bedrock access
- [ ] Validate NLB and DNS setup

### Post-Deploy Tests (AWS)
- [ ] Smoke tests (health check, basic request)
- [ ] Integration tests (all endpoints, all roles)
- [ ] Load tests (rate limiting validation)
- [ ] Security tests (guardrails validation)

### Cleanup
- [ ] Consolidate `observability/` directories
- [ ] Add LICENSE file (MIT)

---

## Blockers

- AWS account not ready for deployment

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
