# Kong LLM Gateway Docker Image
# Includes custom plugins for Bedrock proxy, token metering, and guardrails

FROM kong:3.6

# Switch to root to install plugins
USER root

# Create plugin directories
RUN mkdir -p /usr/local/share/lua/5.1/kong/plugins/bedrock-proxy \
             /usr/local/share/lua/5.1/kong/plugins/token-meter \
             /usr/local/share/lua/5.1/kong/plugins/ecommerce-guardrails

# Copy custom plugins
COPY plugins/bedrock-proxy/handler.lua /usr/local/share/lua/5.1/kong/plugins/bedrock-proxy/
COPY plugins/bedrock-proxy/schema.lua /usr/local/share/lua/5.1/kong/plugins/bedrock-proxy/

COPY plugins/token-meter/handler.lua /usr/local/share/lua/5.1/kong/plugins/token-meter/
COPY plugins/token-meter/schema.lua /usr/local/share/lua/5.1/kong/plugins/token-meter/

COPY plugins/ecommerce-guardrails/handler.lua /usr/local/share/lua/5.1/kong/plugins/ecommerce-guardrails/
COPY plugins/ecommerce-guardrails/schema.lua /usr/local/share/lua/5.1/kong/plugins/ecommerce-guardrails/

# Copy Kong declarative config if present
COPY config/kong.yaml /kong/kong.yaml

# Set ownership
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/ && \
    chown -R kong:kong /kong/

# Switch back to kong user
USER kong

# Expose ports
EXPOSE 8000 8001 8100

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8100/status || exit 1
