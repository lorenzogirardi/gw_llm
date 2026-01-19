-- bedrock-proxy/handler.lua
-- Kong plugin to proxy requests to AWS Bedrock
--
-- Features:
-- - Routes to correct Bedrock model based on headers
-- - AWS SigV4 signing (when using real Bedrock)
-- - Request/response transformation
-- - Token usage extraction from responses

local http = require "resty.http"
local cjson = require "cjson.safe"

local BedrockProxy = {
  PRIORITY = 900,  -- Run after auth, before response plugins
  VERSION = "1.0.0",
}

-- Model ID mapping
local MODEL_PATHS = {
  ["anthropic.claude-3-5-sonnet-20240620-v1:0"] = "/model/anthropic.claude-3-5-sonnet-20240620-v1:0/invoke",
  ["anthropic.claude-3-sonnet-20240229-v1:0"] = "/model/anthropic.claude-3-sonnet-20240229-v1:0/invoke",
  ["anthropic.claude-3-haiku-20240307-v1:0"] = "/model/anthropic.claude-3-haiku-20240307-v1:0/invoke",
  ["amazon.titan-text-express-v1"] = "/model/amazon.titan-text-express-v1/invoke",
}

-- Transform incoming request to Bedrock format
local function transform_request(body, model_id)
  local parsed = cjson.decode(body)
  if not parsed then
    return nil, "Invalid JSON body"
  end

  -- If already in Bedrock format, return as-is
  if parsed.anthropic_version then
    return body, nil
  end

  -- Transform OpenAI-style format to Bedrock Claude format
  if parsed.messages then
    local bedrock_body = {
      anthropic_version = "bedrock-2023-05-31",
      max_tokens = parsed.max_tokens or 4096,
      messages = parsed.messages,
    }

    if parsed.system then
      bedrock_body.system = parsed.system
    end

    if parsed.temperature then
      bedrock_body.temperature = parsed.temperature
    end

    return cjson.encode(bedrock_body), nil
  end

  -- Return original if no transformation needed
  return body, nil
end

-- Extract token usage from Bedrock response
local function extract_usage(response_body)
  local parsed = cjson.decode(response_body)
  if not parsed then
    return nil
  end

  -- Claude format
  if parsed.usage then
    return {
      input_tokens = parsed.usage.input_tokens or 0,
      output_tokens = parsed.usage.output_tokens or 0,
    }
  end

  -- Titan format
  if parsed.inputTextTokenCount then
    local output_tokens = 0
    if parsed.results and parsed.results[1] then
      output_tokens = parsed.results[1].tokenCount or 0
    end
    return {
      input_tokens = parsed.inputTextTokenCount,
      output_tokens = output_tokens,
    }
  end

  return nil
end

function BedrockProxy:init_worker()
  kong.log.info("Bedrock Proxy plugin initialized")
end

function BedrockProxy:access(conf)
  -- Get model ID from header (set by request-transformer plugin)
  local model_id = kong.request.get_header("X-Bedrock-Model")
  if not model_id then
    model_id = conf.default_model
  end

  if not model_id then
    kong.log.err("No model ID specified")
    return kong.response.exit(400, {
      error = {
        code = "MISSING_MODEL",
        message = "X-Bedrock-Model header or default_model config required",
      }
    })
  end

  -- Get request body
  local body = kong.request.get_raw_body()
  if not body or body == "" then
    return kong.response.exit(400, {
      error = {
        code = "MISSING_BODY",
        message = "Request body is required",
      }
    })
  end

  -- Transform request to Bedrock format
  local transformed_body, err = transform_request(body, model_id)
  if err then
    kong.log.err("Request transformation failed: ", err)
    return kong.response.exit(400, {
      error = {
        code = "INVALID_REQUEST",
        message = err,
      }
    })
  end

  -- Build Bedrock endpoint URL
  local model_path = MODEL_PATHS[model_id]
  if not model_path then
    model_path = "/model/" .. model_id .. "/invoke"
  end

  local endpoint = conf.bedrock_endpoint or os.getenv("BEDROCK_ENDPOINT")
  if not endpoint then
    endpoint = "https://bedrock-runtime." .. (conf.aws_region or "us-east-1") .. ".amazonaws.com"
  end

  local full_url = endpoint .. model_path

  kong.log.info("Proxying to Bedrock: ", full_url)

  -- Create HTTP client
  local httpc = http.new()
  httpc:set_timeout(conf.timeout or 120000)

  -- Build headers
  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }

  -- Add AWS SigV4 headers if configured (for real Bedrock)
  -- In local/mock mode, these are not needed
  if conf.use_aws_auth then
    -- TODO: Implement SigV4 signing
    -- For now, pass through AWS credentials from environment
    local aws_access_key = os.getenv("AWS_ACCESS_KEY_ID")
    local aws_secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")
    local aws_session_token = os.getenv("AWS_SESSION_TOKEN")

    if aws_session_token then
      headers["X-Amz-Security-Token"] = aws_session_token
    end
  end

  -- Make request to Bedrock
  local res, err = httpc:request_uri(full_url, {
    method = "POST",
    body = transformed_body,
    headers = headers,
    ssl_verify = conf.ssl_verify or false,
  })

  if not res then
    kong.log.err("Bedrock request failed: ", err)
    return kong.response.exit(502, {
      error = {
        code = "UPSTREAM_ERROR",
        message = "Failed to connect to Bedrock: " .. (err or "unknown error"),
      }
    })
  end

  -- Extract token usage for metrics
  local usage = extract_usage(res.body)
  if usage then
    -- Store for token-meter plugin
    kong.ctx.shared.bedrock_usage = usage
    kong.ctx.shared.bedrock_model = model_id

    -- Add usage headers to response
    kong.response.set_header("X-Bedrock-Input-Tokens", tostring(usage.input_tokens))
    kong.response.set_header("X-Bedrock-Output-Tokens", tostring(usage.output_tokens))
    kong.response.set_header("X-Bedrock-Model", model_id)
  end

  -- Return Bedrock response
  return kong.response.exit(res.status, cjson.decode(res.body) or res.body)
end

function BedrockProxy:header_filter(conf)
  -- Add custom headers
  kong.response.set_header("X-Powered-By", "Kong-LLM-Gateway")
end

function BedrockProxy:log(conf)
  -- Log request details (for debugging)
  local usage = kong.ctx.shared.bedrock_usage
  if usage then
    kong.log.info("Bedrock request completed. ",
      "Model: ", kong.ctx.shared.bedrock_model or "unknown", ", ",
      "Input tokens: ", usage.input_tokens, ", ",
      "Output tokens: ", usage.output_tokens)
  end
end

return BedrockProxy
