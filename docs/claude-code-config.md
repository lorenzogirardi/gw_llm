# Claude Code Configuration for LLM Gateway

## Quick Setup

Add these environment variables to your shell configuration (`~/.bashrc`, `~/.zshrc`, or equivalent):

```bash
# LLM Gateway Configuration
export ANTHROPIC_BASE_URL="https://d18l8nt8fin3hz.cloudfront.net"
export ANTHROPIC_API_KEY="<YOUR_LITELLM_API_KEY>"
```

Then reload your shell:
```bash
source ~/.bashrc  # or ~/.zshrc
```

## Get Your API Key

Contact the gateway administrator to get your personal API key. The master key should NOT be shared - each user should have their own key.

### Creating User Keys (Admin Only)

```bash
# Create a new user with budget
curl -X POST "https://d18l8nt8fin3hz.cloudfront.net/user/new" \
  -H "Authorization: Bearer <MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "user@example.com",
    "max_budget": 10.0,
    "budget_duration": "monthly"
  }'

# Create API key for user
curl -X POST "https://d18l8nt8fin3hz.cloudfront.net/key/generate" \
  -H "Authorization: Bearer <MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "<USER_ID_FROM_ABOVE>",
    "key_alias": "user-laptop"
  }'
```

## Available Models

| Model Name | Description | Status |
|------------|-------------|--------|
| `claude-haiku-4-5` | Fast, cost-effective | Working |
| `claude-sonnet-4-5` | Balanced performance | Needs AWS approval |
| `claude-opus-4-5` | Most capable | Needs AWS approval |

## Test Your Configuration

```bash
# Test with curl
curl -X POST "$ANTHROPIC_BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ANTHROPIC_API_KEY" \
  -d '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"Hello"}],"max_tokens":50}'

# Test with Claude Code
claude --version
```

## Monitoring

- **Grafana Dashboard**: https://d18l8nt8fin3hz.cloudfront.net/grafana
- View your token usage and costs in the "LLM Usage Overview" dashboard

## Troubleshooting

### "Unauthorized" error
- Check that ANTHROPIC_API_KEY is set correctly
- Verify the key is valid: `echo $ANTHROPIC_API_KEY`

### "Model not found" error
- Use one of the available model names listed above
- Check available models: `curl -H "Authorization: Bearer $ANTHROPIC_API_KEY" $ANTHROPIC_BASE_URL/v1/models`

### Connection timeout
- Verify ANTHROPIC_BASE_URL is correct
- Test health: `curl $ANTHROPIC_BASE_URL/health/liveliness`
