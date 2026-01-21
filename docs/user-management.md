# LiteLLM User Management Guide

Questa guida spiega come gestire utenti e API key nel gateway LiteLLM.

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

## Prerequisiti

### Stato Attuale (POC)

Il POC include **PostgreSQL** (RDS db.t4g.micro) per user management completo:

| Feature | Disponibile | Note |
|---------|-------------|------|
| API Key singola (master) | ✅ | Funziona |
| Creare API keys con budget | ✅ | Funziona |
| Creare utenti con budget | ✅ | Funziona |
| Associare modelli a utenti | ✅ | Funziona |
| Tracking spesa per utente | ✅ | Funziona |

Il database è configurato automaticamente da Terraform.

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

> **⚠️ Security**: Gli endpoint admin (`/user/*`, `/key/*`, `/model/*`, `/spend/*`) sono **bloccati da CloudFront** e accessibili solo via ALB dall'interno della VPC.

---

## Quick Start

### 1. Configurare l'ambiente

```bash
# Esporta la master key
export LITELLM_MASTER_KEY="sk-litellm-xxxxxxxxxx"

# Opzionale: URL custom
export LITELLM_URL="https://d18l8nt8fin3hz.cloudfront.net"
```

### 2. Usare lo script

```bash
cd scripts/

# Mostra help
./litellm-users.sh help

# Crea un utente
./litellm-users.sh create-user --email user@example.com --budget 50

# Genera API key
./litellm-users.sh create-key --alias "user-laptop"

# Lista utenti
./litellm-users.sh list-users
```

---

## Comandi Disponibili

### Gestione Utenti

#### Creare un utente

```bash
# Utente base
./litellm-users.sh create-user --email user@example.com

# Con budget mensile
./litellm-users.sh create-user \
  --email user@example.com \
  --budget 50 \
  --duration monthly

# Con modelli specifici
./litellm-users.sh create-user \
  --email dev@example.com \
  --budget 10 \
  --models '["claude-haiku-4-5"]'
```

#### Listare utenti

```bash
./litellm-users.sh list-users
```

#### Info utente

```bash
./litellm-users.sh get-user <user_id>
```

#### Eliminare utente

```bash
./litellm-users.sh delete-user <user_id>
```

#### Aggiornare budget

```bash
./litellm-users.sh update-budget --user-id <user_id> --budget 100
```

---

### Gestione API Keys

#### Generare API key

```bash
# Key standalone con budget
./litellm-users.sh create-key \
  --alias "test-key" \
  --budget 5 \
  --duration monthly

# Key per utente specifico
./litellm-users.sh create-key \
  --user-id user_xxx \
  --alias "laptop-key"

# Key con modelli limitati
./litellm-users.sh create-key \
  --alias "haiku-only" \
  --models '["claude-haiku-4-5"]' \
  --budget 10
```

#### Listare API keys

```bash
./litellm-users.sh list-keys
```

#### Eliminare API key

```bash
./litellm-users.sh delete-key sk-litellm-xxx
```

---

## Associare Modelli agli Utenti

### Limitare modelli per utente

Quando crei un utente, puoi specificare quali modelli può usare:

```bash
# Solo Haiku (economico)
./litellm-users.sh create-user \
  --email intern@example.com \
  --budget 5 \
  --models '["claude-haiku-4-5"]'

# Haiku e Sonnet
./litellm-users.sh create-user \
  --email developer@example.com \
  --budget 50 \
  --models '["claude-haiku-4-5", "claude-sonnet-4-5"]'

# Tutti i modelli
./litellm-users.sh create-user \
  --email senior@example.com \
  --budget 200
```

### Limitare modelli per API key

```bash
# Key per testing (solo Haiku, budget basso)
./litellm-users.sh create-key \
  --alias "test-key" \
  --models '["claude-haiku-4-5"]' \
  --budget 2

# Key di produzione (tutti i modelli)
./litellm-users.sh create-key \
  --alias "prod-key" \
  --budget 100
```

---

## Esempi Pratici

### Scenario 1: Team di sviluppo

```bash
# Lead developer - tutti i modelli, budget alto
./litellm-users.sh create-user \
  --email lead@company.com \
  --budget 200 \
  --duration monthly

# Developer - Haiku e Sonnet, budget medio
./litellm-users.sh create-user \
  --email dev@company.com \
  --budget 50 \
  --duration monthly \
  --models '["claude-haiku-4-5", "claude-sonnet-4-5"]'

# Intern - solo Haiku, budget basso
./litellm-users.sh create-user \
  --email intern@company.com \
  --budget 10 \
  --duration monthly \
  --models '["claude-haiku-4-5"]'
```

### Scenario 2: Chiavi per ambienti diversi

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

## Usando curl direttamente

Se preferisci non usare lo script:

> **⚠️ Importante**: Gli endpoint admin sono bloccati da CloudFront. Usa l'ALB diretto dall'interno della VPC.

### Creare utente

```bash
# Via ALB (dall'interno della VPC) - FUNZIONA
curl -X POST "http://kong-llm-gateway-poc-xxx.us-west-1.elb.amazonaws.com/user/new" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "user@example.com",
    "max_budget": 50,
    "budget_duration": "monthly",
    "models": ["claude-haiku-4-5"]
  }'

# Via CloudFront - BLOCCATO (403 Forbidden)
# curl -X POST "https://d18l8nt8fin3hz.cloudfront.net/user/new" ...
```

### Generare API key

```bash
# Via ALB (dall'interno della VPC)
curl -X POST "http://kong-llm-gateway-poc-xxx.us-west-1.elb.amazonaws.com/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "my-key",
    "max_budget": 10,
    "models": ["claude-haiku-4-5"]
  }'
```

### Listare utenti

```bash
# Via ALB (dall'interno della VPC)
curl -X GET "http://kong-llm-gateway-poc-xxx.us-west-1.elb.amazonaws.com/user/list" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

---

## Configurazione Database (Opzionale)

Per abilitare user management completo, serve PostgreSQL.

### Opzione 1: RDS PostgreSQL

Aggiungi al Terraform:

```hcl
module "litellm_db" {
  source = "../../modules/rds"

  identifier = "litellm-poc"
  engine     = "postgres"
  engine_version = "15"
  instance_class = "db.t4g.micro"  # ~$12/mese

  allocated_storage = 20
  db_name           = "litellm"
  username          = "litellm"

  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.litellm_db.id]
}
```

Poi configura LiteLLM:

```yaml
general_settings:
  database_url: "postgresql://user:pass@host:5432/litellm"
```

### Opzione 2: Aurora Serverless v2

Per costi variabili basati sull'uso (~$0.06/ACU-hour).

### Costi stimati

| Opzione | Costo mensile |
|---------|---------------|
| RDS t4g.micro | ~$12-15 |
| Aurora Serverless v2 | ~$5-20 (variabile) |
| Nessun DB (master key only) | $0 |

---

## Troubleshooting

### "Database not connected"

```
Internal Server Error, Database not connected
```

**Causa**: LiteLLM non ha un database configurato.
**Soluzione**: Usa la master key oppure configura PostgreSQL.

### "Invalid API Key"

```
Authentication Error: Invalid API Key
```

**Causa**: La chiave non esiste o è scaduta.
**Soluzione**: Verifica la chiave con `list-keys` o genera una nuova.

### "Budget exceeded"

```
Budget has been exceeded
```

**Causa**: L'utente/key ha superato il budget.
**Soluzione**: Aumenta il budget con `update-budget`.

---

## Riferimenti

- [LiteLLM Proxy Documentation](https://docs.litellm.ai/docs/simple_proxy)
- [LiteLLM User Management](https://docs.litellm.ai/docs/proxy/users)
- [LiteLLM Virtual Keys](https://docs.litellm.ai/docs/proxy/virtual_keys)
