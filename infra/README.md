# Stargate LLM Gateway - Local Development

Docker Compose stack for local development of the LiteLLM gateway.

## Prerequisites

- Docker and Docker Compose
- AWS credentials with Bedrock access

## Quick Start

```bash
cd infra

# 1. Configure environment variables
cp .env.example .env
vim .env  # Enter your AWS credentials

# 2. Start the stack
docker-compose up -d

# 3. Verify services are running
docker-compose ps
```

## Services

| Service | URL | Description |
|---------|-----|-------------|
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

## Configuration

### LiteLLM

Edit `litellm-config.yaml` to:
- Add/remove models
- Configure callbacks
- Modify settings

### Grafana

Dashboards are in `grafana/dashboards/`. To add new dashboards:
1. Create the JSON in `grafana/dashboards/`
2. Restart Grafana: `docker-compose restart grafana`

## Useful Commands

```bash
# View logs
docker-compose logs -f litellm

# Restart a service
docker-compose restart litellm

# Stop all services
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

## Troubleshooting

### LiteLLM not starting
- Verify AWS credentials in `.env`
- Check logs: `docker-compose logs litellm`

### Metrics not visible in Grafana
- Verify Victoria Metrics is scraping: `curl http://localhost:8428/targets`
- Check that LiteLLM exposes metrics: `curl http://localhost:4000/metrics/`

### Bedrock error
- Verify the model is available in your region
- Check IAM permissions for `bedrock:InvokeModel`
