# Stargate Sandbox - User Management & Token Quotas

**Environment:** Sandbox (Production-Ready)
**Region:** us-east-1
**Last Updated:** 2025-01-25

---

> **URL Gateway:** Negli esempi, sostituire `gateway.example.com` con l'URL CloudFront effettivo.
> Per sandbox: `https://<cloudfront-distribution-id>.cloudfront.net`

---

## Overview

LiteLLM provides built-in user management with:
- API key generation per user
- Token usage tracking
- Spend limits (budget)
- Rate limiting per user

```
┌─────────────────────────────────────────────────────────────┐
│                    LiteLLM User Hierarchy                   │
│                                                             │
│  ┌─────────────┐                                            │
│  │   Master    │  ← Admin con accesso totale                │
│  │    Key      │    Gestisce utenti e configurazione        │
│  └──────┬──────┘                                            │
│         │                                                   │
│         ├──────────────┬──────────────┬──────────────┐      │
│         ▼              ▼              ▼              ▼      │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐│
│  │  User A   │  │  User B   │  │  User C   │  │  Team X   ││
│  │  Budget:  │  │  Budget:  │  │  Budget:  │  │  Budget:  ││
│  │  $50/mo   │  │  $100/mo  │  │  $20/mo   │  │  $500/mo  ││
│  └───────────┘  └───────────┘  └───────────┘  └───────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## Authentication Headers

### Per Utenti Normali (API Calls)

```bash
# Header richiesto per chiamate /v1/*
Authorization: Bearer sk-user-xxxxx

# Esempio completo
curl https://gateway.example.com/v1/chat/completions \
     -H "Authorization: Bearer sk-user-abc123" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "claude-haiku-4-5",
       "messages": [{"role": "user", "content": "Hello"}]
     }'
```

### Per Amministratori (Management API)

```bash
# Headers richiesti per chiamate /user/*, /key/*, etc.
Authorization: Bearer sk-master-xxxxx    # Master key
X-Admin-Secret: <admin-secret>           # Secret aggiuntivo

# Esempio completo
curl https://gateway.example.com/user/new \
     -H "Authorization: Bearer sk-master-xxxxx" \
     -H "X-Admin-Secret: super-secret-admin-123" \
     -H "Content-Type: application/json" \
     -d '{"user_id": "user@example.com"}'
```

---

## Gestione Utenti

### Creare un Nuovo Utente

> **IMPORTANTE:** La creazione di un utente **DEVE** includere l'associazione con i modelli consentiti.
> Se il campo `models` è vuoto o omesso, l'utente avrà accesso a **tutti** i modelli disponibili.
> Per sicurezza e controllo costi, specificare sempre esplicitamente i modelli permessi.

```bash
# Endpoint: POST /user/new

curl -X POST https://gateway.example.com/user/new \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "mario.rossi@company.com",
       "user_email": "mario.rossi@company.com",
       "user_role": "user",
       "max_budget": 50.0,
       "budget_duration": "monthly",
       "models": ["claude-haiku-4-5", "claude-sonnet-4-5"]
     }'

# Risposta
{
  "user_id": "mario.rossi@company.com",
  "user_email": "mario.rossi@company.com",
  "max_budget": 50.0,
  "spend": 0.0,
  "user_role": "user",
  "models": ["claude-haiku-4-5", "claude-sonnet-4-5"]
}
```

### Parametri Utente

| Campo | Tipo | Obbligatorio | Descrizione | Esempio |
|-------|------|--------------|-------------|---------|
| `user_id` | string | **Si** | ID univoco utente | `"mario.rossi@company.com"` |
| `user_email` | string | No | Email utente | `"mario.rossi@company.com"` |
| `user_role` | string | No | Ruolo: `user`, `admin` | `"user"` |
| `max_budget` | float | **Raccomandato** | Budget massimo in USD | `50.0` |
| `budget_duration` | string | **Raccomandato** | Periodo: `daily`, `weekly`, `monthly` | `"monthly"` |
| `models` | list | **Raccomandato** | Modelli consentiti (vuoto = tutti) | `["claude-haiku-4-5"]` |
| `tpm_limit` | int | No | Tokens per minuto | `100000` |
| `rpm_limit` | int | No | Requests per minuto | `100` |

> **Best Practice:** Specificare sempre `models`, `max_budget` e `budget_duration` per ogni utente.

### Listare Utenti

```bash
curl https://gateway.example.com/user/list \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET"

# Risposta
{
  "users": [
    {
      "user_id": "mario.rossi@company.com",
      "spend": 12.50,
      "max_budget": 50.0,
      "budget_duration": "monthly"
    },
    {
      "user_id": "anna.verdi@company.com",
      "spend": 5.20,
      "max_budget": 100.0,
      "budget_duration": "monthly"
    }
  ]
}
```

### Ottenere Info Utente

```bash
curl "https://gateway.example.com/user/info?user_id=mario.rossi@company.com" \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET"
```

### Aggiornare Utente

```bash
curl -X POST https://gateway.example.com/user/update \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "mario.rossi@company.com",
       "max_budget": 100.0
     }'
```

### Eliminare Utente

```bash
curl -X POST https://gateway.example.com/user/delete \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{"user_ids": ["mario.rossi@company.com"]}'
```

---

## Gestione API Keys

### Generare API Key per Utente

```bash
# Endpoint: POST /key/generate

curl -X POST https://gateway.example.com/key/generate \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "mario.rossi@company.com",
       "key_alias": "mario-laptop",
       "duration": "30d",
       "models": ["claude-haiku-4-5", "claude-sonnet-4-5"],
       "max_budget": 50.0
     }'

# Risposta
{
  "key": "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "key_name": "mario-laptop",
  "expires": "2025-02-25T00:00:00Z",
  "user_id": "mario.rossi@company.com"
}
```

### Parametri API Key

| Campo | Tipo | Descrizione | Esempio |
|-------|------|-------------|---------|
| `user_id` | string | Utente proprietario | `"mario@company.com"` |
| `key_alias` | string | Nome descrittivo | `"mario-laptop"` |
| `duration` | string | Validità: `30d`, `90d`, `1y` | `"30d"` |
| `models` | list | Modelli consentiti | `["claude-haiku-4-5"]` |
| `max_budget` | float | Budget per questa key | `50.0` |
| `max_parallel_requests` | int | Richieste parallele max | `10` |
| `tpm_limit` | int | Tokens per minuto | `50000` |
| `rpm_limit` | int | Requests per minuto | `50` |
| `metadata` | object | Dati custom | `{"department": "IT"}` |

### Listare API Keys

```bash
curl https://gateway.example.com/key/list \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET"

# Risposta
{
  "keys": [
    {
      "token": "sk-...xxxx",
      "key_alias": "mario-laptop",
      "user_id": "mario.rossi@company.com",
      "spend": 12.50,
      "max_budget": 50.0,
      "expires": "2025-02-25T00:00:00Z"
    }
  ]
}
```

### Revocare API Key

```bash
curl -X POST https://gateway.example.com/key/delete \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{"keys": ["sk-xxxxxxxx"]}'
```

---

## Quote e Limiti

### Budget (Spesa in USD)

```bash
# Impostare budget utente: $100/mese
curl -X POST https://gateway.example.com/user/new \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "mario@company.com",
       "max_budget": 100.0,
       "budget_duration": "monthly",
       "models": ["claude-haiku-4-5", "claude-sonnet-4-5"]
     }'
```

**Budget Duration Options:**
- `daily` - Reset ogni giorno
- `weekly` - Reset ogni settimana
- `monthly` - Reset ogni mese
- `yearly` - Reset ogni anno

### Rate Limiting (TPM/RPM)

```bash
# Limitare utente a 50K tokens/min e 50 requests/min
curl -X POST https://gateway.example.com/user/new \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "mario@company.com",
       "models": ["claude-haiku-4-5"],
       "max_budget": 50.0,
       "budget_duration": "monthly",
       "tpm_limit": 50000,
       "rpm_limit": 50
     }'
```

### Limiti per Modello

```bash
# Permettere solo modelli economici
curl -X POST https://gateway.example.com/user/new \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "intern@company.com",
       "models": ["claude-haiku-4-5"],
       "max_budget": 10.0,
       "budget_duration": "monthly"
     }'
```

---

## Associazione Modelli (OBBLIGATORIA)

### Policy di Assegnazione Modelli

Ogni utente **DEVE** avere un'associazione esplicita con i modelli che può utilizzare.
Questa è una best practice di sicurezza e controllo costi.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Modelli Disponibili                          │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │ claude-haiku-4-5 │  │claude-sonnet-4-5 │  │claude-opus-4-5│  │
│  │   $0.80/1M in    │  │   $3.00/1M in    │  │  $15.00/1M in │  │
│  │   $4.00/1M out   │  │  $15.00/1M out   │  │  $75.00/1M out│  │
│  │    ECONOMICO     │  │    BILANCIATO    │  │    PREMIUM    │  │
│  └──────────────────┘  └──────────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Profili Utente Raccomandati

| Profilo | Modelli | Budget | Use Case |
|---------|---------|--------|----------|
| **Intern/Junior** | `["claude-haiku-4-5"]` | $10-20/mo | Task semplici, apprendimento |
| **Developer** | `["claude-haiku-4-5", "claude-sonnet-4-5"]` | $50-100/mo | Sviluppo quotidiano |
| **Senior/Lead** | `["claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-5"]` | $200-500/mo | Task complessi, architettura |
| **CI/CD** | `["claude-haiku-4-5"]` | $30/mo | Code review automatizzate |

### Esempio: Creare Utenti con Profili

```bash
# Junior Developer - solo Haiku
curl -X POST https://gateway.example.com/user/new \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "junior@company.com",
       "models": ["claude-haiku-4-5"],
       "max_budget": 20.0,
       "budget_duration": "monthly"
     }'

# Senior Developer - Haiku + Sonnet + Opus
curl -X POST https://gateway.example.com/user/new \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "senior@company.com",
       "models": ["claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-5"],
       "max_budget": 300.0,
       "budget_duration": "monthly"
     }'
```

### Aggiornare Modelli Utente

```bash
# Aggiungere accesso a Sonnet per un utente esistente
curl -X POST https://gateway.example.com/user/update \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "junior@company.com",
       "models": ["claude-haiku-4-5", "claude-sonnet-4-5"]
     }'
```

### Verifica Modelli Utente

```bash
# Controllare quali modelli può usare un utente
curl "https://gateway.example.com/user/info?user_id=junior@company.com" \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET"

# Risposta
{
  "user_id": "junior@company.com",
  "models": ["claude-haiku-4-5"],
  "max_budget": 20.0,
  "spend": 5.30
}
```

---

## Monitoraggio Utilizzo

### Verificare Spesa Utente

```bash
curl "https://gateway.example.com/user/info?user_id=mario@company.com" \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET"

# Risposta
{
  "user_id": "mario@company.com",
  "spend": 45.30,
  "max_budget": 100.0,
  "budget_duration": "monthly",
  "budget_reset_at": "2025-02-01T00:00:00Z"
}
```

### Report Spesa Globale

```bash
curl https://gateway.example.com/spend/logs \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET"

# Risposta
{
  "spend_logs": [
    {
      "user": "mario@company.com",
      "model": "claude-haiku-4-5",
      "spend": 0.0012,
      "tokens": 1500,
      "timestamp": "2025-01-25T10:30:00Z"
    }
  ]
}
```

### Spesa per Modello

```bash
curl "https://gateway.example.com/spend/tags?start_date=2025-01-01&end_date=2025-01-31" \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET"
```

---

## Configurazione Claude Code per Utenti

### Setup Utente

```bash
# 1. Admin genera API key per l'utente
curl -X POST https://gateway.example.com/key/generate \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "developer@company.com",
       "key_alias": "claude-code-dev",
       "models": ["claude-haiku-4-5", "claude-sonnet-4-5"],
       "max_budget": 100.0
     }'

# Risposta: sk-dev-xxxxxxxx
```

### Configurazione Utente Finale

```bash
# 2. L'utente configura il suo ambiente

# Opzione A: Environment variables
export ANTHROPIC_API_KEY="sk-dev-xxxxxxxx"
export ANTHROPIC_BASE_URL="https://sandbox.cloudfront.net/v1"

# Opzione B: Claude settings file (~/.claude/settings.json)
{
  "apiKey": "sk-dev-xxxxxxxx",
  "apiBaseUrl": "https://sandbox.cloudfront.net/v1"
}
```

### Verifica Configurazione

```bash
# Test rapido
curl https://sandbox.cloudfront.net/v1/models \
     -H "Authorization: Bearer sk-dev-xxxxxxxx"

# Dovrebbe listare i modelli disponibili per l'utente
```

---

## Esempi Scenari

### Scenario 1: Team di Sviluppo

```bash
# Creare utenti team dev con budget condiviso
for user in dev1@company.com dev2@company.com dev3@company.com; do
  curl -X POST https://gateway.example.com/user/new \
       -H "Authorization: Bearer $MASTER_KEY" \
       -H "X-Admin-Secret: $ADMIN_SECRET" \
       -H "Content-Type: application/json" \
       -d "{
         \"user_id\": \"$user\",
         \"max_budget\": 50.0,
         \"budget_duration\": \"monthly\",
         \"models\": [\"claude-haiku-4-5\", \"claude-sonnet-4-5\"]
       }"
done
```

### Scenario 2: Utente con Limiti Stretti

```bash
# Stagista con limiti bassi
curl -X POST https://gateway.example.com/user/new \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "intern@company.com",
       "max_budget": 10.0,
       "budget_duration": "monthly",
       "models": ["claude-haiku-4-5"],
       "tpm_limit": 10000,
       "rpm_limit": 10
     }'
```

### Scenario 3: Power User

```bash
# Senior developer con accesso a tutti i modelli
curl -X POST https://gateway.example.com/user/new \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "senior@company.com",
       "max_budget": 500.0,
       "budget_duration": "monthly",
       "models": ["claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-5"],
       "tpm_limit": 200000,
       "rpm_limit": 200
     }'
```

---

## Script di Amministrazione

### Script: Creare Utente Completo

```bash
#!/bin/bash
# create-user.sh

GATEWAY_URL="https://sandbox.cloudfront.net"
MASTER_KEY="${LITELLM_MASTER_KEY}"
ADMIN_SECRET="${ADMIN_HEADER_SECRET}"

create_user() {
    local email=$1
    local budget=${2:-50}
    local models=${3:-'["claude-haiku-4-5", "claude-sonnet-4-5"]'}

    # Crea utente
    curl -s -X POST "$GATEWAY_URL/user/new" \
         -H "Authorization: Bearer $MASTER_KEY" \
         -H "X-Admin-Secret: $ADMIN_SECRET" \
         -H "Content-Type: application/json" \
         -d "{
           \"user_id\": \"$email\",
           \"user_email\": \"$email\",
           \"max_budget\": $budget,
           \"budget_duration\": \"monthly\",
           \"models\": $models
         }"

    echo ""

    # Genera API key
    curl -s -X POST "$GATEWAY_URL/key/generate" \
         -H "Authorization: Bearer $MASTER_KEY" \
         -H "X-Admin-Secret: $ADMIN_SECRET" \
         -H "Content-Type: application/json" \
         -d "{
           \"user_id\": \"$email\",
           \"key_alias\": \"${email%@*}-default\",
           \"duration\": \"90d\"
         }"

    echo ""
}

# Uso: ./create-user.sh mario@company.com 100
create_user "$1" "$2"
```

### Script: Report Utilizzo

```bash
#!/bin/bash
# usage-report.sh

GATEWAY_URL="https://sandbox.cloudfront.net"
MASTER_KEY="${LITELLM_MASTER_KEY}"
ADMIN_SECRET="${ADMIN_HEADER_SECRET}"

echo "=== User Spend Report ==="
echo ""

curl -s "$GATEWAY_URL/user/list" \
     -H "Authorization: Bearer $MASTER_KEY" \
     -H "X-Admin-Secret: $ADMIN_SECRET" | \
     jq -r '.users[] | "\(.user_id): $\(.spend)/\(.max_budget) (\(.spend/.max_budget*100 | floor)%)"'
```

---

## Errori Comuni

### Budget Exceeded

```json
{
  "error": {
    "message": "Budget exceeded for user mario@company.com",
    "type": "budget_exceeded",
    "code": 429
  }
}
```

**Soluzione:** Aumentare budget o attendere reset periodo.

### Rate Limit Exceeded

```json
{
  "error": {
    "message": "Rate limit exceeded: 50 RPM",
    "type": "rate_limit_exceeded",
    "code": 429
  }
}
```

**Soluzione:** Attendere o aumentare `rpm_limit`.

### Model Not Allowed

```json
{
  "error": {
    "message": "Model claude-opus-4-5 not allowed for user",
    "type": "model_not_allowed",
    "code": 403
  }
}
```

**Soluzione:** Aggiungere modello alla lista `models` dell'utente.

### Invalid API Key

```json
{
  "error": {
    "message": "Invalid API key",
    "type": "invalid_api_key",
    "code": 401
  }
}
```

**Soluzione:** Verificare API key o rigenerarla.

---

## Best Practices

1. **Separare API Keys per ambiente**
   - Una key per laptop, una per CI/CD, una per produzione

2. **Impostare budget conservativi**
   - Iniziare bassi e aumentare se necessario

3. **Usare modelli appropriati**
   - Haiku per task semplici (economico)
   - Sonnet per task complessi
   - Opus solo quando necessario

4. **Monitorare regolarmente**
   - Controllare spend logs settimanalmente
   - Alert su soglie budget

5. **Rotare API keys periodicamente**
   - Ogni 90 giorni è una buona pratica

6. **Revocare keys inutilizzate**
   - Eliminare keys di ex-dipendenti immediatamente
