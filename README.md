# Claude Toolkit for Kong Gateway + AWS Bedrock

Skills and templates for developing a Kong API Gateway that proxies requests to AWS Bedrock LLM services.

## Architecture Overview

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Clients   │────▶│   Kong Gateway   │────▶│   AWS Bedrock   │
│  (API Keys) │     │  (Rate Limit,    │     │  (Claude, Titan │
│             │     │   Auth, Logging) │     │   Llama, etc.)  │
└─────────────┘     └──────────────────┘     └─────────────────┘
                            │
                    ┌───────┴───────┐
                    │ Custom Plugins│
                    │ - Auth        │
                    │ - Rate Limit  │
                    │ - Bedrock Proxy│
                    └───────────────┘
```

## How to Activate

Copy to your `~/.claude/` directory:

```bash
# Copy all skills
cp -r .claude/skills/* ~/.claude/skills/

# Copy user config template
cp .claude/CLAUDE.md ~/.claude.md
```

## Structure

```
.claude/
├── README.md                      # This file
├── CLAUDE.md                      # Project conventions
├── status.md                      # Progress tracking template
├── templates/
│   ├── spec.md                    # Feature spec template
│   └── tasks.md                   # Task breakdown template
└── skills/
    ├── lua/SKILL.md               # Lua/Kong plugin development
    ├── aws-bedrock/SKILL.md       # AWS Bedrock integration
    ├── scm/SKILL.md               # Git workflow
    ├── trivy/SKILL.md             # Security scanning
    ├── spec-driven-dev/SKILL.md   # Feature specs
    └── design-patterns/SKILL.md   # Architecture patterns
```

## Skills Overview

| Skill | Trigger | Purpose |
|-------|---------|---------|
| **lua** | `.lua` files | Kong plugin development in Lua |
| **aws-bedrock** | Bedrock/IAM | AWS Bedrock model integration |
| **scm** | Git operations | Conventional commits, PR workflow |
| **trivy** | Dependencies, Helm | Pre-commit security scanning |
| **spec-driven-dev** | `/spec.plan` | Feature specs to tasks |
| **design-patterns** | Architecture | Plugin patterns, error handling |

## Tech Stack

| Component | Technology |
|-----------|------------|
| API Gateway | Kong Gateway (DB-less) |
| Plugins | Lua (Kong PDK) |
| LLM Backend | AWS Bedrock |
| Infrastructure | Terraform, EKS, Helm |
| Testing | Pongo, Busted |
| CI/CD | GitHub Actions |

## Key Commands

```bash
# Validate Kong config
deck validate -s kong/kong.yaml

# Test plugins locally
pongo run

# Terraform plan
terraform -chdir=infra/terraform/environments/dev plan

# Deploy to dev
helm upgrade kong kong/kong -f infra/helm/kong-values.yaml
```

## Decision Framework

| Tier | Color | Action | Examples |
|------|-------|--------|----------|
| Low Risk | Green | Proceed autonomously | Lint fixes, test updates, docs |
| Medium Risk | Yellow | Propose first | New plugins, config changes |
| High Risk | Red | Require approval | Infra, deploys, IAM changes |
