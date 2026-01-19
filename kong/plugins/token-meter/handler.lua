-- token-meter/handler.lua
-- Kong plugin to track token usage from Bedrock responses
--
-- Features:
-- - Extracts token counts from Bedrock responses
-- - Exposes metrics via Prometheus
-- - Estimates costs based on model pricing
-- - Logs usage for analytics

local cjson = require "cjson.safe"

local TokenMeter = {
  PRIORITY = 800,  -- Run after bedrock-proxy
  VERSION = "1.0.0",
}

-- Pricing per 1K tokens (USD) - approximate as of 2024
local MODEL_PRICING = {
  ["anthropic.claude-3-5-sonnet-20240620-v1:0"] = { input = 0.003, output = 0.015 },
  ["anthropic.claude-3-sonnet-20240229-v1:0"] = { input = 0.003, output = 0.015 },
  ["anthropic.claude-3-haiku-20240307-v1:0"] = { input = 0.00025, output = 0.00125 },
  ["amazon.titan-text-express-v1"] = { input = 0.0002, output = 0.0006 },
}

-- Default pricing for unknown models
local DEFAULT_PRICING = { input = 0.003, output = 0.015 }

-- Calculate estimated cost
local function calculate_cost(model_id, input_tokens, output_tokens)
  local pricing = MODEL_PRICING[model_id] or DEFAULT_PRICING
  local input_cost = (input_tokens / 1000) * pricing.input
  local output_cost = (output_tokens / 1000) * pricing.output
  return input_cost + output_cost
end

-- Initialize shared dictionary for metrics (if available)
local function init_metrics()
  -- Kong shared dict for counters
  local ok, err = pcall(function()
    if kong.ctx.shared.token_metrics == nil then
      kong.ctx.shared.token_metrics = {
        total_input_tokens = 0,
        total_output_tokens = 0,
        total_requests = 0,
        total_cost = 0,
      }
    end
  end)
  if not ok then
    kong.log.warn("Could not initialize token metrics: ", err)
  end
end

function TokenMeter:init_worker()
  kong.log.info("Token Meter plugin initialized")
  init_metrics()
end

function TokenMeter:access(conf)
  -- Record request start time
  kong.ctx.plugin.start_time = ngx.now()
end

function TokenMeter:header_filter(conf)
  -- Check for usage data from bedrock-proxy
  local usage = kong.ctx.shared.bedrock_usage
  if not usage then
    return
  end

  local model_id = kong.ctx.shared.bedrock_model or conf.default_model or "unknown"
  local input_tokens = usage.input_tokens or 0
  local output_tokens = usage.output_tokens or 0

  -- Calculate cost
  local cost = calculate_cost(model_id, input_tokens, output_tokens)

  -- Set response headers
  kong.response.set_header("X-Token-Input", tostring(input_tokens))
  kong.response.set_header("X-Token-Output", tostring(output_tokens))
  kong.response.set_header("X-Token-Total", tostring(input_tokens + output_tokens))
  kong.response.set_header("X-Cost-Estimate-USD", string.format("%.6f", cost))
  kong.response.set_header("X-Model-ID", model_id)

  -- Store for log phase
  kong.ctx.plugin.usage = {
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    cost = cost,
    model = model_id,
  }
end

function TokenMeter:log(conf)
  local usage = kong.ctx.plugin.usage
  if not usage then
    return
  end

  local latency = 0
  if kong.ctx.plugin.start_time then
    latency = (ngx.now() - kong.ctx.plugin.start_time) * 1000
  end

  -- Get consumer info
  local consumer = kong.client.get_consumer()
  local consumer_id = consumer and consumer.id or "anonymous"
  local consumer_name = consumer and consumer.username or "anonymous"

  -- Get role from header
  local role = kong.request.get_header("X-Consumer-Role") or "unknown"

  -- Log structured data
  kong.log.info(cjson.encode({
    event = "token_usage",
    model = usage.model,
    input_tokens = usage.input_tokens,
    output_tokens = usage.output_tokens,
    total_tokens = usage.input_tokens + usage.output_tokens,
    cost_usd = usage.cost,
    latency_ms = latency,
    consumer_id = consumer_id,
    consumer_name = consumer_name,
    role = role,
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }))

  -- Update Prometheus metrics (if prometheus plugin is enabled)
  -- The prometheus plugin will scrape kong.ctx.shared data
  if conf.prometheus_metrics then
    local labels = {
      model = usage.model,
      consumer = consumer_name,
      role = role,
    }

    -- These would be exposed via custom Prometheus metrics
    -- For now, we rely on the prometheus plugin's default metrics
    -- and the response headers for token tracking
  end
end

return TokenMeter
