# Kong LLM Gateway - Makefile
# Multi-environment automation for local development and EKS deployment
#
# Usage:
#   make local/up      - Start local environment
#   make local/down    - Stop local environment
#   make eks/plan      - Terraform plan for EKS
#   make eks/apply     - Terraform apply for EKS

.PHONY: help local/up local/down local/logs local/test local/shell \
        eks/plan eks/apply eks/deploy eks/status \
        validate test security-scan clean

# Default target
help:
	@echo "Kong LLM Gateway - Available Commands"
	@echo ""
	@echo "LOCAL DEVELOPMENT:"
	@echo "  make local/up        Start Docker Compose environment"
	@echo "  make local/down      Stop Docker Compose environment"
	@echo "  make local/logs      View Kong logs"
	@echo "  make local/shell     Shell into Kong container"
	@echo "  make local/test      Run plugin tests (Pongo)"
	@echo "  make local/status    Check services status"
	@echo ""
	@echo "EKS DEPLOYMENT:"
	@echo "  make eks/init        Initialize Terraform"
	@echo "  make eks/plan        Terraform plan"
	@echo "  make eks/apply       Terraform apply"
	@echo "  make eks/deploy      Deploy Kong via Helm"
	@echo "  make eks/status      Check EKS deployment"
	@echo ""
	@echo "VALIDATION:"
	@echo "  make validate        Validate Kong config + Lua lint"
	@echo "  make test            Run all tests"
	@echo "  make security-scan   Run Trivy security scan"
	@echo ""
	@echo "UTILITIES:"
	@echo "  make clean           Clean up local environment"
	@echo "  make setup-plugins   Configure Kong plugins via Admin API"

# =============================================================================
# Variables
# =============================================================================
DOCKER_COMPOSE := docker-compose
KONG_ADMIN_URL := http://localhost:8001
KONG_PROXY_URL := http://localhost:8000
TERRAFORM_DIR := infra/terraform/environments/dev
HELM_RELEASE := kong
HELM_NAMESPACE := kong

# =============================================================================
# LOCAL DEVELOPMENT
# =============================================================================

local/up:
	@echo "Starting local environment..."
	$(DOCKER_COMPOSE) up -d
	@echo "Waiting for Kong to be ready..."
	@sleep 10
	@$(MAKE) local/status

local/down:
	@echo "Stopping local environment..."
	$(DOCKER_COMPOSE) down

local/restart:
	@echo "Restarting Kong..."
	$(DOCKER_COMPOSE) restart kong

local/logs:
	$(DOCKER_COMPOSE) logs -f kong

local/logs-all:
	$(DOCKER_COMPOSE) logs -f

local/shell:
	$(DOCKER_COMPOSE) exec kong sh

local/status:
	@echo "=== Service Status ==="
	@$(DOCKER_COMPOSE) ps
	@echo ""
	@echo "=== Kong Health ==="
	@curl -s $(KONG_ADMIN_URL)/status | jq . 2>/dev/null || echo "Kong not ready"
	@echo ""
	@echo "=== Endpoints ==="
	@echo "  Kong Proxy:  $(KONG_PROXY_URL)"
	@echo "  Kong Admin:  $(KONG_ADMIN_URL)"
	@echo "  Kong GUI:    http://localhost:8002"
	@echo "  Grafana:     http://localhost:3000 (admin/admin)"
	@echo "  Prometheus:  http://localhost:9090"

local/test:
	@echo "Running plugin tests with Pongo..."
	cd kong/plugins/bedrock-proxy && pongo run || true
	cd kong/plugins/token-meter && pongo run || true
	cd kong/plugins/ecommerce-guardrails && pongo run || true

# =============================================================================
# KONG CONFIGURATION (via Admin API)
# =============================================================================

setup-plugins:
	@echo "Configuring Kong via Admin API..."
	@# Enable Prometheus plugin globally
	@curl -s -X POST $(KONG_ADMIN_URL)/plugins \
		-d "name=prometheus" | jq .
	@echo "Plugins configured."

setup-consumers:
	@echo "Creating consumers and groups..."
	@# This will be implemented in Phase 2
	@echo "Run 'make local/bootstrap' after Kong config is ready."

local/bootstrap: setup-plugins setup-consumers
	@echo "Local environment bootstrapped."

# =============================================================================
# EKS DEPLOYMENT
# =============================================================================

eks/init:
	@echo "Initializing Terraform..."
	cd $(TERRAFORM_DIR) && terraform init

eks/plan:
	@echo "Running Terraform plan..."
	cd $(TERRAFORM_DIR) && terraform plan -out=tfplan

eks/apply:
	@echo "Applying Terraform..."
	cd $(TERRAFORM_DIR) && terraform apply tfplan

eks/destroy:
	@echo "WARNING: This will destroy EKS infrastructure!"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	cd $(TERRAFORM_DIR) && terraform destroy

eks/deploy:
	@echo "Deploying Kong to EKS via Helm..."
	helm upgrade --install $(HELM_RELEASE) kong/kong \
		--namespace $(HELM_NAMESPACE) \
		--create-namespace \
		-f infra/helm/kong-values.yaml

eks/status:
	@echo "=== EKS Kong Status ==="
	kubectl -n $(HELM_NAMESPACE) get pods
	kubectl -n $(HELM_NAMESPACE) get svc

# =============================================================================
# VALIDATION
# =============================================================================

validate:
	@echo "=== Validating Kong Configuration ==="
	@# Validate declarative config (if using DB-less)
	@if [ -f kong/kong.yaml ]; then \
		deck validate -s kong/kong.yaml && echo "kong.yaml: OK"; \
	fi
	@echo ""
	@echo "=== Lua Linting ==="
	@luacheck kong/plugins/ --no-unused-args --no-max-line-length || true
	@echo ""
	@echo "=== Terraform Validation ==="
	@cd infra/terraform && terraform validate || true

test: local/test
	@echo "All tests completed."

security-scan:
	@echo "=== Security Scan (Trivy) ==="
	@echo "Scanning container images..."
	trivy image kong:3.6-alpine --severity CRITICAL,HIGH || true
	@echo ""
	@echo "Scanning Terraform..."
	trivy config infra/terraform/ --severity CRITICAL,HIGH || true
	@echo ""
	@echo "Scanning Helm values..."
	trivy config infra/helm/ --severity CRITICAL,HIGH || true

# =============================================================================
# UTILITIES
# =============================================================================

clean:
	@echo "Cleaning up..."
	$(DOCKER_COMPOSE) down -v --remove-orphans
	rm -rf infra/terraform/environments/*/.terraform
	rm -rf infra/terraform/environments/*/tfplan
	@echo "Cleanup complete."

# =============================================================================
# CURL EXAMPLES (for testing)
# =============================================================================

curl/health:
	@curl -s $(KONG_PROXY_URL)/health | jq .

curl/chat:
	@echo "Testing chat endpoint (requires API key)..."
	@curl -s -X POST $(KONG_PROXY_URL)/v1/chat \
		-H "Content-Type: application/json" \
		-H "X-API-Key: dev-key-123" \
		-d '{"messages":[{"role":"user","content":"Hello, this is a test"}]}' | jq .

curl/admin-routes:
	@curl -s $(KONG_ADMIN_URL)/routes | jq '.data[] | {name, paths, service}'

curl/admin-services:
	@curl -s $(KONG_ADMIN_URL)/services | jq '.data[] | {name, host, port}'

curl/admin-plugins:
	@curl -s $(KONG_ADMIN_URL)/plugins | jq '.data[] | {name, enabled}'
