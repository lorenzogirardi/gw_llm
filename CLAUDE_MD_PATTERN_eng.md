# .claude Structuring Pattern

Guide to structuring the `.claude` folder for Claude Code projects, based on the pattern developed for the Kong LLM Gateway project.

---

## Design Philosophy

### Separation of Concerns

The `.claude` structure follows the principle of **separating stable rules from dynamic state**:

| Type | File | Update Frequency |
|------|------|------------------|
| **Stable rules** | `CLAUDE.md` | Rarely (initial setup) |
| **Dynamic state** | `status.md` | Every session |
| **Domain expertise** | `skills/*.md` | Per project/technology |
| **Templates** | `templates/*.md` | Rarely |

### Why this separation?

1. **CLAUDE.md** is read on every interaction - it must be concise and stable
2. **status.md** tracks progress - it changes frequently
3. **Skills** are modular - they activate only when needed
4. Work rules don't mix with project state

---

## Directory Structure

```
.claude/
├── CLAUDE.md                    # Work rules (STABLE)
├── README.md                    # Toolkit overview
├── status.md                    # Project state (DYNAMIC)
├── templates/
│   ├── spec.md                  # Specification template
│   └── tasks.md                 # Task breakdown template
└── skills/
    ├── lua/SKILL.md             # Language/tool specific skill
    ├── aws-bedrock/SKILL.md
    ├── scm/SKILL.md
    ├── trivy/SKILL.md
    ├── spec-driven-dev/SKILL.md
    └── design-patterns/SKILL.md
```

---

## CLAUDE.md - Work Rules

### What it MUST contain

| Section | Purpose | Example |
|---------|---------|---------|
| Quick Reference | Rules to check ALWAYS | TDD, Conventional Commits |
| Identity | How Claude should behave | Partner, not tool |
| Decision Framework | Autonomy by task type | Green/Yellow/Red |
| Code Philosophy | Development principles | KISS, YAGNI, TDD |
| Tech Stack | Project technologies | Kong, Lua, Bedrock |
| Project Structure | Folder structure | `kong/`, `infra/`, `docs/` |
| Documentation Requirements | What to document | C4, Runbooks, Mermaid |
| Language Skills | Available skills | `/lua`, `/aws-bedrock` |
| Git Workflow | Commit conventions | Conventional Commits |
| Testing | How to test | Pongo, Busted |

### What it must NOT contain

- Current project state (goes in `status.md`)
- Deliverables checklist (goes in `status.md`)
- Specific business details (goes in `status.md`)
- Blockers and next steps (goes in `status.md`)

### Quick Reference Example

```markdown
# Quick Reference (CHECK BEFORE EVERY TASK)

| Rule | When | Action |
|------|------|--------|
| **TDD** | Always | Red -> Green -> Refactor -> Commit |
| **Documentation** | Every change | Update docs, runbook, architecture |
| **Lua Skill** | Writing/Editing .lua files | Invoke `/lua` BEFORE Write or Edit |
| **Conventional Commits** | Every commit | feat/fix/docs/style/refactor/test/chore |
```

---

## status.md - Project State

### What it MUST contain

| Section | Purpose | Update Frequency |
|---------|---------|------------------|
| Project Overview | Project description | Initial setup |
| Architecture | Architecture diagram | When it changes |
| RBAC/Business Rules | Specific business rules | When they change |
| Deliverables Checklist | What's done/to do | Every session |
| Technology Stack | Local/prod env details | Initial setup |
| Security/Compliance | Security rules | When they change |
| Observability | Metrics and alerts | Initial setup |
| Next Steps | Immediate priorities | Every session |
| Blockers | Current problems | When they exist |
| Infrastructure Status | Resource state | Every session |
| Quick Commands | Frequent commands | Initial setup |

### Why in status.md?

**Business context** (RBAC, models, compliance, guardrails) belongs in `status.md` because:

1. **Changes more frequently** than CLAUDE.md
2. **Is project-specific**, not work rules
3. **Gets updated** every session
4. **CLAUDE.md stays reusable** for similar projects

### Deliverables Checklist Example

```markdown
## Deliverables Checklist

### Configuration Files
- [ ] `docker-compose.yml` - Local Kong + Postgres
- [x] `kong-local.yaml` - Declarative DB-less config
- [ ] `helm/kong-values.yaml` - EKS production values

### Custom Plugins
- [ ] `kong/plugins/bedrock-proxy/` - Bedrock integration
- [ ] `kong/plugins/token-meter/` - Token tracking
```

---

## Skills - Modular Expertise

### Skill Structure

```yaml
---
name: skill-name
description: >-
  Skill description with trigger keywords.
  PROACTIVE: MUST invoke when [condition].
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# ABOUTME: Brief description
# ABOUTME: Second line description

# Skill Title

## Quick Reference
[Main rules table]

## Specific Sections
[Technical content]

## Anti-Patterns
[What NOT to do]

## Checklist
[Pre-commit checks]
```

### When to create a Skill

| Criterion | Action |
|-----------|--------|
| Specific language | Create skill (e.g., `lua`, `python`) |
| Specific tool/framework | Create skill (e.g., `aws-bedrock`, `trivy`) |
| Reusable workflow | Create skill (e.g., `scm`, `spec-driven-dev`) |
| Architectural patterns | Create skill (e.g., `design-patterns`) |

### Skills vs CLAUDE.md

| Aspect | CLAUDE.md | Skills |
|--------|-----------|--------|
| Loading | Always | On-demand |
| Content | General rules | Technical details |
| Length | Concise | Can be long |
| Scope | Entire project | Specific domain |

---

## Usage Workflow

### Initial Project Setup

1. **Copy base structure** `.claude/` to the project
2. **Customize CLAUDE.md**:
   - Tech stack
   - Project structure
   - Specific decision framework
3. **Create status.md**:
   - Project overview
   - RBAC/Business rules
   - Deliverables checklist
   - Quick commands
4. **Select/create skills** for used technologies
5. **Remove unused skills** (e.g., `typescript` if using only Lua)

### During Development

```
┌─────────────────┐
│   New Session   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Read status.md  │  ← Current state, next steps
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Invoke skill    │  ← /lua, /aws-bedrock if needed
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Work on tasks   │  ← TDD, commit after each phase
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Update          │  ← Checklist, next steps, blockers
│ status.md       │
└─────────────────┘
```

### End of Session

1. **Update status.md**:
   - Mark completed tasks
   - Update "Last Updated"
   - Document blockers
   - Define next steps
2. **Commit** with descriptive message

---

## Naming Conventions

### Files

| Pattern | Usage | Example |
|---------|-------|---------|
| `UPPERCASE.md` | Main files | `CLAUDE.md`, `README.md` |
| `lowercase.md` | State/template files | `status.md`, `spec.md` |
| `kebab-case/` | Skill folders | `aws-bedrock/`, `spec-driven-dev/` |
| `SKILL.md` | Skill file (always uppercase) | `skills/lua/SKILL.md` |

### Markdown Sections

| Element | Format |
|---------|--------|
| Main titles | `# Title` |
| Subsections | `## Section` |
| Tables | For rules, checklists, references |
| Code blocks | For commands, configs, examples |
| Checklists | `- [ ]` / `- [x]` for deliverables |

---

## Best Practices

### DO

- Keep CLAUDE.md concise (< 500 lines)
- Update status.md every session
- Use tables for structured information
- Include Quick Reference in every skill
- Document anti-patterns
- Include pre-commit checklists

### DON'T

- Mix stable rules with dynamic state
- Create overly generic skills
- Duplicate information across files
- Leave status.md outdated
- Omit the Quick Reference section

---

## Complete Example: Kong LLM Gateway

### CLAUDE.md (excerpt)

```markdown
# Tech Stack (Kong Gateway + AWS Bedrock)

| Layer | Technology |
|-------|------------|
| API Gateway | Kong Gateway (DB-less mode) |
| Plugin Development | Lua (Kong PDK) |
| LLM Backend | AWS Bedrock |
| Infrastructure | Terraform, EKS, Helm |
```

### status.md (excerpt)

```markdown
## Role-Based Model Access

| Role | Model | Model ID | Rate Limit |
|------|-------|----------|------------|
| `developer` | Claude 3.5 Sonnet | `anthropic.claude-3-5-sonnet-20240620-v1:0` | 10k tokens/min |
| `analyst` | Claude 3 Sonnet | `anthropic.claude-3-sonnet-20240229-v1:0` | 5k tokens/min |

## Deliverables Checklist

### Custom Plugins
- [ ] `kong/plugins/bedrock-proxy/` - Bedrock integration
- [ ] `kong/plugins/token-meter/` - Token tracking
```

### Clear separation

- **CLAUDE.md**: "Use Lua for Kong plugins" (rule)
- **status.md**: "The bedrock-proxy plugin must support Claude 3.5 Sonnet with 10k tokens/min rate limit" (specific requirement)

---

## Conclusion

This pattern allows you to:

1. **Scale** Claude Code configuration for complex projects
2. **Separate** stable rules from dynamic state
3. **Modularize** expertise through skills
4. **Track** progress in a structured way
5. **Reuse** the base structure for similar projects

The key is maintaining discipline in updating `status.md` and not polluting `CLAUDE.md` with details that change frequently.
