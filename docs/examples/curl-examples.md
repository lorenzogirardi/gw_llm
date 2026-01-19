# Kong LLM Gateway - API Examples

This document provides curl examples for testing the Kong LLM Gateway.

## Prerequisites

Set your environment variables:
```bash
# Local development
export KONG_URL="http://localhost:8000"

# EKS deployment
export KONG_URL="https://your-nlb-endpoint.amazonaws.com"

# API Keys (from kong.yaml)
export ADMIN_KEY="admin-key-super-secret"
export DEVELOPER_KEY="developer-key-12345"
export ANALYST_KEY="analyst-key-67890"
export OPS_KEY="ops-key-ecommerce"
export GUEST_KEY="guest-key-limited"
```

## Basic Chat Completion

### Developer Role (Claude Sonnet)

```bash
curl -X POST "${KONG_URL}/v1/chat/developer" \
  -H "Content-Type: application/json" \
  -H "apikey: ${DEVELOPER_KEY}" \
  -d '{
    "model": "claude-sonnet",
    "messages": [
      {
        "role": "user",
        "content": "Write a Python function to calculate fibonacci numbers"
      }
    ],
    "max_tokens": 1024
  }'
```

### Analyst Role (Claude Haiku)

```bash
curl -X POST "${KONG_URL}/v1/chat/analyst" \
  -H "Content-Type: application/json" \
  -H "apikey: ${ANALYST_KEY}" \
  -d '{
    "model": "claude-haiku",
    "messages": [
      {
        "role": "user",
        "content": "Analyze this sales data: Q1: $1M, Q2: $1.2M, Q3: $0.9M, Q4: $1.5M"
      }
    ],
    "max_tokens": 512
  }'
```

### Ecommerce Ops Role

```bash
curl -X POST "${KONG_URL}/v1/chat/ops" \
  -H "Content-Type: application/json" \
  -H "apikey: ${OPS_KEY}" \
  -d '{
    "model": "claude-haiku",
    "messages": [
      {
        "role": "system",
        "content": "You are an ecommerce assistant helping with product descriptions."
      },
      {
        "role": "user",
        "content": "Write a product description for a wireless bluetooth headphone"
      }
    ],
    "max_tokens": 256
  }'
```

### Guest Role (Limited)

```bash
curl -X POST "${KONG_URL}/v1/chat/guest" \
  -H "Content-Type: application/json" \
  -H "apikey: ${GUEST_KEY}" \
  -d '{
    "model": "claude-haiku",
    "messages": [
      {
        "role": "user",
        "content": "What is the capital of France?"
      }
    ],
    "max_tokens": 100
  }'
```

## Admin Operations

### Full Model Access (Claude Opus)

```bash
curl -X POST "${KONG_URL}/v1/chat/admin" \
  -H "Content-Type: application/json" \
  -H "apikey: ${ADMIN_KEY}" \
  -d '{
    "model": "claude-opus",
    "messages": [
      {
        "role": "system",
        "content": "You are a senior software architect."
      },
      {
        "role": "user",
        "content": "Design a microservices architecture for an ecommerce platform"
      }
    ],
    "max_tokens": 4096,
    "temperature": 0.7
  }'
```

## Streaming Responses

```bash
curl -X POST "${KONG_URL}/v1/chat/developer" \
  -H "Content-Type: application/json" \
  -H "apikey: ${DEVELOPER_KEY}" \
  -H "Accept: text/event-stream" \
  -d '{
    "model": "claude-sonnet",
    "messages": [
      {
        "role": "user",
        "content": "Explain async/await in JavaScript"
      }
    ],
    "max_tokens": 1024,
    "stream": true
  }'
```

## Token Usage Information

Response headers include token usage:
```bash
curl -v -X POST "${KONG_URL}/v1/chat/developer" \
  -H "Content-Type: application/json" \
  -H "apikey: ${DEVELOPER_KEY}" \
  -d '{
    "model": "claude-haiku",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }' 2>&1 | grep -i "x-"

# Expected headers:
# X-Token-Input: 5
# X-Token-Output: 12
# X-Token-Total: 17
# X-Token-Cost-USD: 0.000017
# X-Model-Used: anthropic.claude-3-haiku-20240307-v1:0
```

## Error Handling Examples

### Rate Limit Exceeded (429)

```bash
# Send many requests quickly
for i in {1..20}; do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST "${KONG_URL}/v1/chat/guest" \
    -H "Content-Type: application/json" \
    -H "apikey: ${GUEST_KEY}" \
    -d '{"model": "claude-haiku", "messages": [{"role": "user", "content": "Hi"}], "max_tokens": 10}'
done

# Expected: 429 Too Many Requests after limit reached
```

### Guardrail Block (403)

```bash
# Attempt to send sensitive data (will be blocked)
curl -X POST "${KONG_URL}/v1/chat/developer" \
  -H "Content-Type: application/json" \
  -H "apikey: ${DEVELOPER_KEY}" \
  -d '{
    "model": "claude-sonnet",
    "messages": [
      {
        "role": "user",
        "content": "My credit card number is 4111-1111-1111-1111"
      }
    ],
    "max_tokens": 100
  }'

# Expected: 403 Forbidden with guardrail message
```

### Unauthorized (401)

```bash
curl -X POST "${KONG_URL}/v1/chat/developer" \
  -H "Content-Type: application/json" \
  -H "apikey: invalid-key" \
  -d '{
    "model": "claude-sonnet",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'

# Expected: 401 Unauthorized
```

### Model Not Allowed (403)

```bash
# Guest trying to use Opus (not allowed)
curl -X POST "${KONG_URL}/v1/chat/guest" \
  -H "Content-Type: application/json" \
  -H "apikey: ${GUEST_KEY}" \
  -d '{
    "model": "claude-opus",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'

# Expected: 403 Forbidden - model not available for role
```

## Health Check

```bash
# Kong status
curl "${KONG_URL}/status"

# Kong readiness
curl "${KONG_URL}/status/ready"

# Metrics (Prometheus format)
curl "${KONG_URL}:8100/metrics"
```

## Batch Requests Script

```bash
#!/bin/bash
# batch-test.sh - Test multiple requests

MESSAGES=(
  "What is 2+2?"
  "Explain REST APIs"
  "Write a hello world in Python"
)

for msg in "${MESSAGES[@]}"; do
  echo "Sending: $msg"
  curl -s -X POST "${KONG_URL}/v1/chat/developer" \
    -H "Content-Type: application/json" \
    -H "apikey: ${DEVELOPER_KEY}" \
    -d "{
      \"model\": \"claude-haiku\",
      \"messages\": [{\"role\": \"user\", \"content\": \"$msg\"}],
      \"max_tokens\": 100
    }" | jq -r '.choices[0].message.content' | head -c 100
  echo -e "\n---"
done
```

## Performance Testing

```bash
# Using hey (HTTP load generator)
hey -n 100 -c 10 -m POST \
  -H "Content-Type: application/json" \
  -H "apikey: ${DEVELOPER_KEY}" \
  -d '{"model":"claude-haiku","messages":[{"role":"user","content":"Hello"}],"max_tokens":10}' \
  "${KONG_URL}/v1/chat/developer"
```

## Troubleshooting

### Enable Debug Headers

```bash
curl -v -X POST "${KONG_URL}/v1/chat/developer" \
  -H "Content-Type: application/json" \
  -H "apikey: ${DEVELOPER_KEY}" \
  -H "X-Debug: true" \
  -d '{
    "model": "claude-haiku",
    "messages": [{"role": "user", "content": "Debug test"}],
    "max_tokens": 50
  }' 2>&1 | grep -E "(< |> |X-)"
```

### Check Consumer Identity

```bash
curl -I "${KONG_URL}/v1/chat/developer" \
  -H "apikey: ${DEVELOPER_KEY}" 2>&1 | grep -i "x-consumer"

# Expected: X-Consumer-Username: developer-team
```
