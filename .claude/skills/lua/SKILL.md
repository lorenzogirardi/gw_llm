---
name: lua
description: >-
  Lua development for Kong Gateway plugins. Covers Kong PDK, plugin structure,
  schema definitions, request/response handling, and testing with Pongo/Busted.
  Triggers on "lua", "kong plugin", "pdk", "handler.lua", "schema.lua",
  "kong.request", "kong.response", "kong.service".
  PROACTIVE: MUST invoke when writing or editing .lua files.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# ABOUTME: Lua skill for Kong Gateway plugin development
# ABOUTME: Covers Kong PDK, plugin patterns, testing with Pongo and Busted

# Lua / Kong Plugin Skill

## Quick Reference

| Rule | Convention |
|------|------------|
| Plugin structure | handler.lua + schema.lua |
| PDK access | `kong.*` namespace |
| Error handling | Return `nil, err` pattern |
| Testing | Pongo + Busted |
| Linting | Luacheck |

---

## Plugin Structure

```
kong/plugins/my-plugin/
├── handler.lua         # Main plugin logic
├── schema.lua          # Configuration schema
├── daos.lua            # Database entities (optional)
├── migrations/         # DB migrations (optional)
└── spec/
    └── my-plugin_spec.lua  # Tests
```

---

## Handler Template

```lua
-- handler.lua
local MyPlugin = {
  PRIORITY = 1000,  -- Higher = runs earlier
  VERSION = "1.0.0",
}

function MyPlugin:init_worker()
  -- Called once per worker process
end

function MyPlugin:access(conf)
  -- Called for every request
  -- conf contains plugin configuration
  local headers = kong.request.get_headers()

  if not headers["authorization"] then
    return kong.response.exit(401, { message = "Unauthorized" })
  end
end

function MyPlugin:header_filter(conf)
  -- Modify response headers
  kong.response.set_header("X-Plugin-Version", self.VERSION)
end

function MyPlugin:body_filter(conf)
  -- Modify response body (called multiple times for streaming)
end

function MyPlugin:log(conf)
  -- Called after response sent
  kong.log.info("Request completed")
end

return MyPlugin
```

---

## Schema Template

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
          { api_key = { type = "string", required = true, encrypted = true } },
          { timeout = { type = "integer", default = 30000 } },
          { model = {
              type = "string",
              default = "anthropic.claude-3-sonnet-20240229-v1:0",
              one_of = {
                "anthropic.claude-3-sonnet-20240229-v1:0",
                "anthropic.claude-3-haiku-20240307-v1:0",
                "amazon.titan-text-express-v1",
              }
          }},
          { max_tokens = { type = "integer", default = 4096 } },
        },
      },
    },
  },
}
```

---

## Kong PDK Reference

### Request Handling

```lua
-- Get request data
local method = kong.request.get_method()
local path = kong.request.get_path()
local query = kong.request.get_query()
local headers = kong.request.get_headers()
local body = kong.request.get_body()
local raw_body = kong.request.get_raw_body()

-- Modify request (before upstream)
kong.service.request.set_header("X-Custom", "value")
kong.service.request.set_body(new_body)
kong.service.request.set_path("/new-path")
```

### Response Handling

```lua
-- Exit early with response
kong.response.exit(200, { message = "OK" })
kong.response.exit(401, { error = "Unauthorized" })

-- Modify response headers
kong.response.set_header("X-Custom", "value")
kong.response.add_header("X-Multi", "value1")

-- Get response data (in header_filter/body_filter)
local status = kong.response.get_status()
local headers = kong.response.get_headers()
```

### Logging

```lua
kong.log.debug("Debug message")
kong.log.info("Info message")
kong.log.notice("Notice message")
kong.log.warn("Warning message")
kong.log.err("Error message")
kong.log.crit("Critical message")

-- Structured logging
kong.log.info("request_id=", kong.request.get_header("X-Request-ID"))
```

### HTTP Client (for upstream calls)

```lua
local http = require "resty.http"

local function call_bedrock(conf, body)
  local httpc = http.new()
  httpc:set_timeout(conf.timeout)

  local res, err = httpc:request_uri("https://bedrock-runtime.us-east-1.amazonaws.com", {
    method = "POST",
    path = "/model/" .. conf.model .. "/invoke",
    body = body,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "AWS4-HMAC-SHA256 ...",
    },
  })

  if not res then
    return nil, err
  end

  return res.body, nil
end
```

---

## Testing with Pongo

### Setup

```bash
# Install Pongo
git clone https://github.com/Kong/kong-pongo.git ~/.pongo
export PATH="$HOME/.pongo/pongo:$PATH"

# Initialize in plugin directory
cd kong/plugins/my-plugin
pongo init
```

### Test File (Busted)

```lua
-- spec/my-plugin_spec.lua
local helpers = require "spec.helpers"

describe("my-plugin", function()
  local client
  local bp

  lazy_setup(function()
    bp = helpers.get_db_utils(nil, nil, {"my-plugin"})

    local service = bp.services:insert({
      name = "test-service",
      host = "httpbin.org",
      port = 80,
    })

    local route = bp.routes:insert({
      service = service,
      paths = { "/test" },
    })

    bp.plugins:insert({
      name = "my-plugin",
      route = route,
      config = {
        api_key = "test-key",
        timeout = 5000,
      },
    })

    assert(helpers.start_kong({
      plugins = "bundled,my-plugin",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  it("adds custom header", function()
    local res = client:get("/test", {
      headers = { Authorization = "Bearer token" }
    })

    assert.response(res).has.status(200)
    assert.response(res).has.header("X-Plugin-Version")
  end)

  it("rejects unauthorized requests", function()
    local res = client:get("/test")

    assert.response(res).has.status(401)
    local body = assert.response(res).has.jsonbody()
    assert.equal("Unauthorized", body.message)
  end)
end)
```

### Run Tests

```bash
# Run all tests
pongo run

# Run specific test file
pongo run spec/my-plugin_spec.lua

# With verbose output
pongo run -- -v

# Shell into test container
pongo shell
```

---

## Lua Style Guide

### Naming

```lua
-- Local variables: snake_case
local request_body = kong.request.get_body()

-- Constants: SCREAMING_SNAKE_CASE
local MAX_RETRIES = 3
local DEFAULT_TIMEOUT = 30000

-- Functions: snake_case
local function validate_request(headers)
  -- ...
end

-- Module table: PascalCase
local MyPlugin = {}
```

### Error Handling

```lua
-- Return nil, err pattern
local function do_something()
  local result, err = some_operation()
  if not result then
    return nil, "operation failed: " .. (err or "unknown error")
  end
  return result
end

-- Usage
local data, err = do_something()
if not data then
  kong.log.err(err)
  return kong.response.exit(500, { error = err })
end
```

### Tables

```lua
-- Prefer explicit table construction
local config = {
  timeout = 5000,
  retries = 3,
}

-- Iterate with ipairs for arrays
for i, item in ipairs(items) do
  -- ...
end

-- Iterate with pairs for hash tables
for key, value in pairs(config) do
  -- ...
end
```

---

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Global variables | Shared state issues | Always use `local` |
| Blocking I/O | Blocks nginx worker | Use `ngx.timer` or async |
| No error handling | Silent failures | Always check return values |
| String concatenation in loops | Memory churn | Use `table.concat` |
| Deep nesting | Hard to read | Extract functions |

---

## Commands

```bash
# Lint Lua files
luacheck kong/plugins/

# Run tests
pongo run

# Validate plugin structure
deck validate -s kong/kong.yaml

# Reload Kong (dev)
kong reload

# Check Kong logs
tail -f /usr/local/kong/logs/error.log
```

---

## Checklist

Before committing Lua changes:

- [ ] `luacheck` passes
- [ ] Tests pass (`pongo run`)
- [ ] No global variables
- [ ] Error handling for all external calls
- [ ] Logging at appropriate levels
- [ ] Schema validates all config fields
- [ ] Plugin priority set correctly
