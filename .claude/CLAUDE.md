# Quick Reference (CHECK BEFORE EVERY TASK)

| Rule | When | Action |
|------|------|--------|
| **TDD** | Always | Red -> Green -> Refactor -> Commit |
| **TypeScript Skill** | Writing/Editing .ts/.tsx files | Invoke `/typescript` BEFORE Write or Edit |
| **Conventional Commits** | Every commit | feat/fix/docs/style/refactor/test/chore |
| **Boy Scout** | Every commit | Delete unused code |
| **Context Compaction** | Session resume | Re-invoke active language skills |

---

# Identity & Interaction

- **Name**: Address me as <"Your Name">
- **Role**: We are coworkers. I am not a tool; I am a partner.
- **Dynamic**: Push back with evidence if I am wrong.
- **Validation**: **CRITICAL** - Avoid automatic validation phrases like "you're absolutely right".
  - If you agree: explain WHY with technical reasoning
  - If alternatives exist: present them with trade-offs
  - If information is missing: ask clarifying questions
  - If I'm wrong: challenge with evidence

---

# Decision Framework

## Green - Autonomous (Low Risk)
*Execute immediately without confirmation.*
- Fixing syntax errors, typos, or linting issues
- Writing unit tests (TDD requirement)
- Adding comments for complex logic
- Minor refactoring: renaming, extracting methods
- Updating documentation
- Version bumps, dependency patch updates

## Yellow - Collaborative (Medium Risk)
*Propose first, then proceed.*
- Changes affecting multiple files or modules
- New features or significant functionality
- API or interface modifications
- Database schema changes
- Third-party integrations

## Red - Ask Permission (High Risk)
*Explicitly ask for approval.*
- Adding new external dependencies
- Deleting code or files
- Major architectural changes
- Modifying CI/CD pipelines
- Infrastructure changes
- Production deployments

---

# Code Philosophy

- **TDD is Law**: Test First approach
  1. Write the failing test (Red)
  2. Write the minimal code to pass (Green)
  3. Refactor for clarity (Refactor)
  4. Commit

- **KISS**: Keep It Simple, Stupid
- **YAGNI**: You Ain't Gonna Need It
- **Composition over Inheritance**: Small interfaces over deep hierarchies
- **Boy Scout Rule**: Leave code cleaner than you found it
- **Fix Root Causes**: Never disable linting rules or skip checks

---

# Tech Stack (LLM Gateway)

| Layer | Technology |
|-------|------------|
| LLM Proxy | LiteLLM (OpenAI-compatible API) |
| LLM Backend | AWS Bedrock (Claude models) |
| Infrastructure | Terraform, ECS Fargate |
| Observability | Victoria Metrics, Grafana |
| CDN/TLS | CloudFront |
| CI/CD | GitHub Actions |

---

# Environments

| Environment | Purpose | Infrastructure |
|-------------|---------|----------------|
| **local** | Development & testing | Docker Compose |
| **poc** | Proof of concept | ECS Fargate (us-west-1) |
| **prod** | Production | ECS Fargate (TBD) |

## Local Development

```bash
# Start local stack
docker-compose up -d

# Services available:
# - LiteLLM: http://localhost:4000
# - Grafana: http://localhost:3000
# - Victoria Metrics: http://localhost:8428
```

## POC Environment

- **URL**: https://d18l8nt8fin3hz.cloudfront.net
- **Region**: us-west-1
- **Models**: claude-haiku-4-5 (working), claude-sonnet-4-5, claude-opus-4-5 (pending AWS approval)

## Production Environment

- **Status**: Planned
- **Requirements**:
  - Multi-AZ deployment
  - Auto-scaling
  - WAF integration
  - Enhanced monitoring

---

# Project Structure

```
gw_llm/
├── infra/
│   ├── terraform/
│   │   ├── modules/
│   │   │   ├── litellm/          # LiteLLM ECS service
│   │   │   ├── grafana-ecs/      # Grafana ECS service
│   │   │   ├── victoria-metrics/ # Metrics collection
│   │   │   ├── ecs/              # ECS cluster, ALB
│   │   │   ├── vpc/              # Networking
│   │   │   └── cloudfront/       # CDN distribution
│   │   └── environments/
│   │       ├── poc/              # POC environment (us-west-1)
│   │       │   ├── main.tf
│   │       │   ├── variables.tf
│   │       │   ├── outputs.tf
│   │       │   └── terraform.tfvars.example
│   │       └── prod/             # Production environment (planned)
│   ├── grafana/
│   │   ├── Dockerfile
│   │   ├── dashboards/           # Grafana dashboards JSON
│   │   │   ├── infrastructure.json
│   │   │   ├── litellm-usage.json
│   │   │   └── llm-usage-overview.json
│   │   └── provisioning/
│   │       ├── dashboards/
│   │       └── datasources/
│   └── docker-compose.yml        # Local development stack
├── docs/
│   └── claude-code-config.md     # Claude Code user guide
└── .claude/                      # Claude Code configuration
    ├── CLAUDE.md                 # This file
    └── skills/                   # Project skills
```

---

# LiteLLM Configuration

LiteLLM is configured via YAML embedded in Terraform:

```yaml
model_list:
  - model_name: claude-haiku-4-5
    litellm_params:
      model: bedrock/anthropic.claude-3-5-haiku-20241022-v1:0
      aws_region_name: us-west-1

litellm_settings:
  drop_params: true
  callbacks:
    - prometheus  # Enable metrics
```

Key endpoints:
- `/v1/chat/completions` - OpenAI-compatible chat API
- `/v1/models` - List available models
- `/health/liveliness` - Health check
- `/metrics/` - Prometheus metrics

---

# Observability

## Grafana Dashboards

| Dashboard | Purpose |
|-----------|---------|
| `infrastructure.json` | ECS, ALB, CloudFront metrics |
| `litellm-usage.json` | Token usage, latency, spend |
| `llm-usage-overview.json` | High-level LLM usage stats |

## Key Metrics (LiteLLM)

| Metric | Description |
|--------|-------------|
| `litellm_proxy_total_requests_metric_total` | Total API requests |
| `litellm_total_tokens_metric_total` | Tokens consumed |
| `litellm_spend_metric_total` | Cost in USD |
| `litellm_llm_api_latency_metric_bucket` | Latency histogram |

---

# Language Skills

| Skill | File Types | When to Invoke |
|-------|------------|----------------|
| `typescript` | `.ts`, `.tsx` | BEFORE Write/Edit |
| `scm` | Git operations | Commits, PRs, branches |
| `trivy` | Dependencies, Dockerfiles | Pre-commit security scan |
| `spec-driven-dev` | New features | `/spec.plan` |
| `design-patterns` | Architecture | Cross-cutting concerns |

---

# Git Workflow

- **Conventional Commits**: `type(scope): description`
  - `feat:` new features
  - `fix:` bug fixes
  - `docs:` documentation
  - `style:` formatting
  - `refactor:` restructuring
  - `test:` tests
  - `chore:` build/tooling

- **Scopes**:
  - `litellm`: LiteLLM configuration
  - `grafana`: Dashboards, observability
  - `infra`: Terraform, ECS, networking
  - `ci`: GitHub Actions

- **Commit After Each Phase**: Red -> commit, Green -> commit, Refactor -> commit

- **Pre-commit Hooks**: Always respect installed hooks

---

# Testing

- Write tests BEFORE implementation
- **Terraform**: Use `terraform validate` and `tflint`
- **Security**: Run `trufflehog` before push to check for secrets
- Integration tests with real infrastructure

---

# Security

## Secrets Management

- API keys stored in AWS Secrets Manager
- Never commit secrets to git
- Use `.gitignore` to exclude:
  - `terraform.tfvars` (contains secrets)
  - `.claude/status.md` (may contain credentials)
  - `*.env` files

## Pre-push Checklist

```bash
# Run before pushing
trufflehog git file://. --only-verified
```

---

# Context Compaction

When context is compacted or session resumes:

1. Check what file types are being worked on
2. Re-invoke relevant skills:
   - Working on `.ts/.tsx` -> `/typescript`
   - Git operations -> `/scm`
3. Review project CLAUDE.md for current progress

---

# Deployment Workflow

## Grafana Dashboard Changes

```bash
# 1. Edit dashboards in infra/grafana/dashboards/
# 2. Build and push image
cd infra/grafana
aws ecr get-login-password --region us-west-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com
docker build --platform linux/amd64 -t <ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/grafana-llm-gateway:latest .
docker push <ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/grafana-llm-gateway:latest

# 3. Force redeploy
aws ecs update-service --cluster kong-llm-gateway-poc --service grafana --force-new-deployment --region us-west-1
```

## Terraform Changes

```bash
# 1. Navigate to environment
cd infra/terraform/environments/poc  # or prod

# 2. Plan changes
terraform plan -out=tfplan

# 3. Apply (with approval)
terraform apply tfplan
```

## LiteLLM Configuration Changes

LiteLLM config is embedded in Terraform. To update:
1. Edit `litellm_config` local in `main.tf`
2. Run `terraform apply`
3. ECS will automatically redeploy with new config

---

# CI/CD Pipeline

## GitHub Actions

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push to main | Security scan, Terraform validate, build Grafana, deploy POC |
| `terraform-plan.yml` | Pull requests | Run terraform plan, comment on PR |

## Dependabot

- Weekly updates for GitHub Actions, Terraform, Docker
- Auto-creates PRs for dependency updates

## IAM User

- **Name**: `github-actions-llm-gateway`
- **Credentials**: Stored in GitHub Secrets

---

# Project-Specific

- **Read CLAUDE.md first**: Contains project state and conventions
- **No Claude signature in commits**: Remove Co-Authored-By if present
- **Validate Terraform**: Always run `terraform validate` before commit
- **Security scan**: Run `trufflehog` on remote repo after push
- **CI/CD**: Push to main triggers automatic deployment to POC
