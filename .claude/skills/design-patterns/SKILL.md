---
name: design-patterns
description: >-
  Architectural patterns for TypeScript/Node.js ecommerce project. Covers
  dependency injection, error handling, configuration, testing patterns.
  Triggers on "dependency injection", "DI pattern", "error handling",
  "architectural pattern", "design pattern", "testing pattern", "anti-pattern".
allowed-tools: Read
---

# ABOUTME: Architectural patterns skill for Stargate LLM Gateway
# ABOUTME: Covers design patterns, error handling, testing, and common anti-patterns

# Design Patterns (Stargate LLM Gateway)

Architectural patterns for the LLM Gateway and AWS Bedrock integration.

## Quick Reference

| Pattern | Kong Plugin | Infrastructure |
|---------|-------------|----------------|
| Config | schema.lua + conf | Helm values + env |
| Errors | kong.response.exit | Structured JSON |
| Logging | kong.log.* | CloudWatch |
| Auth | Pre-function phase | IRSA (EKS) |
| Testing | Pongo + Busted | Terraform test |

---

## 1. Plugin Architecture

### Single Responsibility

Each plugin should do ONE thing well:

```
kong/plugins/
├── bedrock-proxy/      # Route to Bedrock
├── api-key-auth/       # Authenticate requests
├── rate-limiter/       # Rate limiting
├── request-logger/     # Logging
└── response-transform/ # Transform responses
```

### Phase Selection

| Phase | Use Case | Example |
|-------|----------|---------|
| `init_worker` | One-time setup | Initialize cache |
| `certificate` | TLS handling | Custom certificates |
| `rewrite` | Early request mod | Path rewriting |
| `access` | Auth & routing | API key validation |
| `header_filter` | Response headers | Add CORS headers |
| `body_filter` | Response body | Transform JSON |
| `log` | After response | Send to analytics |

```lua
local MyPlugin = {
  PRIORITY = 1000,  -- Higher = earlier
  VERSION = "1.0.0",
}

-- Choose the RIGHT phase
function MyPlugin:access(conf)
  -- Auth and main logic here
end

function MyPlugin:log(conf)
  -- Non-blocking logging here
end
```

---

## 2. Configuration Patterns

### Schema Design

```lua
-- schema.lua
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "my-plugin",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          -- Required fields
          { endpoint = { type = "string", required = true } },

          -- With defaults
          { timeout = { type = "integer", default = 30000 } },

          -- Encrypted (secrets)
          { api_key = { type = "string", encrypted = true } },

          -- Enum validation
          { log_level = {
              type = "string",
              default = "info",
              one_of = { "debug", "info", "warn", "error" }
          }},

          -- Nested config
          { retry = {
              type = "record",
              fields = {
                { count = { type = "integer", default = 3 } },
                { delay = { type = "integer", default = 1000 } },
              },
          }},
        },
      },
    },
  },
}
```

### Environment-Based Config

```yaml
# kong.yaml (DB-less)
plugins:
  - name: bedrock-proxy
    config:
      region: ${BEDROCK_REGION:-us-east-1}
      model: ${BEDROCK_MODEL:-anthropic.claude-3-sonnet-20240229-v1:0}
      timeout: ${BEDROCK_TIMEOUT:-60000}
```

---

## 3. Error Handling Patterns

### Structured Errors

```lua
-- Define error types
local ERRORS = {
  UNAUTHORIZED = { status = 401, code = "UNAUTHORIZED", message = "Missing or invalid API key" },
  FORBIDDEN = { status = 403, code = "FORBIDDEN", message = "Access denied" },
  RATE_LIMITED = { status = 429, code = "RATE_LIMITED", message = "Too many requests" },
  BAD_REQUEST = { status = 400, code = "BAD_REQUEST" },
  UPSTREAM_ERROR = { status = 502, code = "UPSTREAM_ERROR", message = "Upstream service unavailable" },
  INTERNAL_ERROR = { status = 500, code = "INTERNAL_ERROR", message = "Internal server error" },
}

local function exit_error(err_type, details)
  local err = ERRORS[err_type]
  local body = {
    error = {
      code = err.code,
      message = details or err.message,
    }
  }
  return kong.response.exit(err.status, body)
end

-- Usage
function MyPlugin:access(conf)
  local api_key = kong.request.get_header("X-API-Key")
  if not api_key then
    return exit_error("UNAUTHORIZED")
  end

  local valid, err = validate_key(api_key)
  if not valid then
    kong.log.warn("Invalid API key: ", err)
    return exit_error("FORBIDDEN", "Invalid API key")
  end
end
```

### Bedrock Error Mapping

```lua
local BEDROCK_ERRORS = {
  ValidationException = { status = 400, code = "INVALID_REQUEST" },
  AccessDeniedException = { status = 503, code = "SERVICE_UNAVAILABLE" },
  ThrottlingException = { status = 429, code = "RATE_LIMITED" },
  ModelNotReadyException = { status = 503, code = "MODEL_UNAVAILABLE" },
  ServiceQuotaExceededException = { status = 503, code = "QUOTA_EXCEEDED" },
}

local function handle_bedrock_error(response)
  local body = cjson.decode(response.body)
  local error_type = body.__type or "UnknownError"

  for pattern, mapping in pairs(BEDROCK_ERRORS) do
    if error_type:match(pattern) then
      return kong.response.exit(mapping.status, {
        error = { code = mapping.code, message = body.message }
      })
    end
  end

  -- Unknown error - log and return generic
  kong.log.err("Unknown Bedrock error: ", error_type)
  return exit_error("UPSTREAM_ERROR")
end
```

---

## 4. Retry Pattern

```lua
local function with_retry(fn, max_retries, delay_ms)
  local retries = 0
  local last_error

  while retries < max_retries do
    local result, err = fn()
    if result then
      return result
    end

    last_error = err
    retries = retries + 1

    if retries < max_retries then
      kong.log.info("Retry ", retries, "/", max_retries, " after error: ", err)
      ngx.sleep(delay_ms / 1000)
    end
  end

  return nil, last_error
end

-- Usage
local response, err = with_retry(function()
  return call_bedrock(conf, body)
end, conf.retry.count, conf.retry.delay)
```

---

## 5. Caching Pattern

```lua
local kong_cache = kong.cache

local function get_cached_response(cache_key, ttl, fetch_fn)
  local cached, err = kong_cache:get(cache_key, { ttl = ttl }, fetch_fn)
  if err then
    kong.log.err("Cache error: ", err)
    return fetch_fn()  -- Fallback to direct fetch
  end
  return cached
end

-- Usage (cache Bedrock responses for identical prompts)
function MyPlugin:access(conf)
  local body = kong.request.get_body()
  local cache_key = "bedrock:" .. ngx.md5(cjson.encode(body))

  local response = get_cached_response(cache_key, conf.cache_ttl, function()
    return call_bedrock(conf, body)
  end)

  return kong.response.exit(200, response)
end
```

---

## 6. Rate Limiting Pattern

```lua
local redis = require "resty.redis"

local function check_rate_limit(consumer_id, limit, window)
  local red = redis:new()
  red:connect(os.getenv("REDIS_HOST"), 6379)

  local key = "ratelimit:" .. consumer_id
  local current = red:incr(key)

  if current == 1 then
    red:expire(key, window)
  end

  red:close()

  if current > limit then
    kong.response.set_header("X-RateLimit-Limit", limit)
    kong.response.set_header("X-RateLimit-Remaining", 0)
    kong.response.set_header("Retry-After", window)
    return false
  end

  kong.response.set_header("X-RateLimit-Limit", limit)
  kong.response.set_header("X-RateLimit-Remaining", limit - current)
  return true
end
```

---

## 7. Testing Patterns

### Unit Test (Busted)

```lua
-- spec/my-plugin_spec.lua
describe("my-plugin", function()
  describe("schema", function()
    it("validates required fields", function()
      local schema = require "kong.plugins.my-plugin.schema"
      local ok, err = schema:validate({ endpoint = nil })
      assert.is_nil(ok)
      assert.matches("endpoint", err.endpoint)
    end)
  end)

  describe("handler", function()
    local handler

    before_each(function()
      handler = require "kong.plugins.my-plugin.handler"
    end)

    it("has correct priority", function()
      assert.equal(1000, handler.PRIORITY)
    end)
  end)
end)
```

### Integration Test (Pongo)

```lua
-- spec/integration_spec.lua
local helpers = require "spec.helpers"

describe("bedrock-proxy integration", function()
  local client
  local mock_server

  lazy_setup(function()
    -- Start mock Bedrock server
    mock_server = helpers.mock_upstream(8888)

    local bp = helpers.get_db_utils(nil, nil, {"bedrock-proxy"})

    local service = bp.services:insert({
      name = "bedrock-service",
      host = "localhost",
      port = 8888,
    })

    local route = bp.routes:insert({
      service = service,
      paths = { "/v1/chat" },
    })

    bp.plugins:insert({
      name = "bedrock-proxy",
      route = route,
      config = {
        region = "us-east-1",
        model = "anthropic.claude-3-sonnet-20240229-v1:0",
      },
    })

    assert(helpers.start_kong({ plugins = "bundled,bedrock-proxy" }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    mock_server:stop()
  end)

  it("proxies to Bedrock", function()
    client = helpers.proxy_client()

    local res = client:post("/v1/chat", {
      headers = { ["Content-Type"] = "application/json" },
      body = '{"messages":[{"role":"user","content":"Hi"}]}',
    })

    assert.response(res).has.status(200)
    client:close()
  end)
end)
```

---

## 8. Anti-Patterns

### Lua/Kong

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Global variables | Shared state bugs | Always use `local` |
| Blocking I/O | Blocks nginx worker | Use cosockets/timers |
| No error handling | Silent failures | Check all return values |
| Hardcoded config | No flexibility | Use schema.lua |
| Logging secrets | Security risk | Redact sensitive data |

### Bedrock Integration

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Hardcoded credentials | Security risk | Use IRSA |
| No timeouts | Hung requests | Set explicit timeouts |
| Sync streaming | Memory bloat | Use body_filter chunked |
| No rate limits | Cost explosion | Implement rate limiting |
| Logging prompts | Privacy/cost | Log metadata only |

---

## 9. Naming Conventions

### Files

```
kong/plugins/
├── bedrock-proxy/
│   ├── handler.lua      # Main logic
│   ├── schema.lua       # Config schema
│   ├── aws_v4.lua       # AWS signing module
│   └── spec/
│       ├── handler_spec.lua
│       └── integration_spec.lua
```

### Variables

```lua
-- Constants: SCREAMING_SNAKE_CASE
local MAX_RETRIES = 3
local DEFAULT_TIMEOUT = 30000

-- Local variables: snake_case
local request_body = kong.request.get_body()

-- Functions: snake_case
local function validate_request(headers)
end

-- Module table: PascalCase
local BedrockProxy = {}
```

---

## Resources

- [Kong Plugin Development Guide](https://docs.konghq.com/gateway/latest/plugin-development/)
- [Kong PDK Reference](https://docs.konghq.com/gateway/latest/pdk/)
- [AWS Bedrock API Reference](https://docs.aws.amazon.com/bedrock/latest/APIReference/)
