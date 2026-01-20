# Runbook: Token Quota Exceeded

## Alert: BudgetExceeded

**Severity**: Warning

**Description**: A user has exceeded their token budget.

## Quick Actions

1. Check current spend:
   ```promql
   sum(litellm_spend_metric_total) by (user)
   ```

2. Check token usage:
   ```promql
   sum(litellm_total_tokens_metric_total) by (user, model)
   ```

## Investigation Steps

### 1. Identify High-Usage Users

```promql
# Top users by spend
topk(10, sum(litellm_spend_metric_total) by (user))

# Top users by tokens
topk(10, sum(litellm_total_tokens_metric_total) by (user))
```

### 2. Check User Budget

```bash
curl "https://d18l8nt8fin3hz.cloudfront.net/user/info?user_id=<USER_ID>" \
  -H "Authorization: Bearer <MASTER_KEY>"
```

### 3. Analyze Usage Patterns

Look for:
- Sudden spikes in usage
- Requests with very large prompts
- Repeated identical requests (possible loop)

## Remediation

### Increase User Budget

```bash
curl -X POST "https://d18l8nt8fin3hz.cloudfront.net/user/update" \
  -H "Authorization: Bearer <MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "<USER_ID>",
    "max_budget": 50.0
  }'
```

### Temporarily Disable User

```bash
curl -X POST "https://d18l8nt8fin3hz.cloudfront.net/user/block" \
  -H "Authorization: Bearer <MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "user_ids": ["<USER_ID>"]
  }'
```

## Cost Optimization

### For Users

1. Use Haiku for simple tasks ($0.25/1M input)
2. Use Sonnet for complex tasks ($3/1M input)
3. Use Opus only when necessary ($15/1M input)
4. Optimize prompt length

### Model Pricing

| Model | Input ($/1M) | Output ($/1M) |
|-------|--------------|---------------|
| Claude Haiku 4.5 | $0.25 | $1.25 |
| Claude Sonnet 4.5 | $3.00 | $15.00 |
| Claude Opus 4.5 | $15.00 | $75.00 |

## Related Links

- [Grafana Dashboard](https://d18l8nt8fin3hz.cloudfront.net/grafana)
- [Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
