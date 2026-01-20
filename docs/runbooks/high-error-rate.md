# Runbook: High Error Rate

## Alert: LiteLLMHighErrorRate

**Severity**: Warning (>5%) / Critical (>10%)

**Description**: The LiteLLM Gateway is returning an elevated rate of 5xx errors.

## Quick Actions

1. Check LiteLLM service status:
   ```bash
   aws ecs describe-services \
     --cluster kong-llm-gateway-poc \
     --services litellm \
     --region us-west-1
   ```

2. Check recent logs:
   ```bash
   aws logs tail /ecs/litellm --since 10m --region us-west-1 | grep -i error
   ```

3. Check Bedrock service status:
   ```bash
   aws bedrock list-foundation-models --region us-west-1
   ```

## Investigation Steps

### 1. Identify Error Pattern

Check Victoria Metrics for error breakdown:
```promql
sum(rate(litellm_proxy_total_requests_metric_total{status_code=~"5.."}[5m])) by (status_code, model)
```

Common error codes:
- **500**: Internal server error (check LiteLLM logs)
- **502**: Bad gateway (Bedrock unreachable)
- **503**: Service unavailable (ECS task unhealthy)
- **504**: Gateway timeout (Bedrock slow response)

### 2. Check Bedrock Connectivity

```bash
# Test Bedrock API
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-5-haiku-20241022-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}' \
  --region us-west-1 \
  output.json
```

### 3. Check ECS Task Health

```bash
# List running tasks
aws ecs list-tasks \
  --cluster kong-llm-gateway-poc \
  --service-name litellm \
  --region us-west-1

# Describe task
aws ecs describe-tasks \
  --cluster kong-llm-gateway-poc \
  --tasks <TASK_ARN> \
  --region us-west-1
```

## Remediation

### LiteLLM Service Issues

1. Force new deployment:
   ```bash
   aws ecs update-service \
     --cluster kong-llm-gateway-poc \
     --service litellm \
     --force-new-deployment \
     --region us-west-1
   ```

2. Scale up if under load:
   ```bash
   aws ecs update-service \
     --cluster kong-llm-gateway-poc \
     --service litellm \
     --desired-count 2 \
     --region us-west-1
   ```

### Configuration Issues

1. Check LiteLLM config in Terraform:
   ```bash
   cd infra/terraform/environments/poc
   grep -A50 "litellm_config" main.tf
   ```

2. Apply config changes:
   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

## Escalation

1. **Slack**: #platform-alerts
2. **AWS Support**: Open case for Bedrock service issues

## Related Links

- [Grafana Dashboard](https://d18l8nt8fin3hz.cloudfront.net/grafana)
- [AWS Bedrock Status](https://health.aws.amazon.com/)
