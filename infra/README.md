# LiteLLM Gateway - Local Development

Docker Compose stack per sviluppo locale del gateway LiteLLM.

## Prerequisiti

- Docker e Docker Compose
- AWS credentials con accesso a Bedrock

## Quick Start

```bash
cd infra

# 1. Configura le variabili d'ambiente
cp .env.example .env
vim .env  # Inserisci le tue credenziali AWS

# 2. Avvia lo stack
docker-compose up -d

# 3. Verifica che i servizi siano attivi
docker-compose ps
```

## Servizi

| Servizio | URL | Descrizione |
|----------|-----|-------------|
| LiteLLM | http://localhost:4000 | API Gateway (OpenAI-compatible) |
| Grafana | http://localhost:3000 | Dashboard (admin/admin) |
| Victoria Metrics | http://localhost:8428 | Metrics storage |

## Test

```bash
# Health check
curl http://localhost:4000/health/liveliness

# Chat completion
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-litellm-master-key" \
  -d '{
    "model": "claude-haiku-4-5",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'

# Metrics
curl http://localhost:4000/metrics/
```

## Configurazione

### LiteLLM

Modifica `litellm-config.yaml` per:
- Aggiungere/rimuovere modelli
- Configurare callbacks
- Modificare impostazioni

### Grafana

Le dashboard sono in `grafana/dashboards/`. Per aggiungere nuove dashboard:
1. Crea il JSON in `grafana/dashboards/`
2. Riavvia Grafana: `docker-compose restart grafana`

## Comandi Utili

```bash
# Visualizza log
docker-compose logs -f litellm

# Riavvia un servizio
docker-compose restart litellm

# Stop completo
docker-compose down

# Stop e rimuovi volumi
docker-compose down -v
```

## Troubleshooting

### LiteLLM non parte
- Verifica le credenziali AWS in `.env`
- Controlla i log: `docker-compose logs litellm`

### Metriche non visibili in Grafana
- Verifica che Victoria Metrics stia scraping: `curl http://localhost:8428/targets`
- Controlla che LiteLLM esponga metriche: `curl http://localhost:4000/metrics/`

### Errore Bedrock
- Verifica che il modello sia disponibile nella tua region
- Controlla le permission IAM per `bedrock:InvokeModel`
