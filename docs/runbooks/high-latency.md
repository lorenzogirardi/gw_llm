# Runbook: High Latency

## Alert: LiteLLMHighLatency

**Severity**: Warning (P99 > 10s)

**Description**: LiteLLM Gateway requests are experiencing high latency.

## Quick Actions

1. Check current latency in Grafana
2. Check Bedrock model response times:
   ```promql
   histogram_quantile(0.95, sum(rate(litellm_llm_api_latency_metric_bucket[5m])) by (le, model))
   ```

## Investigation Steps

### 1. Check Model-Specific Latency

Different models have different response times:
- **Claude Haiku 4.5**: Fastest (~1-3s)
- **Claude Sonnet 4.5**: Balanced (~3-10s)
- **Claude Opus 4.5**: Slowest (~5-30s)

### 2. Check Token Usage

Large prompts increase latency:
```promql
avg(litellm_total_tokens_metric_total) by (model)
```

### 3. Check ECS Resources

```bash
aws cloudwatch get-metric-statistics \
  --namespace ECS/ContainerInsights \
  --metric-name CpuUtilized \
  --dimensions Name=ClusterName,Value=kong-llm-gateway-poc Name=ServiceName,Value=litellm \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --region us-west-1
```

## Remediation

### High Bedrock Latency

1. Route to faster models (Haiku)
2. Reduce prompt size
3. Set appropriate timeouts

### Scale LiteLLM

```bash
aws ecs update-service \
  --cluster kong-llm-gateway-poc \
  --service litellm \
  --desired-count 2 \
  --region us-west-1
```

## Expected Latencies

| Model | P50 | P95 | Timeout |
|-------|-----|-----|---------|
| Claude Haiku 4.5 | 1-2s | 3-5s | 30s |
| Claude Sonnet 4.5 | 3-5s | 8-15s | 60s |
| Claude Opus 4.5 | 5-15s | 20-40s | 120s |

## Related Links

- [Grafana Dashboard](https://d18l8nt8fin3hz.cloudfront.net/grafana)
- [Bedrock Quotas](https://docs.aws.amazon.com/bedrock/latest/userguide/quotas.html)
