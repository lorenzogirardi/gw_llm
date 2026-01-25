#!/bin/bash
#
# LiteLLM User Management Script
# Requires: curl, jq
#
# Usage:
#   ./litellm-users.sh <command> [options]
#
# Commands:
#   create-user     Create a new user with budget
#   list-users      List all users
#   get-user        Get user details
#   delete-user     Delete a user
#   create-key      Generate API key for user
#   list-keys       List all API keys
#   delete-key      Delete an API key
#   update-budget   Update user budget
#

set -e

# Configuration (override with environment variables)
LITELLM_URL="${LITELLM_URL:-https://d18l8nt8fin3hz.cloudfront.net}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"
ADMIN_SECRET="${ADMIN_SECRET:-}"
AWS_REGION="${AWS_REGION:-us-west-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
error() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $1${NC}"; }
info() { echo -e "$1"; }

check_dependencies() {
    command -v curl >/dev/null 2>&1 || error "curl is required but not installed"
    command -v jq >/dev/null 2>&1 || error "jq is required but not installed"
}

check_master_key() {
    if [ -z "$LITELLM_MASTER_KEY" ]; then
        error "LITELLM_MASTER_KEY environment variable is required"
    fi
}

fetch_admin_secret() {
    # Fetch admin secret from AWS Secrets Manager if not set
    if [ -z "$ADMIN_SECRET" ]; then
        info "Fetching admin secret from AWS Secrets Manager..."
        ADMIN_SECRET=$(aws secretsmanager get-secret-value \
            --secret-id "kong-llm-gateway-poc/admin-header-secret" \
            --region "$AWS_REGION" \
            --query 'SecretString' \
            --output text 2>/dev/null) || error "Failed to fetch admin secret from Secrets Manager"
    fi
}

api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    local response
    if [ -n "$data" ]; then
        response=$(curl -s -X "$method" "${LITELLM_URL}${endpoint}" \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            -H "Content-Type: application/json" \
            -H "X-Admin-Secret: ${ADMIN_SECRET}" \
            -d "$data")
    else
        response=$(curl -s -X "$method" "${LITELLM_URL}${endpoint}" \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            -H "Content-Type: application/json" \
            -H "X-Admin-Secret: ${ADMIN_SECRET}")
    fi

    # Check for errors
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.error.message // .error')
        error "$error_msg"
    fi

    echo "$response"
}

# Commands

cmd_create_user() {
    local email=""
    local budget=""
    local duration="monthly"
    local models=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --email) email="$2"; shift 2 ;;
            --budget) budget="$2"; shift 2 ;;
            --duration) duration="$2"; shift 2 ;;
            --models) models="$2"; shift 2 ;;
            *) error "Unknown option: $1" ;;
        esac
    done

    [ -z "$email" ] && error "Email is required (--email)"

    local payload="{\"user_email\": \"$email\""
    [ -n "$budget" ] && payload="$payload, \"max_budget\": $budget"
    [ -n "$duration" ] && payload="$payload, \"budget_duration\": \"$duration\""
    [ -n "$models" ] && payload="$payload, \"models\": $models"
    payload="$payload}"

    info "Creating user: $email"
    local result=$(api_call POST "/user/new" "$payload")

    local user_id=$(echo "$result" | jq -r '.user_id // empty')
    if [ -n "$user_id" ]; then
        success "User created successfully!"
        echo "$result" | jq '.'
    else
        echo "$result" | jq '.'
    fi
}

cmd_list_users() {
    info "Listing all users..."
    api_call GET "/user/list" | jq '.'
}

cmd_get_user() {
    local user_id="$1"
    [ -z "$user_id" ] && error "User ID is required"

    info "Getting user: $user_id"
    api_call GET "/user/info?user_id=$user_id" | jq '.'
}

cmd_delete_user() {
    local user_id="$1"
    [ -z "$user_id" ] && error "User ID is required"

    warn "Deleting user: $user_id"
    read -p "Are you sure? (y/N) " confirm
    [ "$confirm" != "y" ] && exit 0

    api_call POST "/user/delete" "{\"user_ids\": [\"$user_id\"]}"
    success "User deleted"
}

cmd_create_key() {
    local user_id=""
    local alias=""
    local budget=""
    local duration=""
    local models=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --user-id) user_id="$2"; shift 2 ;;
            --alias) alias="$2"; shift 2 ;;
            --budget) budget="$2"; shift 2 ;;
            --duration) duration="$2"; shift 2 ;;
            --models) models="$2"; shift 2 ;;
            *) error "Unknown option: $1" ;;
        esac
    done

    local payload="{"
    local first=true

    if [ -n "$user_id" ]; then
        payload="$payload\"user_id\": \"$user_id\""
        first=false
    fi
    if [ -n "$alias" ]; then
        [ "$first" = false ] && payload="$payload, "
        payload="$payload\"key_alias\": \"$alias\""
        first=false
    fi
    if [ -n "$budget" ]; then
        [ "$first" = false ] && payload="$payload, "
        payload="$payload\"max_budget\": $budget"
        first=false
    fi
    if [ -n "$duration" ]; then
        [ "$first" = false ] && payload="$payload, "
        payload="$payload\"budget_duration\": \"$duration\""
        first=false
    fi
    if [ -n "$models" ]; then
        [ "$first" = false ] && payload="$payload, "
        payload="$payload\"models\": $models"
        first=false
    fi
    payload="$payload}"

    info "Generating API key..."
    local result=$(api_call POST "/key/generate" "$payload")

    local key=$(echo "$result" | jq -r '.key // empty')
    if [ -n "$key" ]; then
        success "API Key generated successfully!"
        echo ""
        echo "=========================================="
        echo -e "${GREEN}API Key: $key${NC}"
        echo "=========================================="
        echo ""
        warn "Save this key! It cannot be retrieved later."
        echo ""
        echo "Full response:"
        echo "$result" | jq '.'
    else
        echo "$result" | jq '.'
    fi
}

cmd_list_keys() {
    info "Listing all API keys..."
    api_call GET "/key/list" | jq '.'
}

cmd_delete_key() {
    local key="$1"
    [ -z "$key" ] && error "API key is required"

    warn "Deleting API key: ${key:0:20}..."
    read -p "Are you sure? (y/N) " confirm
    [ "$confirm" != "y" ] && exit 0

    api_call POST "/key/delete" "{\"keys\": [\"$key\"]}"
    success "Key deleted"
}

cmd_update_budget() {
    local user_id=""
    local budget=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --user-id) user_id="$2"; shift 2 ;;
            --budget) budget="$2"; shift 2 ;;
            *) error "Unknown option: $1" ;;
        esac
    done

    [ -z "$user_id" ] && error "User ID is required (--user-id)"
    [ -z "$budget" ] && error "Budget is required (--budget)"

    info "Updating budget for user: $user_id"
    api_call POST "/user/update" "{\"user_id\": \"$user_id\", \"max_budget\": $budget}" | jq '.'
    success "Budget updated"
}

# Usage
usage() {
    cat << EOF
LiteLLM User Management Script

Usage: $0 <command> [options]

Commands:
  create-user     Create a new user
                  Options:
                    --email <email>       User email (required)
                    --budget <amount>     Max budget in USD
                    --duration <period>   Budget period: daily, weekly, monthly
                    --models <json>       Allowed models: '["claude-haiku-4-5"]'

  list-users      List all users

  get-user <id>   Get user details

  delete-user <id> Delete a user

  create-key      Generate API key
                  Options:
                    --user-id <id>        Associate with user
                    --alias <name>        Key alias/name
                    --budget <amount>     Key-specific budget
                    --duration <period>   Budget period
                    --models <json>       Allowed models

  list-keys       List all API keys

  delete-key <key> Delete an API key

  update-budget   Update user budget
                  Options:
                    --user-id <id>        User ID (required)
                    --budget <amount>     New budget (required)

Environment Variables:
  LITELLM_URL         LiteLLM proxy URL (default: https://d18l8nt8fin3hz.cloudfront.net)
  LITELLM_MASTER_KEY  Master API key (required)
  ADMIN_SECRET        Admin header secret (auto-fetched from AWS Secrets Manager if not set)
  AWS_REGION          AWS region for Secrets Manager (default: us-west-1)

Examples:
  # Create user with \$50 monthly budget
  export LITELLM_MASTER_KEY="sk-litellm-xxx"
  $0 create-user --email user@example.com --budget 50 --duration monthly

  # Create user with specific models only
  $0 create-user --email dev@example.com --budget 10 --models '["claude-haiku-4-5"]'

  # Generate API key for user
  $0 create-key --user-id user_xxx --alias "laptop-key"

  # Generate standalone key with budget
  $0 create-key --alias "test-key" --budget 5 --models '["claude-haiku-4-5"]'

  # List all users
  $0 list-users

EOF
    exit 1
}

# Main
main() {
    check_dependencies
    check_master_key
    fetch_admin_secret

    local command="${1:-}"
    shift || true

    case "$command" in
        create-user)  cmd_create_user "$@" ;;
        list-users)   cmd_list_users ;;
        get-user)     cmd_get_user "$@" ;;
        delete-user)  cmd_delete_user "$@" ;;
        create-key)   cmd_create_key "$@" ;;
        list-keys)    cmd_list_keys ;;
        delete-key)   cmd_delete_key "$@" ;;
        update-budget) cmd_update_budget "$@" ;;
        help|--help|-h|"") usage ;;
        *) error "Unknown command: $command. Use '$0 help' for usage." ;;
    esac
}

main "$@"
