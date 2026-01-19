---
name: scm
description: >-
  Git workflow and source control management for Kong Gateway project. Covers
  Conventional Commits, branch strategy, PR workflow, and conflict resolution.
  Triggers on "git", "commit", "branch", "merge", "rebase", "pull request", "PR",
  "conventional commits", "git workflow", "push", "commit message".
  PROACTIVE: MUST invoke when performing Git operations.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# ABOUTME: Git workflow skill for Kong Gateway project
# ABOUTME: Covers Conventional Commits, GitHub Flow, and team collaboration

# Source Control Management (SCM) Skill

## Quick Reference

| Principle | Rule |
|-----------|------|
| Atomic Commits | One logical change per commit |
| Conventional Commits | `type(scope): description` format |
| Branch Naming | `type/ticket-description` format |
| PR Size | < 400 lines of code changes |
| Never Force Push | To shared branches (main) |

---

## Branching Strategy (GitHub Flow)

```
main ─────●───────●───────●───────●──────
          │       ↑       │       ↑
          ↓       │       ↓       │
feature ──●──●──●─┘ fix ──●──●────┘
```

**Branches:**
- `main`: Always deployable (protected)
- `feature/*`: New features
- `fix/*`: Bug fixes
- `chore/*`: Maintenance
- `docs/*`: Documentation

---

## Conventional Commits

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | Description | Example |
|------|-------------|---------|
| `feat` | New feature | `feat(plugin): add bedrock proxy plugin` |
| `fix` | Bug fix | `fix(auth): correct token validation` |
| `docs` | Documentation | `docs(readme): update deployment steps` |
| `style` | Formatting | `style(lua): fix indentation` |
| `refactor` | Code restructure | `refactor(plugin): extract signing logic` |
| `test` | Tests | `test(bedrock): add integration tests` |
| `chore` | Build/tooling | `chore(deps): update kong base image` |
| `perf` | Performance | `perf(plugin): cache signed headers` |
| `ci` | CI config | `ci(actions): add security scan` |

### Scopes (Kong/Bedrock)

| Scope | Area |
|-------|------|
| `kong` | Kong configuration (kong.yaml) |
| `plugin` | Custom Lua plugins |
| `bedrock` | AWS Bedrock integration |
| `auth` | Authentication/API keys |
| `rate-limit` | Rate limiting logic |
| `infra` | Terraform/Helm/EKS |
| `ci` | GitHub Actions |
| `helm` | Helm chart values |

---

## Branch Naming

```
<type>/<ticket>-<description>

Examples:
- feature/KONG-123-bedrock-proxy-plugin
- fix/KONG-456-rate-limit-bypass
- chore/KONG-789-update-kong-version
```

---

## Commit Workflow

### TDD Commit Pattern

```bash
# Red phase
git add kong/plugins/*/spec/
git commit -m "test(plugin): add bedrock proxy tests"

# Green phase
git add kong/plugins/*/
git commit -m "feat(plugin): implement bedrock proxy"

# Refactor phase
git add kong/plugins/*/
git commit -m "refactor(plugin): extract aws signing module"
```

### Multi-line Commit (HEREDOC)

```bash
git commit -m "$(cat <<'EOF'
feat(plugin): add bedrock proxy plugin

- Route requests to AWS Bedrock
- Sign requests with AWS SigV4
- Support Claude and Titan models
- Add rate limiting per consumer

Closes #123
EOF
)"
```

---

## Pull Request Workflow

### Before Creating PR

```bash
# 1. Ensure branch is up to date
git fetch origin
git rebase origin/main

# 2. Validate Kong config
deck validate -s kong/kong.yaml

# 3. Run plugin tests
pongo run

# 4. Run linters
luacheck kong/plugins/
terraform validate infra/terraform/

# 5. Review changes
git diff origin/main...HEAD
git log origin/main..HEAD --oneline
```

### PR Description Template

```markdown
## Summary
- Brief description (1-3 bullet points)

## Changes
- Added bedrock-proxy plugin
- Modified kong.yaml to include new routes
- Updated Helm values for IRSA

## Testing
- [ ] Plugin tests pass (pongo run)
- [ ] Kong config validates (deck validate)
- [ ] Terraform plan succeeds
- [ ] Manual testing completed

## Deployment Notes
- Requires IAM role update (see infra changes)
- New environment variable: BEDROCK_MODEL

## Related Issues
Closes #123
```

### PR Size Guidelines

| Size | Lines | Review Time |
|------|-------|-------------|
| XS | < 50 | Minutes |
| S | 50-200 | < 30 min |
| M | 200-400 | < 1 hour |
| L | 400-800 | Hours |
| XL | > 800 | Split required |

---

## Conflict Resolution

### Understanding Conflicts

```
<<<<<<< HEAD (current branch)
local timeout = 5000
=======
local timeout = 10000
>>>>>>> feature-branch (incoming)
```

### Resolution Commands

```bash
# Keep current branch version
git checkout --ours path/to/file

# Keep incoming version
git checkout --theirs path/to/file

# After manual resolution
git add path/to/file
git rebase --continue
```

---

## Safety Rules

### Never Do

```bash
# Never force push to main
git push --force origin main  # DANGEROUS

# Never rebase shared branches
git rebase main  # on shared feature branch

# Never reset pushed commits
git reset --hard HEAD~3  # if already pushed
```

### Safe Alternatives

```bash
# Use force-with-lease
git push --force-with-lease

# Merge instead of rebase on shared
git merge origin/main

# Revert instead of reset
git revert <sha>
```

---

## Common Operations

### Undo Operations

```bash
# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo uncommitted changes
git checkout -- path/to/file

# Revert pushed commit
git revert <sha>
```

### Stashing

```bash
# Stash changes
git stash save "WIP: plugin development"

# List stashes
git stash list

# Apply and drop
git stash pop
```

---

## Checklist

Before committing:
- [ ] Changes are atomic (one logical change)
- [ ] Commit message follows Conventional Commits
- [ ] Tests pass locally (pongo run)
- [ ] No debug code or print statements
- [ ] No secrets or credentials
- [ ] Branch is up to date with main
- [ ] Kong config validates (deck validate)

Before creating PR:
- [ ] Rebased on latest main
- [ ] All commits have meaningful messages
- [ ] PR is < 400 lines
- [ ] Description explains what and why
- [ ] Related issues linked
- [ ] CI checks pass
