-- ecommerce-guardrails/handler.lua
-- Kong plugin to block sensitive patterns in LLM requests
--
-- Features:
-- - Blocks SQL injection attempts
-- - Blocks credit card patterns
-- - Blocks password/secret requests
-- - Blocks exploit/hack attempts
-- - Configurable blocklist patterns
-- - PCI-DSS and GDPR compliance support

local cjson = require "cjson.safe"

local EcommerceGuardrails = {
  PRIORITY = 950,  -- Run early, after auth but before proxy
  VERSION = "1.0.0",
}

-- Default blocked patterns (case-insensitive)
local DEFAULT_PATTERNS = {
  -- SQL injection
  { pattern = "SELECT%s+.-%s+FROM", category = "sql_injection", severity = "critical" },
  { pattern = "INSERT%s+INTO", category = "sql_injection", severity = "critical" },
  { pattern = "UPDATE%s+.-%s+SET", category = "sql_injection", severity = "critical" },
  { pattern = "DELETE%s+FROM", category = "sql_injection", severity = "critical" },
  { pattern = "DROP%s+TABLE", category = "sql_injection", severity = "critical" },
  { pattern = "UNION%s+SELECT", category = "sql_injection", severity = "critical" },
  { pattern = ";%s*%-%-", category = "sql_injection", severity = "high" },

  -- Credit card patterns
  { pattern = "credit%s*card", category = "pci_dss", severity = "high" },
  { pattern = "card%s*number", category = "pci_dss", severity = "high" },
  { pattern = "%d%d%d%d[%s%-]?%d%d%d%d[%s%-]?%d%d%d%d[%s%-]?%d%d%d%d", category = "pci_dss", severity = "critical" },
  { pattern = "CVV", category = "pci_dss", severity = "high" },
  { pattern = "CVC", category = "pci_dss", severity = "high" },
  { pattern = "expir%w*%s*date", category = "pci_dss", severity = "high" },

  -- Passwords and secrets
  { pattern = "password", category = "credentials", severity = "high" },
  { pattern = "passwd", category = "credentials", severity = "high" },
  { pattern = "secret%s*key", category = "credentials", severity = "high" },
  { pattern = "api%s*key", category = "credentials", severity = "medium" },
  { pattern = "access%s*token", category = "credentials", severity = "high" },
  { pattern = "private%s*key", category = "credentials", severity = "critical" },

  -- Exploit attempts
  { pattern = "order%s*hack", category = "exploit", severity = "critical" },
  { pattern = "exploit", category = "exploit", severity = "high" },
  { pattern = "bypass", category = "exploit", severity = "medium" },
  { pattern = "injection", category = "exploit", severity = "high" },
  { pattern = "XSS", category = "exploit", severity = "high" },
  { pattern = "<script", category = "exploit", severity = "critical" },

  -- PII patterns (GDPR)
  { pattern = "social%s*security", category = "pii", severity = "critical" },
  { pattern = "SSN", category = "pii", severity = "critical" },
  { pattern = "passport%s*number", category = "pii", severity = "high" },
  { pattern = "driver%s*license", category = "pii", severity = "high" },
}

-- Check if text matches any blocked pattern
local function check_patterns(text, patterns, conf)
  if not text or text == "" then
    return nil
  end

  local text_lower = string.lower(text)

  for _, p in ipairs(patterns) do
    -- Skip if severity is below threshold
    if conf.min_severity then
      local severity_order = { debug = 0, low = 1, medium = 2, high = 3, critical = 4 }
      if (severity_order[p.severity] or 0) < (severity_order[conf.min_severity] or 0) then
        goto continue
      end
    end

    -- Check pattern
    if string.match(text_lower, string.lower(p.pattern)) then
      return {
        pattern = p.pattern,
        category = p.category,
        severity = p.severity,
      }
    end

    ::continue::
  end

  return nil
end

-- Extract text content from request body
local function extract_text(body)
  local parsed = cjson.decode(body)
  if not parsed then
    return body  -- Return raw body if not JSON
  end

  local texts = {}

  -- Extract from messages array (OpenAI/Claude format)
  if parsed.messages then
    for _, msg in ipairs(parsed.messages) do
      if msg.content then
        if type(msg.content) == "string" then
          table.insert(texts, msg.content)
        elseif type(msg.content) == "table" then
          for _, part in ipairs(msg.content) do
            if part.text then
              table.insert(texts, part.text)
            end
          end
        end
      end
    end
  end

  -- Extract from prompt (legacy format)
  if parsed.prompt then
    table.insert(texts, parsed.prompt)
  end

  -- Extract from system prompt
  if parsed.system then
    table.insert(texts, parsed.system)
  end

  return table.concat(texts, " ")
end

function EcommerceGuardrails:init_worker()
  kong.log.info("Ecommerce Guardrails plugin initialized")
end

function EcommerceGuardrails:access(conf)
  -- Get request body
  local body = kong.request.get_raw_body()
  if not body or body == "" then
    return  -- No body to check
  end

  -- Extract text content
  local text = extract_text(body)

  -- Build patterns list
  local patterns = {}

  -- Add default patterns if enabled
  if conf.use_default_patterns then
    for _, p in ipairs(DEFAULT_PATTERNS) do
      table.insert(patterns, p)
    end
  end

  -- Add custom patterns
  if conf.custom_patterns then
    local custom = cjson.decode(conf.custom_patterns)
    if custom then
      for _, p in ipairs(custom) do
        table.insert(patterns, p)
      end
    end
  end

  -- Check for blocked patterns
  local violation = check_patterns(text, patterns, conf)

  if violation then
    -- Log violation (without the actual content for privacy)
    kong.log.warn(cjson.encode({
      event = "guardrail_violation",
      category = violation.category,
      severity = violation.severity,
      pattern = violation.pattern,
      consumer = kong.client.get_consumer() and kong.client.get_consumer().username or "anonymous",
      route = kong.router.get_route() and kong.router.get_route().name or "unknown",
      timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }))

    -- Block request
    if conf.block_on_violation then
      return kong.response.exit(conf.block_status_code or 400, {
        error = {
          code = "GUARDRAIL_VIOLATION",
          category = violation.category,
          message = conf.block_message or "Request blocked by security policy",
        }
      })
    end

    -- Or just add warning header
    kong.service.request.set_header("X-Guardrail-Warning", violation.category)
  end
end

function EcommerceGuardrails:header_filter(conf)
  -- Add guardrail status header
  kong.response.set_header("X-Guardrails-Enabled", "true")
end

return EcommerceGuardrails
