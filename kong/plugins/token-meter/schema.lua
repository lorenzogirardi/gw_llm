-- token-meter/schema.lua
-- Configuration schema for the Token Meter plugin

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "token-meter",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          -- Default model for cost calculation if not detected
          { default_model = {
              type = "string",
              default = "anthropic.claude-3-sonnet-20240229-v1:0",
              description = "Default model ID for cost calculation if not detected in response.",
          }},

          -- Enable Prometheus metrics
          { prometheus_metrics = {
              type = "boolean",
              default = true,
              description = "Expose token metrics via Prometheus.",
          }},

          -- Enable cost estimation
          { enable_cost_estimation = {
              type = "boolean",
              default = true,
              description = "Calculate and include cost estimates in response headers.",
          }},

          -- Log level for token usage
          { log_level = {
              type = "string",
              default = "info",
              one_of = { "debug", "info", "notice", "warn", "err" },
              description = "Log level for token usage events.",
          }},

          -- Custom pricing overrides (JSON string)
          { custom_pricing = {
              type = "string",
              required = false,
              description = "JSON object with custom pricing per model: {\"model-id\": {\"input\": 0.001, \"output\": 0.002}}",
          }},
        },
      },
    },
  },
}
