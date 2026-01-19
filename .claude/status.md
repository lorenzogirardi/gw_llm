# Project Status: Kong LLM Gateway

**Last Updated:** 2026-01-20
**Current Phase:** POC Implementation - Bedrock Integration Working

---

## POC Environment (DEPLOYED)

### Live Endpoints

| Service | URL |
|---------|-----|
| **API (CloudFront)** | https://d18l8nt8fin3hz.cloudfront.net |
| **Grafana** | https://d18l8nt8fin3hz.cloudfront.net/grafana |
| **Kong ALB** | kong-llm-gateway-poc-1159371345.us-west-1.elb.amazonaws.com |

### API Routes

| Route | Model | Status |
|-------|-------|--------|
| `/v1/chat/completions` | Haiku 4.5 (default) | WORKING |
| `/v1/messages` | Haiku 4.5 (default) | WORKING |
| `/v1/chat/haiku` | Haiku 4.5 | WORKING |
| `/v1/chat/opus` | Opus 4.5 | NEEDS USE CASE FORM |
| `/v1/chat/sonnet` | Sonnet 4 | NEEDS USE CASE FORM |
| `/health` | - | WORKING |

### Credentials

| Service | Credentials | Location |
|---------|-------------|----------|
| **Grafana** | admin / FsdnbxMi7erbiSYg. | Secrets Manager |
| **Kong API (dev)** | `hRbLUp1HJtMgVemwJQR6GzeIBbRsf7xI` | kong/.api-keys.txt |
| **Kong API (prod)** | `xBQQDv9gitRU3kTdZ7ilZk+9NgQgjn6G` | kong/.api-keys.txt |
| **AWS Bedrock** | IAM User: kong-bedrock-poc | Secrets Manager |

### Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────────────────────────┐     ┌─────────────────┐
│   Clients   │────▶│  CloudFront  │────▶│       ECS Fargate Cluster        │────▶│   AWS Bedrock   │
│             │     │   (HTTPS)    │     │  ┌────────────────────────────┐  │     │                 │
└─────────────┘     └──────────────┘     │  │ Kong Gateway (DB-less)     │  │     │  - Haiku 4.5 ✓  │
                                         │  │ + bedrock-proxy (SigV4)    │  │     │  - Opus 4.5 ⚠   │
                                         │  │ + token-meter plugin       │  │     │  - Sonnet 4 ⚠   │
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
```

---

## Recent Changes (2026-01-20)

### Bedrock Proxy Plugin
1. **SigV4 Signing Implemented**: Full AWS SigV4 authentication working
2. **URL Encoding Fixed**: Proper RFC 3986 encoding for model IDs with special chars
3. **Multi-source Credentials**: Env vars → ECS Full URI → ECS Relative URI → IMDS
4. **Nginx Env Directive**: Added `KONG_NGINX_MAIN_ENV` for credential passthrough
5. **Model IDs Updated**: Using cross-region inference profiles (`us.anthropic.*`)

### Security
1. **API Keys Rotated**: 32-char alphanumeric with symbols
2. **Secrets in .gitignore**: kong.yaml with real keys excluded from git
3. **Template File**: kong.yaml.template with placeholders for git

### Claude Code Hooks
1. **PreToolUse Hook**: Blocks .lua edits without `/lua` skill
2. **PreToolUse Hook**: Blocks bedrock/IAM edits without `/aws-bedrock` skill
3. **UserPromptSubmit Hook**: Commit checklist reminder
4. **Skill Activation**: Marker files (`/tmp/claude_skill_*`)

---

## TODO

### Immediate
- [ ] Submit Anthropic use case form in AWS Console for Opus/Sonnet access
- [ ] Test Claude Code compatibility with Kong proxy
- [ ] Write tests for bedrock-proxy plugin (TDD debt)
- [ ] Update docs/plugins/bedrock-proxy.md

### Future
- [ ] Add streaming support to bedrock-proxy
- [ ] Implement token counting per consumer
- [ ] Add request/response logging plugin
- [ ] Set up alerts in Grafana

---

## Test Commands

```bash
# Test Haiku (working)
curl -X POST https://d18l8nt8fin3hz.cloudfront.net/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-API-Key: hRbLUp1HJtMgVemwJQR6GzeIBbRsf7xI" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"max_tokens":50}'

# Test health
curl https://d18l8nt8fin3hz.cloudfront.net/health

# View Kong logs
aws logs tail /ecs/kong-llm-gateway-poc/kong --follow --region us-west-1

# Check ECS services
aws ecs describe-services --cluster kong-llm-gateway-poc \
  --services kong grafana victoria-metrics --region us-west-1 \
  --query 'services[*].{name:serviceName,running:runningCount}'
```

---

## Known Issues

1. **Opus/Sonnet Blocked**: "Model use case details have not been submitted" - need to fill AWS form
2. **TDD Debt**: No tests written for bedrock-proxy plugin changes
3. **Documentation Debt**: docs/plugins/bedrock-proxy.md not updated

---

## Files Changed This Session

| File | Change |
|------|--------|
| `kong/plugins/bedrock-proxy/handler.lua` | SigV4 signing, URL encoding, multi-source creds |
| `kong/config/kong.yaml` | New API keys, inference profile model IDs |
| `kong/config/kong.yaml.template` | Template with placeholders |
| `kong/.gitignore` | Exclude secrets |
| `kong/.api-keys.txt` | Store real API keys |
| `.claude/settings.json` | Hook configuration |
| `.claude/hooks/check-skill.sh` | Skill enforcement hook |
| `.claude/hooks/commit-checklist.py` | Commit reminder hook |
| `.claude/skills/lua/SKILL.md` | Activation marker |
| `.claude/skills/aws-bedrock/SKILL.md` | Activation marker |
| `infra/terraform/modules/victoria-metrics/` | New module |
| `infra/terraform/modules/ecs/` | Secrets support |

---

*Update this file at the end of each session*
