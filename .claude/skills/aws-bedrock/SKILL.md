---
name: aws-bedrock
description: >-
  AWS Bedrock integration for Kong Gateway. Covers model invocation, IAM/IRSA
  configuration, request signing, and error handling. Triggers on "bedrock",
  "aws", "claude", "titan", "llm", "model invocation", "IRSA", "IAM role".
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# ABOUTME: AWS Bedrock integration skill for Kong Gateway
# ABOUTME: Covers model invocation, IAM, request signing, Terraform

# AWS Bedrock Skill

## Quick Reference

| Component | Details |
|-----------|---------|
| Region | us-east-1, us-west-2 (Bedrock availability) |
| Auth | IAM roles (IRSA for EKS) |
| Models | Claude, Titan, Llama, Mistral |
| API | bedrock-runtime (invoke), bedrock (management) |

---

## Available Models

| Model | Model ID | Use Case |
|-------|----------|----------|
| Claude 3.5 Sonnet | `anthropic.claude-3-5-sonnet-20240620-v1:0` | Best overall |
| Claude 3 Sonnet | `anthropic.claude-3-sonnet-20240229-v1:0` | Balanced |
| Claude 3 Haiku | `anthropic.claude-3-haiku-20240307-v1:0` | Fast, cheap |
| Titan Text | `amazon.titan-text-express-v1` | AWS native |
| Llama 3 70B | `meta.llama3-70b-instruct-v1:0` | Open source |

---

## API Endpoints

```
# Model invocation (runtime)
POST https://bedrock-runtime.{region}.amazonaws.com/model/{model-id}/invoke

# Streaming invocation
POST https://bedrock-runtime.{region}.amazonaws.com/model/{model-id}/invoke-with-response-stream

# List models (management)
GET https://bedrock.{region}.amazonaws.com/foundation-models
```

---

## Request Format (Claude)

```json
{
  "anthropic_version": "bedrock-2023-05-31",
  "max_tokens": 4096,
  "messages": [
    {
      "role": "user",
      "content": "Hello, Claude!"
    }
  ],
  "system": "You are a helpful assistant."
}
```

## Response Format (Claude)

```json
{
  "id": "msg_123",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "Hello! How can I help you today?"
    }
  ],
  "model": "claude-3-sonnet-20240229",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 12,
    "output_tokens": 15
  }
}
```

---

## IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockInvoke",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-*",
        "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-*"
      ]
    }
  ]
}
```

---

## Terraform (IRSA for EKS)

```hcl
# modules/bedrock/main.tf

# IAM Role for Kong pods
resource "aws_iam_role" "kong_bedrock" {
  name = "${var.cluster_name}-kong-bedrock"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account}"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Bedrock policy
resource "aws_iam_role_policy" "bedrock_invoke" {
  name = "bedrock-invoke"
  role = aws_iam_role.kong_bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BedrockInvoke"
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = var.allowed_models
    }]
  })
}

# Output for Helm values
output "role_arn" {
  value = aws_iam_role.kong_bedrock.arn
}
```

### Variables

```hcl
# modules/bedrock/variables.tf

variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider" {
  type = string
}

variable "namespace" {
  type    = string
  default = "kong"
}

variable "service_account" {
  type    = string
  default = "kong"
}

variable "allowed_models" {
  type = list(string)
  default = [
    "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-*"
  ]
}
```

---

## Helm Values (Kong)

```yaml
# infra/helm/kong-values.yaml

deployment:
  serviceAccount:
    create: true
    name: kong
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/eks-kong-bedrock"

env:
  # AWS SDK will use IRSA automatically
  AWS_REGION: us-east-1
  AWS_SDK_LOAD_CONFIG: "true"

# Custom plugins
plugins:
  configMaps:
    - name: kong-plugin-bedrock-proxy
      pluginName: bedrock-proxy
```

---

## Kong Plugin (Bedrock Proxy)

```lua
-- kong/plugins/bedrock-proxy/handler.lua
local http = require "resty.http"
local cjson = require "cjson.safe"
local aws_v4 = require "kong.plugins.bedrock-proxy.aws_v4"

local BedrockProxy = {
  PRIORITY = 900,
  VERSION = "1.0.0",
}

function BedrockProxy:access(conf)
  local body = kong.request.get_body()

  if not body then
    return kong.response.exit(400, { error = "Request body required" })
  end

  -- Build Bedrock request
  local bedrock_body = {
    anthropic_version = "bedrock-2023-05-31",
    max_tokens = conf.max_tokens,
    messages = body.messages,
    system = body.system,
  }

  local endpoint = string.format(
    "https://bedrock-runtime.%s.amazonaws.com/model/%s/invoke",
    conf.region,
    conf.model
  )

  -- Sign request with AWS SigV4
  local signed_headers = aws_v4.sign_request({
    method = "POST",
    host = "bedrock-runtime." .. conf.region .. ".amazonaws.com",
    path = "/model/" .. conf.model .. "/invoke",
    body = cjson.encode(bedrock_body),
    region = conf.region,
    service = "bedrock",
  })

  -- Make request
  local httpc = http.new()
  httpc:set_timeout(conf.timeout)

  local res, err = httpc:request_uri(endpoint, {
    method = "POST",
    body = cjson.encode(bedrock_body),
    headers = signed_headers,
  })

  if not res then
    kong.log.err("Bedrock request failed: ", err)
    return kong.response.exit(502, { error = "Upstream error" })
  end

  -- Return Bedrock response
  return kong.response.exit(res.status, cjson.decode(res.body))
end

return BedrockProxy
```

---

## AWS SigV4 Signing

```lua
-- kong/plugins/bedrock-proxy/aws_v4.lua
local resty_sha256 = require "resty.sha256"
local resty_hmac = require "resty.hmac"
local str = require "resty.string"

local _M = {}

local function get_credentials()
  -- IRSA: AWS SDK handles this via environment
  -- For local dev, use environment variables
  return {
    access_key = os.getenv("AWS_ACCESS_KEY_ID"),
    secret_key = os.getenv("AWS_SECRET_ACCESS_KEY"),
    session_token = os.getenv("AWS_SESSION_TOKEN"),
  }
end

local function sha256(data)
  local sha = resty_sha256:new()
  sha:update(data)
  return str.to_hex(sha:final())
end

local function hmac_sha256(key, data)
  local hmac = resty_hmac:new(key, resty_hmac.ALGOS.SHA256)
  hmac:update(data)
  return hmac:final()
end

function _M.sign_request(opts)
  local creds = get_credentials()
  local datetime = os.date("!%Y%m%dT%H%M%SZ")
  local date = os.date("!%Y%m%d")

  local payload_hash = sha256(opts.body or "")

  local headers = {
    ["Host"] = opts.host,
    ["Content-Type"] = "application/json",
    ["X-Amz-Date"] = datetime,
    ["X-Amz-Content-Sha256"] = payload_hash,
  }

  if creds.session_token then
    headers["X-Amz-Security-Token"] = creds.session_token
  end

  -- Build canonical request and sign
  -- (Simplified - use aws-sdk-lua in production)

  return headers
end

return _M
```

---

## Error Handling

| Error Code | Cause | Handling |
|------------|-------|----------|
| `ValidationException` | Bad request format | Return 400, log details |
| `AccessDeniedException` | IAM permissions | Check IRSA setup |
| `ThrottlingException` | Rate limit hit | Implement backoff |
| `ModelNotReadyException` | Model warming up | Retry with delay |
| `ServiceQuotaExceededException` | Quota exceeded | Alert, increase quota |

```lua
local function handle_bedrock_error(res)
  local body = cjson.decode(res.body)
  local error_type = body.__type or "UnknownError"

  if error_type:match("ThrottlingException") then
    kong.log.warn("Bedrock rate limited")
    return kong.response.exit(429, { error = "Rate limited", retry_after = 5 })
  end

  if error_type:match("AccessDeniedException") then
    kong.log.err("Bedrock access denied - check IAM")
    return kong.response.exit(503, { error = "Service unavailable" })
  end

  kong.log.err("Bedrock error: ", error_type, " - ", body.message)
  return kong.response.exit(502, { error = "Upstream error" })
end
```

---

## Testing

```bash
# Test Bedrock access (CLI)
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":100,"messages":[{"role":"user","content":"Hi"}]}' \
  --content-type application/json \
  output.json

# Test through Kong
curl -X POST http://localhost:8000/v1/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "model": "claude-3-sonnet"
  }'
```

---

## Checklist

Before Bedrock changes:

- [ ] IAM policy grants only needed permissions
- [ ] IRSA configured for EKS pods
- [ ] Model IDs are valid and enabled in Bedrock
- [ ] Rate limiting configured in Kong
- [ ] Error responses don't leak internal details
- [ ] Timeouts set appropriately (Bedrock can be slow)
- [ ] Logging captures request metadata (not content)
- [ ] Cost alerts configured in AWS
