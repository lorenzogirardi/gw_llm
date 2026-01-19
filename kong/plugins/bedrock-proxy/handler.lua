-- bedrock-proxy/handler.lua
-- Kong plugin to proxy requests to AWS Bedrock with SigV4 signing

local http = require "resty.http"
local cjson = require "cjson.safe"
local ffi = require "ffi"
local C = ffi.C

-- FFI declarations for OpenSSL
ffi.cdef[[
  typedef struct env_md_ctx_st EVP_MD_CTX;
  typedef struct env_md_st EVP_MD;
  typedef struct hmac_ctx_st HMAC_CTX;

  const EVP_MD *EVP_sha256(void);

  unsigned char *HMAC(const EVP_MD *evp_md, const void *key, int key_len,
                      const unsigned char *d, size_t n, unsigned char *md,
                      unsigned int *md_len);

  int EVP_Digest(const void *data, size_t count, unsigned char *md,
                 unsigned int *size, const EVP_MD *type, void *impl);
]]

local BedrockProxy = {
  PRIORITY = 900,
  VERSION = "1.1.0",
}

-- AWS credentials cache
local aws_credentials = nil
local credentials_expiry = 0

-- Get AWS credentials from multiple sources
local function get_ecs_credentials()
  local now = ngx.now()

  if aws_credentials and now < credentials_expiry - 60 then
    return aws_credentials
  end

  -- Try 1: Environment variables (for local testing or explicit config)
  local access_key = os.getenv("AWS_ACCESS_KEY_ID")
  local secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")
  kong.log.info("ENV check - AWS_ACCESS_KEY_ID present: ", access_key ~= nil, ", AWS_SECRET_ACCESS_KEY present: ", secret_key ~= nil)
  if access_key and secret_key then
    kong.log.info("Using AWS credentials from environment variables")
    aws_credentials = {
      access_key = access_key,
      secret_key = secret_key,
      session_token = os.getenv("AWS_SESSION_TOKEN"),
    }
    credentials_expiry = now + 3600
    return aws_credentials
  end

  -- Try 2: ECS Container Credentials (full URI - Fargate)
  local full_uri = os.getenv("AWS_CONTAINER_CREDENTIALS_FULL_URI")
  if full_uri then
    kong.log.info("Trying AWS_CONTAINER_CREDENTIALS_FULL_URI: ", full_uri)
    local httpc = http.new()
    httpc:set_timeout(5000)

    local auth_token = os.getenv("AWS_CONTAINER_AUTHORIZATION_TOKEN")
    local headers = {}
    if auth_token then
      headers["Authorization"] = auth_token
    end

    local res, err = httpc:request_uri(full_uri, {
      method = "GET",
      headers = headers,
    })

    if res and res.status == 200 then
      local creds = cjson.decode(res.body)
      if creds and creds.AccessKeyId then
        aws_credentials = {
          access_key = creds.AccessKeyId,
          secret_key = creds.SecretAccessKey,
          session_token = creds.Token,
        }
        credentials_expiry = now + 3600
        kong.log.info("AWS credentials refreshed from full URI")
        return aws_credentials
      end
    else
      kong.log.warn("Failed to get credentials from full URI: ", err or (res and res.status))
    end
  end

  -- Try 3: ECS Container Credentials (relative URI)
  local relative_uri = os.getenv("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
  if relative_uri then
    kong.log.info("Trying AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    local httpc = http.new()
    httpc:set_timeout(5000)

    local res, err = httpc:request_uri("http://169.254.170.2" .. relative_uri, {
      method = "GET",
    })

    if res and res.status == 200 then
      local creds = cjson.decode(res.body)
      if creds and creds.AccessKeyId then
        aws_credentials = {
          access_key = creds.AccessKeyId,
          secret_key = creds.SecretAccessKey,
          session_token = creds.Token,
        }
        credentials_expiry = now + 3600
        kong.log.info("AWS credentials refreshed from relative URI")
        return aws_credentials
      end
    else
      kong.log.warn("Failed to get credentials from relative URI: ", err or (res and res.status))
    end
  end

  -- Try 4: EC2 Instance Metadata (IMDS v2)
  kong.log.info("Trying EC2 IMDS for credentials")
  local httpc = http.new()
  httpc:set_timeout(2000)

  -- Get token for IMDSv2
  local token_res = httpc:request_uri("http://169.254.169.254/latest/api/token", {
    method = "PUT",
    headers = {
      ["X-aws-ec2-metadata-token-ttl-seconds"] = "21600"
    }
  })

  if token_res and token_res.status == 200 then
    local token = token_res.body

    -- Get IAM role name
    local role_res = httpc:request_uri("http://169.254.169.254/latest/meta-data/iam/security-credentials/", {
      method = "GET",
      headers = {
        ["X-aws-ec2-metadata-token"] = token
      }
    })

    if role_res and role_res.status == 200 then
      local role_name = role_res.body

      -- Get credentials
      local creds_res = httpc:request_uri("http://169.254.169.254/latest/meta-data/iam/security-credentials/" .. role_name, {
        method = "GET",
        headers = {
          ["X-aws-ec2-metadata-token"] = token
        }
      })

      if creds_res and creds_res.status == 200 then
        local creds = cjson.decode(creds_res.body)
        if creds and creds.AccessKeyId then
          aws_credentials = {
            access_key = creds.AccessKeyId,
            secret_key = creds.SecretAccessKey,
            session_token = creds.Token,
          }
          credentials_expiry = now + 3600
          kong.log.info("AWS credentials refreshed from IMDS")
          return aws_credentials
        end
      end
    end
  end

  kong.log.err("Failed to get AWS credentials from any source")
  return nil
end

-- Hex encoding
local function to_hex(s)
  return (s:gsub('.', function(c)
    return string.format('%02x', string.byte(c))
  end))
end

-- SHA256 hash using OpenSSL
local function sha256(data)
  local buf = ffi.new("unsigned char[32]")
  local len = ffi.new("unsigned int[1]")
  C.EVP_Digest(data, #data, buf, len, C.EVP_sha256(), nil)
  return ffi.string(buf, 32)
end

local function sha256_hex(data)
  return to_hex(sha256(data or ""))
end

-- URL encode for SigV4 (RFC 3986)
local function uri_encode(str, encode_slash)
  if not str then return "" end
  local result = str:gsub("([^A-Za-z0-9%-_.~])", function(c)
    if c == "/" and not encode_slash then
      return "/"
    end
    return string.format("%%%02X", string.byte(c))
  end)
  return result
end

-- Encode URI path (encode each segment, preserve slashes)
local function encode_uri_path(path)
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    table.insert(segments, uri_encode(segment, true))
  end
  return "/" .. table.concat(segments, "/")
end

-- HMAC-SHA256 using OpenSSL
local function hmac_sha256(key, data)
  local buf = ffi.new("unsigned char[32]")
  local len = ffi.new("unsigned int[1]")
  C.HMAC(C.EVP_sha256(), key, #key, data, #data, buf, len)
  return ffi.string(buf, 32)
end

-- AWS SigV4 signing
local function sign_request(method, host, uri, headers, body, region, service, creds)
  local amz_date = os.date("!%Y%m%dT%H%M%SZ")
  local date_stamp = os.date("!%Y%m%d")

  headers["host"] = host
  headers["x-amz-date"] = amz_date
  if creds.session_token then
    headers["x-amz-security-token"] = creds.session_token
  end

  -- Build canonical headers (sorted)
  local header_names = {}
  for name, _ in pairs(headers) do
    table.insert(header_names, name:lower())
  end
  table.sort(header_names)

  local canonical_headers = ""
  local signed_headers_list = {}
  for _, name in ipairs(header_names) do
    local value = headers[name]
    if value then
      canonical_headers = canonical_headers .. name .. ":" .. tostring(value):gsub("^%s+", ""):gsub("%s+$", "") .. "\n"
      table.insert(signed_headers_list, name)
    end
  end
  local signed_headers = table.concat(signed_headers_list, ";")

  local payload_hash = sha256_hex(body or "")

  -- URL encode the URI path for canonical request
  local canonical_uri = encode_uri_path(uri)

  local canonical_request = method .. "\n" ..
    canonical_uri .. "\n" ..
    "" .. "\n" ..
    canonical_headers .. "\n" ..
    signed_headers .. "\n" ..
    payload_hash

  local algorithm = "AWS4-HMAC-SHA256"
  local credential_scope = date_stamp .. "/" .. region .. "/" .. service .. "/aws4_request"
  local string_to_sign = algorithm .. "\n" ..
    amz_date .. "\n" ..
    credential_scope .. "\n" ..
    sha256_hex(canonical_request)

  local k_date = hmac_sha256("AWS4" .. creds.secret_key, date_stamp)
  local k_region = hmac_sha256(k_date, region)
  local k_service = hmac_sha256(k_region, service)
  local k_signing = hmac_sha256(k_service, "aws4_request")
  local signature = to_hex(hmac_sha256(k_signing, string_to_sign))

  headers["authorization"] = algorithm .. " " ..
    "Credential=" .. creds.access_key .. "/" .. credential_scope .. ", " ..
    "SignedHeaders=" .. signed_headers .. ", " ..
    "Signature=" .. signature

  return headers
end

-- Transform OpenAI format to Bedrock format
local function transform_request(body)
  local parsed = cjson.decode(body)
  if not parsed then
    return nil, "Invalid JSON body"
  end

  if parsed.anthropic_version then
    return body, nil
  end

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

  return body, nil
end

function BedrockProxy:init_worker()
  kong.log.info("Bedrock Proxy plugin initialized")
end

function BedrockProxy:access(conf)
  local model_id = kong.request.get_header("X-Bedrock-Model") or conf.default_model

  if not model_id then
    return kong.response.exit(400, { error = { code = "MISSING_MODEL", message = "Model ID required" } })
  end

  local body = kong.request.get_raw_body()
  if not body or body == "" then
    return kong.response.exit(400, { error = { code = "MISSING_BODY", message = "Request body required" } })
  end

  local transformed_body, err = transform_request(body)
  if err then
    return kong.response.exit(400, { error = { code = "INVALID_REQUEST", message = err } })
  end

  local creds = get_ecs_credentials()
  if not creds then
    return kong.response.exit(500, { error = { code = "CREDENTIALS_ERROR", message = "Failed to get AWS credentials" } })
  end

  local region = conf.aws_region or "us-west-1"
  local host = "bedrock-runtime." .. region .. ".amazonaws.com"
  local uri = "/model/" .. model_id .. "/invoke"
  local url = "https://" .. host .. uri

  local headers = {
    ["content-type"] = "application/json",
    ["accept"] = "application/json",
  }

  headers = sign_request("POST", host, uri, headers, transformed_body, region, "bedrock", creds)

  kong.log.info("Calling Bedrock: ", url, " model: ", model_id)

  local httpc = http.new()
  httpc:set_timeout(conf.timeout or 120000)

  local res, req_err = httpc:request_uri(url, {
    method = "POST",
    body = transformed_body,
    headers = headers,
    ssl_verify = true,
  })

  if not res then
    kong.log.err("Bedrock request failed: ", req_err)
    return kong.response.exit(502, { error = { code = "UPSTREAM_ERROR", message = "Bedrock request failed: " .. (req_err or "unknown") } })
  end

  local response_body = cjson.decode(res.body)

  if response_body and response_body.usage then
    kong.ctx.shared.bedrock_usage = {
      input_tokens = response_body.usage.input_tokens or 0,
      output_tokens = response_body.usage.output_tokens or 0,
    }
    kong.ctx.shared.bedrock_model = model_id
    kong.response.set_header("X-Bedrock-Input-Tokens", tostring(response_body.usage.input_tokens or 0))
    kong.response.set_header("X-Bedrock-Output-Tokens", tostring(response_body.usage.output_tokens or 0))
  end

  kong.response.set_header("X-Bedrock-Model", model_id)
  return kong.response.exit(res.status, response_body or res.body)
end

function BedrockProxy:header_filter(conf)
  kong.response.set_header("X-Powered-By", "Kong-LLM-Gateway")
end

function BedrockProxy:log(conf)
  local usage = kong.ctx.shared.bedrock_usage
  if usage then
    kong.log.info("Bedrock completed. Model: ", kong.ctx.shared.bedrock_model,
      ", Input: ", usage.input_tokens, ", Output: ", usage.output_tokens)
  end
end

return BedrockProxy
