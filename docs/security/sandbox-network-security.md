# Stargate Sandbox - Network Security

**Environment:** Sandbox (Production-Ready)
**Region:** us-east-1
**Last Updated:** 2025-01-25

---

## Security Architecture Overview

```
                              INTERNET
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │       CloudFront        │
                    │  ┌───────────────────┐  │
                    │  │    AWS WAF        │  │
                    │  │  • IP Reputation  │  │
                    │  │  • Bot Control    │  │
                    │  │  • Rate Limiting  │  │
                    │  │  • OWASP Rules    │  │
                    │  └───────────────────┘  │
                    │                         │
                    │  Adds: X-Origin-Verify  │
                    └───────────┬─────────────┘
                                │
                    ┌───────────▼─────────────┐
                    │    Security Boundary    │
                    │      (VPC Boundary)     │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
        ┌──────────┐     ┌──────────┐     ┌──────────┐
        │ Port 80  │     │ Port 8080│     │ Port 9090│
        │  (HTTP)  │     │(Langfuse)│     │(Victoria)│
        └────┬─────┘     └────┬─────┘     └────┬─────┘
             │                │                 │
             │ Header         │ Header OR       │ VPC CIDR
             │ Verify         │ VPC CIDR        │ Only
             ▼                ▼                 ▼
        ┌──────────┐     ┌──────────┐     ┌──────────┐
        │ LiteLLM  │     │ Langfuse │     │ Victoria │
        │ Grafana  │     │          │     │ Metrics  │
        └──────────┘     └──────────┘     └──────────┘
                              ▲
                              │ Internal
                              │ Callbacks
                         ┌────┴─────┐
                         │ LiteLLM  │
                         └──────────┘
```

---

## Ingress Rules

### CloudFront (Edge Layer)

| Source | Port | Protocol | Description |
|--------|------|----------|-------------|
| `0.0.0.0/0` | 443 | HTTPS | Public internet access |

**Protections Applied:**
- AWS WAF Web ACL
- TLS 1.2+ only
- Geographic restrictions (optional)

### ALB Security Group

| Source | Port | Protocol | Description |
|--------|------|----------|-------------|
| CloudFront + Header | 80 | HTTP | LiteLLM, Grafana (via X-Origin-Verify) |
| CloudFront + Header | 8080 | HTTP | Langfuse (via X-Origin-Verify) |
| VPC CIDR (10.20.0.0/16) | 8080 | HTTP | Langfuse (internal LiteLLM callbacks) |
| VPC CIDR (10.20.0.0/16) | 9090 | HTTP | Victoria Metrics (internal only) |

**Important:** Direct ALB access without `X-Origin-Verify` header returns `403 Forbidden`.

**Exception:** Internal VPC traffic (10.20.0.0/16) is allowed on ports 8080 and 9090 for service-to-service communication.

### ECS Service Security Groups

#### LiteLLM Service
| Source | Port | Protocol | Description |
|--------|------|----------|-------------|
| ALB SG | 4000 | TCP | API traffic from ALB |
| VPC CIDR | 4000 | TCP | Metrics scraping (Victoria) |

#### Grafana Service
| Source | Port | Protocol | Description |
|--------|------|----------|-------------|
| ALB SG | 3000 | TCP | Dashboard access from ALB |

#### Langfuse Service
| Source | Port | Protocol | Description |
|--------|------|----------|-------------|
| ALB SG | 3000 | TCP | UI/API access from ALB |

#### Victoria Metrics Service
| Source | Port | Protocol | Description |
|--------|------|----------|-------------|
| ALB SG | 8428 | TCP | Prometheus API from ALB |

### RDS Security Group

| Source | Port | Protocol | Description |
|--------|------|----------|-------------|
| VPC CIDR (10.20.0.0/16) | 5432 | TCP | PostgreSQL from ECS services |

### EFS Security Group

| Source | Port | Protocol | Description |
|--------|------|----------|-------------|
| VPC CIDR (10.20.0.0/16) | 2049 | TCP | NFS from ECS services |

---

## Egress Rules

### All ECS Services

| Destination | Port | Protocol | Description |
|-------------|------|----------|-------------|
| `0.0.0.0/0` | 443 | HTTPS | AWS APIs (Bedrock, Secrets Manager, ECR) |
| `0.0.0.0/0` | 80 | HTTP | Package managers (if needed) |
| VPC CIDR | 5432 | TCP | RDS PostgreSQL |
| VPC CIDR | 2049 | TCP | EFS NFS |

### NAT Gateway

| Destination | Port | Protocol | Description |
|-------------|------|----------|-------------|
| `0.0.0.0/0` | All | All | Internet access for private subnets |

---

## WAF Rules (Priority Order)

| Priority | Rule Name | Action | Description |
|----------|-----------|--------|-------------|
| 1 | IP Reputation | BLOCK | AWS managed malicious IP list |
| 2 | Common Rules | BLOCK | OWASP Top 10 (SQLi, XSS, etc.) |
| 3 | Known Bad Inputs | BLOCK | Log4j, Java deserialization |
| 4 | Bot Control | BLOCK/CHALLENGE | Automated bot detection |
| 5 | Rate Limit | BLOCK | 1000 requests/5min per IP |
| Default | - | ALLOW | Pass through if no rule matches |

---

## Header-Based Security

### X-Origin-Verify (Automatic)

**Purpose:** Prevent direct ALB access (WAF bypass prevention)

```
┌──────────────┐         ┌─────────────┐         ┌─────────┐
│   Client     │ ──────► │ CloudFront  │ ──────► │   ALB   │
└──────────────┘         └─────────────┘         └─────────┘
                               │                       │
                               │ Adds header:          │ Checks:
                               │ X-Origin-Verify       │ X-Origin-Verify
                               │ = <secret>            │ = <secret>
                               │                       │
                               │                       ▼
                               │                 Match? ─► Forward
                               │                 No?    ─► 403
```

**Configuration:**
- Secret stored in: `stargate-sandbox/origin-verify-secret`
- Added by: CloudFront (origin custom header)
- Verified by: ALB listener rules

### X-Admin-Secret (Manual)

**Purpose:** Protect admin endpoints from unauthorized access

```
Admin Endpoints Protected:
    /key/*      - API key management
    /user/*     - User management
    /model/*    - Model configuration
    /spend/*    - Spend tracking
```

**Usage:**
```bash
curl https://cloudfront.example.com/user/new \
     -H "Authorization: Bearer sk-master-key" \
     -H "X-Admin-Secret: <admin-secret>"
```

**Configuration:**
- Secret stored in: `stargate-sandbox/admin-header-secret`
- Added by: Administrator (manual)
- Verified by: CloudFront Function

---

## Authentication Layers

| Layer | Mechanism | Scope | Who Provides |
|-------|-----------|-------|--------------|
| 1 | WAF | All traffic | AWS (automatic) |
| 2 | X-Origin-Verify | All traffic | CloudFront (automatic) |
| 3 | X-Admin-Secret | Admin endpoints | Admin (manual) |
| 4 | LiteLLM API Key | /v1/* endpoints | User (manual) |
| 5 | Grafana Login | /grafana/* | User (manual) |
| 6 | Langfuse Login | /langfuse/* | User (manual) |

---

## Endpoint Access Matrix

| Endpoint | Public | WAF | Origin Verify | Admin Secret | App Auth |
|----------|--------|-----|---------------|--------------|----------|
| `/v1/chat/completions` | ✅ | ✅ | ✅ | ❌ | API Key |
| `/v1/models` | ✅ | ✅ | ✅ | ❌ | API Key |
| `/health/*` | ✅ | ✅ | ✅ | ❌ | None |
| `/grafana/*` | ✅ | ✅ | ✅ | ❌ | Login |
| `/langfuse/*` | ✅ | ✅ | ✅ | ❌ | Login |
| `/key/*` | ✅ | ✅ | ✅ | ✅ | Master Key |
| `/user/*` | ✅ | ✅ | ✅ | ✅ | Master Key |
| `/model/*` | ✅ | ✅ | ✅ | ✅ | Master Key |
| `/spend/*` | ✅ | ✅ | ✅ | ✅ | Master Key |
| Victoria Metrics | ❌ | ❌ | ❌ | ❌ | VPC Only |

---

## Internal Service Communication

### Service-to-Service Flows

I seguenti flussi interni **NON** passano da CloudFront/WAF ma usano comunicazione diretta VPC:

```
┌────────────────────────────────────────────────────────────────┐
│                    Internal VPC Traffic                         │
│                                                                 │
│  ┌──────────┐                              ┌──────────────────┐ │
│  │ Grafana  │ ────── Port 9090 ──────────► │ Victoria Metrics │ │
│  └──────────┘     (Prometheus queries)     └──────────────────┘ │
│                                                                 │
│  ┌──────────┐                              ┌──────────────────┐ │
│  │ LiteLLM  │ ────── Port 8080 ──────────► │     Langfuse     │ │
│  └──────────┘     (Tracing callbacks)      └──────────────────┘ │
│                                                                 │
│  ┌──────────┐                              ┌──────────────────┐ │
│  │ Victoria │ ────── Port 80 ────────────► │     LiteLLM      │ │
│  │ Metrics  │     (Metrics scraping)       │   /metrics/      │ │
│  └──────────┘                              └──────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

| Source | Destination | Port | Purpose |
|--------|-------------|------|---------|
| Grafana | Victoria Metrics | 9090 | Query metriche per dashboard |
| LiteLLM | Langfuse | 8080 | Invio trace/span per observability |
| Victoria Metrics | LiteLLM | 80 | Scraping metriche Prometheus |

**Nota:** Questi flussi usano VPC CIDR (10.20.0.0/16) come source IP e non richiedono X-Origin-Verify header.

---

## Data Encryption

### In Transit

| Connection | Encryption | Protocol |
|------------|------------|----------|
| Client → CloudFront | TLS 1.2+ | HTTPS |
| CloudFront → ALB | None (internal) | HTTP |
| ALB → ECS Services | None (internal) | HTTP |
| ECS → RDS | TLS | PostgreSQL SSL |
| ECS → Bedrock | TLS 1.2+ | HTTPS |

### At Rest

| Resource | Encryption | Key Management |
|----------|------------|----------------|
| RDS PostgreSQL | AES-256 | AWS managed |
| EFS | AES-256 | AWS managed |
| Secrets Manager | AES-256 | AWS managed |
| CloudWatch Logs | AES-256 | AWS managed |

---

## Secrets Management

| Secret | Location | Used By |
|--------|----------|---------|
| `stargate-sandbox/origin-verify-secret` | Secrets Manager | CloudFront, ALB |
| `stargate-sandbox/admin-header-secret` | Secrets Manager | CloudFront Function |
| `stargate-sandbox/litellm-master-key` | Secrets Manager | LiteLLM |
| `stargate-sandbox/grafana-admin-password` | Secrets Manager | Grafana |
| `stargate-sandbox/langfuse-*` | Secrets Manager | Langfuse |
| RDS credentials | Secrets Manager (auto) | LiteLLM, Langfuse |

---

## Network Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                       │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        VPC: 10.20.0.0/16                              │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    PUBLIC SUBNETS                               │  │  │
│  │  │  10.20.101.0/24 │ 10.20.102.0/24 │ 10.20.103.0/24              │  │  │
│  │  │                                                                 │  │  │
│  │  │    ┌─────────┐       ┌─────────┐                               │  │  │
│  │  │    │   ALB   │       │   NAT   │                               │  │  │
│  │  │    │         │       │ Gateway │                               │  │  │
│  │  │    └────┬────┘       └────┬────┘                               │  │  │
│  │  └─────────┼─────────────────┼─────────────────────────────────────┘  │  │
│  │            │                 │                                        │  │
│  │  ┌─────────▼─────────────────▼─────────────────────────────────────┐  │  │
│  │  │                    PRIVATE SUBNETS                              │  │  │
│  │  │  10.20.1.0/24  │  10.20.2.0/24  │  10.20.3.0/24                │  │  │
│  │  │                                                                 │  │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │  │  │
│  │  │  │ LiteLLM  │  │ Grafana  │  │ Langfuse │  │ Victoria │       │  │  │
│  │  │  │ (x2-6)   │  │  (x2)    │  │  (x2)    │  │  (x1)    │       │  │  │
│  │  │  └────┬─────┘  └──────────┘  └────┬─────┘  └────┬─────┘       │  │  │
│  │  │       │                           │             │              │  │  │
│  │  │       │         ┌─────────────────┴─────────────┘              │  │  │
│  │  │       │         │                                              │  │  │
│  │  │  ┌────▼─────────▼────┐         ┌──────────┐                   │  │  │
│  │  │  │  RDS PostgreSQL   │         │   EFS    │                   │  │  │
│  │  │  │   (Multi-AZ)      │         │          │                   │  │  │
│  │  │  └───────────────────┘         └──────────┘                   │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────┐                    ┌───────────────────┐            │
│  │    CloudFront     │◄───────────────────│    AWS Bedrock    │            │
│  │    + WAF          │                    │  (Claude Models)  │            │
│  └───────────────────┘                    └───────────────────┘            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Security Checklist

### Pre-Deployment

- [ ] Create all secrets in Secrets Manager (us-east-1)
- [ ] Generate strong random values (32+ characters) for:
  - [ ] `origin-verify-secret`
  - [ ] `admin-header-secret`
  - [ ] `litellm-master-key`
  - [ ] `grafana-admin-password`
- [ ] Verify Bedrock model access in us-east-1
- [ ] Review WAF rules configuration

### Post-Deployment

- [ ] Test direct ALB access returns 403
- [ ] Test CloudFront access works
- [ ] Test admin endpoints require X-Admin-Secret
- [ ] Test rate limiting (trigger 1000+ requests)
- [ ] Verify Victoria Metrics not accessible externally
- [ ] Review CloudWatch logs for anomalies

### Ongoing

- [ ] Rotate secrets quarterly
- [ ] Review WAF logs weekly
- [ ] Monitor for unusual traffic patterns
- [ ] Update WAF rules as needed
