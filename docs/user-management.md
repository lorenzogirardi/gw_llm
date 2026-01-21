# LiteLLM User Management Guide

Questa guida spiega come gestire utenti e API key nel gateway LiteLLM.

## Prerequisiti

### Stato Attuale (POC)

Il POC attualmente usa solo la **master key** senza database. Questo significa:

| Feature | Disponibile | Note |
|---------|-------------|------|
| API Key singola (master) | ✅ | Funziona |
| Creare API keys con budget | ⚠️ | Richiede database |
| Creare utenti con budget | ⚠️ | Richiede database |
| Associare modelli a utenti | ⚠️ | Richiede database |
| Tracking spesa per utente | ⚠️ | Richiede database |

### Abilitare User Management Completo

Per abilitare tutte le funzionalità, serve un database PostgreSQL. Vedi [Configurazione Database](#configurazione-database-opzionale).

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

### Creare utente

```bash
curl -X POST "https://d18l8nt8fin3hz.cloudfront.net/user/new" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "user@example.com",
    "max_budget": 50,
    "budget_duration": "monthly",
    "models": ["claude-haiku-4-5"]
  }'
```

### Generare API key

```bash
curl -X POST "https://d18l8nt8fin3hz.cloudfront.net/key/generate" \
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
curl -X GET "https://d18l8nt8fin3hz.cloudfront.net/user/list" \
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
