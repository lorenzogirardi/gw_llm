# LiteLLM Gateway - API Examples

This document provides curl examples for testing the LiteLLM Gateway.

## Prerequisites

Set your environment variables:
```bash
# Gateway URL
export LITELLM_URL="https://d18l8nt8fin3hz.cloudfront.net"

# Your API Key (get from admin)
export LITELLM_API_KEY="sk-your-api-key"

# Admin only - Master Key
export LITELLM_MASTER_KEY="sk-litellm-master-key"
```

## Basic Chat Completion

### Simple Request

```bash
curl -X POST "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -d '{
    "model": "claude-haiku-4-5",
    "messages": [
      {
        "role": "user",
        "content": "What is the capital of France?"
      }
    ],
    "max_tokens": 100
  }'
```

### With System Prompt

```bash
curl -X POST "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -d '{
    "model": "claude-haiku-4-5",
    "messages": [
      {
        "role": "system",
        "content": "You are a helpful coding assistant."
      },
      {
        "role": "user",
        "content": "Write a Python function to calculate fibonacci numbers"
      }
    ],
    "max_tokens": 1024
  }'
```

### With Temperature Control

```bash
curl -X POST "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -d '{
    "model": "claude-haiku-4-5",
    "messages": [
      {
        "role": "user",
        "content": "Write a creative story about a robot"
      }
    ],
    "max_tokens": 500,
    "temperature": 0.9
  }'
```

## Streaming Responses

```bash
curl -X POST "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -H "Accept: text/event-stream" \
  -d '{
    "model": "claude-haiku-4-5",
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

## List Available Models

```bash
curl "${LITELLM_URL}/v1/models" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}"
```

## Health Check

```bash
# Liveliness check
curl "${LITELLM_URL}/health/liveliness"

# Readiness check
curl "${LITELLM_URL}/health/readiness"

# Full health check
curl "${LITELLM_URL}/health"
```

## Metrics (Prometheus Format)

```bash
curl "${LITELLM_URL}/metrics/"
```

## Admin Operations (Master Key Required)

### Create User

```bash
curl -X POST "${LITELLM_URL}/user/new" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{
    "user_email": "developer@example.com",
    "max_budget": 10.0,
    "budget_duration": "monthly"
  }'
```

### Generate API Key for User

```bash
curl -X POST "${LITELLM_URL}/key/generate" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{
    "user_id": "<USER_ID_FROM_ABOVE>",
    "key_alias": "developer-laptop",
    "duration": "30d"
  }'
```

### List All Keys

```bash
curl "${LITELLM_URL}/key/list" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
```

### Delete Key

```bash
curl -X POST "${LITELLM_URL}/key/delete" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{
    "keys": ["sk-key-to-delete"]
  }'
```

### Get User Info

```bash
curl "${LITELLM_URL}/user/info?user_id=<USER_ID>" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
```

### Update User Budget

```bash
curl -X POST "${LITELLM_URL}/user/update" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{
    "user_id": "<USER_ID>",
    "max_budget": 50.0
  }'
```

## Error Handling Examples

### Unauthorized (401)

```bash
curl -X POST "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer invalid-key" \
  -d '{
    "model": "claude-haiku-4-5",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'

# Expected: 401 Unauthorized
```

### Budget Exceeded (429)

When a user exceeds their budget, they receive:
```json
{
  "error": {
    "message": "Budget exceeded for user",
    "type": "budget_exceeded",
    "code": 429
  }
}
```

### Model Not Found

```bash
curl -X POST "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -d '{
    "model": "non-existent-model",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'

# Expected: Model not found error
```

## Batch Testing Script

```bash
#!/bin/bash
# batch-test.sh - Test multiple requests

MESSAGES=(
  "What is 2+2?"
  "Explain REST APIs in one sentence"
  "Write hello world in Python"
)

for msg in "${MESSAGES[@]}"; do
  echo "Sending: $msg"
  curl -s -X POST "${LITELLM_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${LITELLM_API_KEY}" \
    -d "{
      \"model\": \"claude-haiku-4-5\",
      \"messages\": [{\"role\": \"user\", \"content\": \"$msg\"}],
      \"max_tokens\": 100
    }" | jq -r '.choices[0].message.content' | head -c 100
  echo -e "\n---"
done
```

## Performance Testing

```bash
# Using hey (HTTP load generator)
# Install: brew install hey

hey -n 100 -c 10 -m POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -d '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"Hello"}],"max_tokens":10}' \
  "${LITELLM_URL}/v1/chat/completions"
```

## Troubleshooting

### Enable Verbose Output

```bash
curl -v -X POST "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -d '{
    "model": "claude-haiku-4-5",
    "messages": [{"role": "user", "content": "Debug test"}],
    "max_tokens": 50
  }' 2>&1 | grep -E "(< |> |HTTP)"
```

### Check Response Headers

```bash
curl -I -X POST "${LITELLM_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_API_KEY}" \
  -d '{
    "model": "claude-haiku-4-5",
    "messages": [{"role": "user", "content": "Hi"}],
    "max_tokens": 10
  }'
```

### Test Connectivity

```bash
# Test DNS resolution
nslookup d18l8nt8fin3hz.cloudfront.net

# Test HTTPS connectivity
curl -v --connect-timeout 5 "${LITELLM_URL}/health/liveliness"

# Test with timing
curl -w "@-" -o /dev/null -s "${LITELLM_URL}/health/liveliness" <<'EOF'
     time_namelookup:  %{time_namelookup}s\n
        time_connect:  %{time_connect}s\n
     time_appconnect:  %{time_appconnect}s\n
          time_total:  %{time_total}s\n
EOF
```
