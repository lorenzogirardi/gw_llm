# Runbook: High Error Rate

## Alert: KongHighErrorRate / KongCriticalErrorRate

**Severity**: Warning (>5%) / Critical (>10%)

**Description**: The Kong LLM Gateway is returning an elevated rate of 5xx errors.

## Quick Actions

1. Check Kong pod status:
   ```bash
   kubectl get pods -n kong -l app.kubernetes.io/name=kong
   ```

2. Check recent logs:
   ```bash
   kubectl logs -n kong -l app.kubernetes.io/name=kong --tail=100 | grep -i error
   ```

3. Check Bedrock service status:
   ```bash
   aws bedrock list-foundation-models --region us-east-1
   ```

## Investigation Steps

### 1. Identify Error Pattern

Check Prometheus for error breakdown:
```promql
sum(rate(kong_http_requests_total{code=~"5.."}[5m])) by (code, service, route)
```

Common error codes:
- **500**: Internal server error (check Kong logs)
- **502**: Bad gateway (Bedrock unreachable)
- **503**: Service unavailable (rate limiting or overload)
- **504**: Gateway timeout (Bedrock slow response)

### 2. Check Bedrock Connectivity

```bash
# Test Bedrock API from Kong pod
kubectl exec -n kong -it $(kubectl get pod -n kong -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].metadata.name}') -- \
  curl -v https://bedrock-runtime.us-east-1.amazonaws.com/
```

### 3. Verify IRSA Configuration

```bash
# Check service account annotation
kubectl get sa -n kong kong -o yaml | grep eks.amazonaws.com

# Verify IAM role trust policy
aws iam get-role --role-name kong-llm-gateway-dev-kong-bedrock
```

### 4. Check Resource Utilization

```bash
# Pod resources
kubectl top pods -n kong

# Node resources
kubectl top nodes
```

### 5. Review Recent Changes

```bash
# Check ArgoCD sync history
argocd app history kong-llm-gateway-dev

# Check ConfigMap changes
kubectl get configmap -n kong kong-declarative-config -o yaml
```

## Remediation

### Bedrock API Issues

1. Check AWS Service Health Dashboard
2. Verify model availability in the region
3. Check IAM permissions for InvokeModel

### Kong Pod Issues

1. Restart affected pods:
   ```bash
   kubectl rollout restart deployment -n kong kong-kong
   ```

2. Scale up if under load:
   ```bash
   kubectl scale deployment -n kong kong-kong --replicas=5
   ```

### Configuration Issues

1. Validate Kong configuration:
   ```bash
   kubectl exec -n kong -it $(kubectl get pod -n kong -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].metadata.name}') -- \
     kong config parse /kong_dbless/kong.yaml
   ```

2. Check for recent config changes and rollback if needed

## Escalation

If the issue persists after following this runbook:

1. **Slack**: #kong-alerts
2. **PagerDuty**: Platform On-Call
3. **AWS Support**: Open case for Bedrock service issues

## Related Links

- [Grafana Dashboard](http://grafana:3000/d/kong-llm-gateway)
- [Kong Error Codes](https://docs.konghq.com/gateway/latest/production/troubleshooting/error-codes/)
- [AWS Bedrock Status](https://health.aws.amazon.com/)
