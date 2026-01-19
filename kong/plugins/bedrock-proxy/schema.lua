-- bedrock-proxy/schema.lua
-- Configuration schema for the Bedrock Proxy plugin

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "bedrock-proxy",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          -- Bedrock endpoint (optional, defaults to env var or AWS endpoint)
          { bedrock_endpoint = {
              type = "string",
              required = false,
              description = "Bedrock API endpoint. Defaults to BEDROCK_ENDPOINT env var or AWS endpoint.",
          }},

          -- AWS Region
          { aws_region = {
              type = "string",
              default = "us-east-1",
              description = "AWS region for Bedrock API.",
          }},

          -- Default model if not specified in request
          { default_model = {
              type = "string",
              default = "anthropic.claude-3-sonnet-20240229-v1:0",
              description = "Default Bedrock model ID if not specified in X-Bedrock-Model header.",
          }},

          -- Timeout in milliseconds
          { timeout = {
              type = "integer",
              default = 120000,
              description = "Request timeout in milliseconds.",
          }},

          -- Enable AWS authentication (SigV4)
          { use_aws_auth = {
              type = "boolean",
              default = false,
              description = "Enable AWS SigV4 authentication. Requires AWS credentials.",
          }},

          -- SSL verification
          { ssl_verify = {
              type = "boolean",
              default = true,
              description = "Verify SSL certificates for Bedrock endpoint.",
          }},

          -- Max tokens override
          { max_tokens = {
              type = "integer",
              default = 4096,
              description = "Maximum tokens for response. Can be overridden in request.",
          }},
        },
      },
    },
  },
}
