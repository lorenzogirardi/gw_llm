-- ecommerce-guardrails/schema.lua
-- Configuration schema for the Ecommerce Guardrails plugin

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "ecommerce-guardrails",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          -- Use built-in default patterns
          { use_default_patterns = {
              type = "boolean",
              default = true,
              description = "Enable default security patterns (SQL injection, PCI-DSS, credentials, exploits).",
          }},

          -- Custom patterns (JSON array)
          { custom_patterns = {
              type = "string",
              required = false,
              description = "JSON array of custom patterns: [{\"pattern\": \"regex\", \"category\": \"name\", \"severity\": \"high\"}]",
          }},

          -- Minimum severity to block
          { min_severity = {
              type = "string",
              default = "medium",
              one_of = { "debug", "low", "medium", "high", "critical" },
              description = "Minimum severity level to trigger blocking.",
          }},

          -- Block on violation
          { block_on_violation = {
              type = "boolean",
              default = true,
              description = "Block request on pattern match. If false, only adds warning header.",
          }},

          -- HTTP status code for blocked requests
          { block_status_code = {
              type = "integer",
              default = 400,
              description = "HTTP status code for blocked requests.",
          }},

          -- Custom block message
          { block_message = {
              type = "string",
              default = "Request blocked by security policy",
              description = "Error message returned when request is blocked.",
          }},

          -- Enable logging of violations
          { log_violations = {
              type = "boolean",
              default = true,
              description = "Log security violations (without sensitive content).",
          }},

          -- Categories to enable
          { enabled_categories = {
              type = "array",
              elements = { type = "string" },
              default = { "sql_injection", "pci_dss", "credentials", "exploit", "pii" },
              description = "List of pattern categories to enable.",
          }},
        },
      },
    },
  },
}
