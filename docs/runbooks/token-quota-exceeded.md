# Runbook: Token Quota Exceeded

## Alert: TokenQuotaExceeded / HighLLMCost

**Severity**: Warning

**Description**: A consumer has exceeded their token quota or LLM costs are unusually high.

## Quick Actions

1. Check current token usage:
   ```promql
   sum(kong_llm_tokens_total) by (consumer)
   ```

2. Check cost breakdown:
   ```promql
   sum(kong_llm_cost_total) by (consumer, model)
   ```

## Investigation Steps

### 1. Identify High-Usage Consumers

```promql
# Top consumers by token usage (last 24h)
topk(10, sum(increase(kong_llm_tokens_total[24h])) by (consumer))

# Token usage rate per consumer
sum(rate(kong_llm_tokens_total[1h])) by (consumer)
```

### 2. Analyze Usage Patterns

```bash
# Check request patterns from logs
kubectl logs -n kong -l app.kubernetes.io/name=kong --tail=10000 | \
  jq -r 'select(.consumer != null) | [.consumer, .request_uri, .request_size] | @tsv' | \
  sort | uniq -c | sort -rn | head -20
```

### 3. Check for Anomalies

Look for:
- Sudden spikes in usage
- Requests with very large prompts
- Repeated identical requests (possible bot/loop)
- Unusual access patterns (time of day, frequency)

```promql
# Request rate anomaly
sum(rate(kong_http_requests_total{consumer="$consumer"}[5m])) /
sum(rate(kong_http_requests_total{consumer="$consumer"}[1h] offset 1d))
```

### 4. Review Consumer Configuration

```bash
# Check consumer rate limits
kubectl exec -n kong -it $(kubectl get pod -n kong -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].metadata.name}') -- \
  cat /kong_dbless/kong.yaml | grep -A 20 "username: $CONSUMER"
```

## Remediation

### Immediate Actions

1. **Reduce rate limits temporarily**:
   ```yaml
   # Update kong.yaml
   plugins:
     - name: rate-limiting
       consumer: high-usage-consumer
       config:
         second: 1
         hour: 100
         policy: local
   ```

2. **Switch to cheaper models**:
   ```yaml
   # Route consumer to Haiku only
   plugins:
     - name: request-transformer
       consumer: high-usage-consumer
       config:
         replace:
           body:
             - model:claude-haiku
   ```

3. **Temporarily disable consumer** (emergency):
   ```bash
   # Remove consumer from allowed list
   kubectl edit configmap -n kong kong-declarative-config
   kubectl rollout restart deployment -n kong kong-kong
   ```

### Long-term Solutions

1. **Implement token budgets**:
   ```yaml
   # Add token-based rate limiting
   plugins:
     - name: rate-limiting
       consumer: budget-consumer
       config:
         limit_by: header
         header_name: X-Token-Total
         day: 100000  # 100K tokens/day
   ```

2. **Notify consumer owner**:
   - Send usage report
   - Discuss optimization strategies
   - Review and adjust quotas if needed

3. **Add cost alerts**:
   ```yaml
   # Datadog monitor
   - name: "Consumer Cost Alert"
     query: "sum:kong.llm.cost.total{*} by {consumer} > 50"
     message: "Consumer {{consumer}} has spent ${{value}} today"
   ```

## Cost Optimization Strategies

### For Consumers

1. **Use appropriate models**:
   - Haiku for simple tasks ($0.00025/1K input)
   - Sonnet for complex tasks ($0.003/1K input)
   - Opus only when necessary ($0.015/1K input)

2. **Optimize prompts**:
   - Shorter system prompts
   - Concise instructions
   - Use examples sparingly

3. **Implement caching**:
   - Cache common responses
   - Use semantic caching for similar queries

### For Platform

1. **Set appropriate quotas per role**
2. **Monitor usage trends**
3. **Implement cost allocation/chargeback**
4. **Review and adjust pricing tiers**

## Quota Limits Reference

| Role | Daily Token Limit | Model Access | Cost Cap |
|------|-------------------|--------------|----------|
| Admin | Unlimited | All | None |
| Developer | 100,000 | Sonnet, Haiku | $50/day |
| Analyst | 50,000 | Haiku, Titan | $20/day |
| Ops | 20,000 | Haiku | $10/day |
| Guest | 1,000 | Haiku | $1/day |

## Escalation

1. **Consumer-related issues**: Contact consumer owner
2. **Platform-wide cost issues**: Finance team
3. **Suspected abuse**: Security team

## Related Links

- [Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
- [Token Counting Guide](https://docs.anthropic.com/claude/docs/token-counting)
- [Cost Management Dashboard](http://grafana:3000/d/kong-llm-costs)
