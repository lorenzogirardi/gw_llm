# LiteLLM User Management Guide

This guide explains how to manage users and API keys in the LiteLLM gateway.

## Overview

```mermaid
flowchart TB
    subgraph Admin["Admin (VPC Only)"]
        script[litellm-users.sh]
        alb[ALB Direct]
    end

    subgraph LiteLLM["LiteLLM Proxy"]
        api[User/Key API]
        budget[Budget Manager]
    end

    subgraph Storage["PostgreSQL (RDS)"]
        users[(Users Table)]
        keys[(API Keys Table)]
        spend[(Spend Table)]
    end

    script -->|curl| alb
    alb --> api
    api --> budget
    budget <--> users & keys & spend

    style Admin fill:#ccffcc
    style Storage fill:#336791,color:#fff
```

## Prerequisites

### Current Status (POC)

The POC includes **PostgreSQL** (RDS db.t4g.micro) for full user management:

| Feature | Available | Notes |
|---------|-----------|-------|
| Single API Key (master) | ✅ | Works |
| Create API keys with budget | ✅ | Works |
| Create users with budget | ✅ | Works |
| Associate models to users | ✅ | Works |
| Per-user spend tracking | ✅ | Works |

The database is automatically configured by Terraform.

### Security Model

```mermaid
flowchart LR
    subgraph Internet
        client[Client]
    end

    subgraph CloudFront
        cf[CloudFront]
    end

    subgraph VPC["AWS VPC"]
        alb[ALB]
        litellm[LiteLLM]
    end

    client -->|/v1/chat/completions ✅| cf
    client -->|/user/* ❌ 403| cf
    cf --> alb
    alb --> litellm

    admin[Admin VPN] -->|/user/* ✅| alb

    style cf fill:#ffcccc
    style admin fill:#ccffcc
```

> **⚠️ Security**: Admin endpoints (`/user/*`, `/key/*`, `/model/*`, `/spend/*`) are **blocked by CloudFront** and only accessible via ALB from within the VPC.

---

## Quick Start

### 1. Configure environment

```bash
# Export master key
export LITELLM_MASTER_KEY="sk-litellm-xxxxxxxxxx"

# Optional: Custom URL
export LITELLM_URL="https://d18l8nt8fin3hz.cloudfront.net"
```

### 2. Use the script

```bash
cd scripts/

# Show help
./litellm-users.sh help

# Create a user
./litellm-users.sh create-user --email user@example.com --budget 50

# Generate API key
./litellm-users.sh create-key --alias "user-laptop"

# List users
./litellm-users.sh list-users
```

---

## Available Commands

### User Management

#### Create a user

```bash
# Basic user
./litellm-users.sh create-user --email user@example.com

# With monthly budget
./litellm-users.sh create-user \
  --email user@example.com \
  --budget 50 \
  --duration monthly

# With specific models
./litellm-users.sh create-user \
  --email dev@example.com \
  --budget 10 \
  --models '["claude-haiku-4-5"]'
```

#### List users

```bash
./litellm-users.sh list-users
```

#### Get user info

```bash
./litellm-users.sh get-user <user_id>
```

#### Delete user

```bash
./litellm-users.sh delete-user <user_id>
```

#### Update budget

```bash
./litellm-users.sh update-budget --user-id <user_id> --budget 100
```

---

### API Key Management

#### Generate API key

```bash
# Standalone key with budget
./litellm-users.sh create-key \
  --alias "test-key" \
  --budget 5 \
  --duration monthly

# Key for specific user
./litellm-users.sh create-key \
  --user-id user_xxx \
  --alias "laptop-key"

# Key with limited models
./litellm-users.sh create-key \
  --alias "haiku-only" \
  --models '["claude-haiku-4-5"]' \
  --budget 10
```

#### List API keys

```bash
./litellm-users.sh list-keys
```

#### Delete API key

```bash
./litellm-users.sh delete-key sk-litellm-xxx
```

---

## Associating Models to Users

### Limit models per user

When creating a user, you can specify which models they can use:

```bash
# Haiku only (economical)
./litellm-users.sh create-user \
  --email intern@example.com \
  --budget 5 \
  --models '["claude-haiku-4-5"]'

# Haiku and Sonnet
./litellm-users.sh create-user \
  --email developer@example.com \
  --budget 50 \
  --models '["claude-haiku-4-5", "claude-sonnet-4-5"]'

# All models
./litellm-users.sh create-user \
  --email senior@example.com \
  --budget 200
```

### Limit models per API key

```bash
# Testing key (Haiku only, low budget)
./litellm-users.sh create-key \
  --alias "test-key" \
  --models '["claude-haiku-4-5"]' \
  --budget 2

# Production key (all models)
./litellm-users.sh create-key \
  --alias "prod-key" \
  --budget 100
```

---

## Practical Examples

### Scenario 1: Development team

```bash
# Lead developer - all models, high budget
./litellm-users.sh create-user \
  --email lead@company.com \
  --budget 200 \
  --duration monthly

# Developer - Haiku and Sonnet, medium budget
./litellm-users.sh create-user \
  --email dev@company.com \
  --budget 50 \
  --duration monthly \
  --models '["claude-haiku-4-5", "claude-sonnet-4-5"]'

# Intern - Haiku only, low budget
./litellm-users.sh create-user \
  --email intern@company.com \
  --budget 10 \
  --duration monthly \
  --models '["claude-haiku-4-5"]'
```

### Scenario 2: Keys for different environments

```bash
# Development (Haiku only, low budget)
./litellm-users.sh create-key \
  --alias "dev-environment" \
  --models '["claude-haiku-4-5"]' \
  --budget 20

# Staging (all models, medium budget)
./litellm-users.sh create-key \
  --alias "staging-environment" \
  --budget 100

# Production (all models, high budget)
./litellm-users.sh create-key \
  --alias "production" \
  --budget 500
```

---

## Using curl directly

If you prefer not to use the script:

> **⚠️ Important**: Admin endpoints are blocked by CloudFront. Use ALB direct from within the VPC.

### Create user

```bash
# Via ALB (from within the VPC) - WORKS
curl -X POST "http://kong-llm-gateway-poc-xxx.us-west-1.elb.amazonaws.com/user/new" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "user@example.com",
    "max_budget": 50,
    "budget_duration": "monthly",
    "models": ["claude-haiku-4-5"]
  }'

# Via CloudFront - BLOCKED (403 Forbidden)
# curl -X POST "https://d18l8nt8fin3hz.cloudfront.net/user/new" ...
```

### Generate API key

```bash
# Via ALB (from within the VPC)
curl -X POST "http://kong-llm-gateway-poc-xxx.us-west-1.elb.amazonaws.com/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "my-key",
    "max_budget": 10,
    "models": ["claude-haiku-4-5"]
  }'
```

### List users

```bash
# Via ALB (from within the VPC)
curl -X GET "http://kong-llm-gateway-poc-xxx.us-west-1.elb.amazonaws.com/user/list" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

---

## Database Configuration (Optional)

For full user management, PostgreSQL is required.

### Option 1: RDS PostgreSQL

Add to Terraform:

```hcl
module "litellm_db" {
  source = "../../modules/rds"

  identifier = "litellm-poc"
  engine     = "postgres"
  engine_version = "15"
  instance_class = "db.t4g.micro"  # ~$12/month

  allocated_storage = 20
  db_name           = "litellm"
  username          = "litellm"

  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.litellm_db.id]
}
```

Then configure LiteLLM:

```yaml
general_settings:
  database_url: "postgresql://user:pass@host:5432/litellm"
```

### Option 2: Aurora Serverless v2

For variable costs based on usage (~$0.06/ACU-hour).

### Estimated costs

| Option | Monthly Cost |
|--------|--------------|
| RDS t4g.micro | ~$12-15 |
| Aurora Serverless v2 | ~$5-20 (variable) |
| No DB (master key only) | $0 |

---

## Troubleshooting

### "Database not connected"

```
Internal Server Error, Database not connected
```

**Cause**: LiteLLM does not have a database configured.
**Solution**: Use master key or configure PostgreSQL.

### "Invalid API Key"

```
Authentication Error: Invalid API Key
```

**Cause**: The key does not exist or has expired.
**Solution**: Verify the key with `list-keys` or generate a new one.

### "Budget exceeded"

```
Budget has been exceeded
```

**Cause**: The user/key has exceeded their budget.
**Solution**: Increase budget with `update-budget`.

---

## References

- [LiteLLM Proxy Documentation](https://docs.litellm.ai/docs/simple_proxy)
- [LiteLLM User Management](https://docs.litellm.ai/docs/proxy/users)
- [LiteLLM Virtual Keys](https://docs.litellm.ai/docs/proxy/virtual_keys)
