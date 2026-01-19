# Runbook: High Latency

## Alert: KongHighLatency

**Severity**: Warning (P99 > 5s)

**Description**: Kong LLM Gateway requests are experiencing high latency.

## Quick Actions

1. Check current P95/P99 latency:
   ```promql
   histogram_quantile(0.99, sum(rate(kong_request_latency_ms_bucket[5m])) by (le, service))
   ```

2. Check Bedrock model response times:
   ```promql
   histogram_quantile(0.95, sum(rate(kong_upstream_latency_ms_bucket[5m])) by (le, upstream))
   ```

## Investigation Steps

### 1. Identify Latency Source

Latency breakdown:
- **Kong latency**: Time spent in Kong processing
- **Upstream latency**: Time waiting for Bedrock response

```promql
# Kong processing time
avg(kong_latency_ms) by (service)

# Upstream (Bedrock) time
avg(kong_upstream_target_health_latency_ms) by (upstream)
```

### 2. Check Model-Specific Latency

Different models have different response times:
- **Claude Opus**: Slowest, most capable
- **Claude Sonnet**: Balanced
- **Claude Haiku**: Fastest

```promql
histogram_quantile(0.95, sum(rate(kong_request_latency_ms_bucket{service=~"bedrock-.*"}[5m])) by (le, service))
```

### 3. Check Request Payload Size

Large prompts and responses increase latency:
```bash
# Check average request/response sizes
kubectl logs -n kong -l app.kubernetes.io/name=kong --tail=1000 | \
  jq -r 'select(.request_size != null) | .request_size' | \
  awk '{sum+=$1; count++} END {print "Avg request size:", sum/count}'
```

### 4. Resource Contention

```bash
# Check CPU throttling
kubectl top pods -n kong

# Check HPA status
kubectl get hpa -n kong
```

### 5. Network Issues

```bash
# Check network latency to Bedrock
kubectl exec -n kong -it $(kubectl get pod -n kong -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].metadata.name}') -- \
  curl -w "@/dev/stdin" -o /dev/null -s https://bedrock-runtime.us-east-1.amazonaws.com <<'EOF'
     time_namelookup:  %{time_namelookup}s\n
        time_connect:  %{time_connect}s\n
     time_appconnect:  %{time_appconnect}s\n
    time_pretransfer:  %{time_pretransfer}s\n
       time_redirect:  %{time_redirect}s\n
  time_starttransfer:  %{time_starttransfer}s\n
          time_total:  %{time_total}s\n
EOF
```

## Remediation

### High Bedrock Latency

1. **Route to faster models**: Use Haiku for latency-sensitive requests
2. **Implement request caching**: Cache common prompts
3. **Reduce prompt size**: Optimize system prompts

### High Kong Processing Time

1. **Disable unnecessary plugins**:
   ```yaml
   # Check active plugins
   plugins:
     - name: bedrock-proxy
       enabled: true
     - name: token-meter
       enabled: true
   ```

2. **Scale horizontally**:
   ```bash
   kubectl scale deployment -n kong kong-kong --replicas=5
   ```

3. **Increase resources**:
   ```yaml
   resources:
     requests:
       cpu: 1000m
       memory: 1Gi
     limits:
       cpu: 4000m
       memory: 4Gi
   ```

### Network Optimization

1. Use VPC endpoints for Bedrock (reduces network hops)
2. Ensure Kong pods are in same AZ as Bedrock endpoint
3. Enable HTTP/2 keep-alive connections

## Expected Latencies

| Model | Typical P50 | Typical P95 | SLA |
|-------|-------------|-------------|-----|
| Claude Opus | 5-15s | 20-30s | 60s |
| Claude Sonnet | 2-5s | 8-15s | 30s |
| Claude Haiku | 0.5-2s | 3-5s | 10s |
| Titan Text | 1-3s | 5-8s | 15s |

## Escalation

1. If latency is network-related: **Network team**
2. If latency is Bedrock-related: **AWS Support**
3. If latency is resource-related: **Platform team**

## Related Links

- [Bedrock Latency Optimization](https://docs.aws.amazon.com/bedrock/latest/userguide/optimization.html)
- [Kong Performance Tuning](https://docs.konghq.com/gateway/latest/production/performance/)
