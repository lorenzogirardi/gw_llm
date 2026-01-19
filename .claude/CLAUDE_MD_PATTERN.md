# Pattern di Strutturazione .claude

Guida alla strutturazione della cartella `.claude` per progetti Claude Code, basata sul pattern sviluppato per il progetto Kong LLM Gateway.

---

## Filosofia di Design

### Separazione delle Responsabilità

La struttura `.claude` segue il principio di **separazione tra regole stabili e stato dinamico**:

| Tipo | File | Frequenza Aggiornamento |
|------|------|-------------------------|
| **Regole stabili** | `CLAUDE.md` | Raramente (setup iniziale) |
| **Stato dinamico** | `status.md` | Ogni sessione |
| **Competenze dominio** | `skills/*.md` | Per progetto/tecnologia |
| **Template** | `templates/*.md` | Raramente |

### Perché questa separazione?

1. **CLAUDE.md** viene letto ad ogni interazione - deve essere conciso e stabile
2. **status.md** traccia il progresso - cambia frequentemente
3. **Skills** sono modulari - si attivano solo quando servono
4. Le regole di lavoro non si mescolano con lo stato del progetto

---

## Struttura Directory

```
.claude/
├── CLAUDE.md                    # Regole di lavoro (STABILE)
├── README.md                    # Overview toolkit
├── status.md                    # Stato progetto (DINAMICO)
├── templates/
│   ├── spec.md                  # Template specifiche
│   └── tasks.md                 # Template task breakdown
└── skills/
    ├── lua/SKILL.md             # Skill per linguaggio/tool
    ├── aws-bedrock/SKILL.md
    ├── scm/SKILL.md
    ├── trivy/SKILL.md
    ├── spec-driven-dev/SKILL.md
    └── design-patterns/SKILL.md
```

---

## CLAUDE.md - Regole di Lavoro

### Cosa DEVE contenere

| Sezione | Scopo | Esempio |
|---------|-------|---------|
| Quick Reference | Regole da controllare SEMPRE | TDD, Conventional Commits |
| Identity | Come Claude deve comportarsi | Partner, non tool |
| Decision Framework | Autonomia per tipo di task | Green/Yellow/Red |
| Code Philosophy | Principi di sviluppo | KISS, YAGNI, TDD |
| Tech Stack | Tecnologie del progetto | Kong, Lua, Bedrock |
| Project Structure | Struttura cartelle | `kong/`, `infra/`, `docs/` |
| Documentation Requirements | Cosa documentare | C4, Runbooks, Mermaid |
| Language Skills | Skills disponibili | `/lua`, `/aws-bedrock` |
| Git Workflow | Convenzioni commit | Conventional Commits |
| Testing | Come testare | Pongo, Busted |

### Cosa NON deve contenere

- Stato corrente del progetto (va in `status.md`)
- Checklist di deliverables (va in `status.md`)
- Dettagli business specifici (va in `status.md`)
- Blockers e next steps (va in `status.md`)

### Esempio Quick Reference

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

## status.md - Stato del Progetto

### Cosa DEVE contenere

| Sezione | Scopo | Frequenza Update |
|---------|-------|------------------|
| Project Overview | Descrizione progetto | Setup iniziale |
| Architecture | Diagramma architettura | Quando cambia |
| RBAC/Business Rules | Regole business specifiche | Quando cambiano |
| Deliverables Checklist | Cosa è fatto/da fare | Ogni sessione |
| Technology Stack | Dettagli env local/prod | Setup iniziale |
| Security/Compliance | Regole sicurezza | Quando cambiano |
| Observability | Metriche e alert | Setup iniziale |
| Next Steps | Priorità immediate | Ogni sessione |
| Blockers | Problemi attuali | Quando esistono |
| Infrastructure Status | Stato risorse | Ogni sessione |
| Quick Commands | Comandi frequenti | Setup iniziale |

### Perché in status.md?

Il **contesto business** (RBAC, modelli, compliance, guardrails) sta in `status.md` perché:

1. **Cambia più frequentemente** di CLAUDE.md
2. **È specifico del progetto**, non delle regole di lavoro
3. **Viene aggiornato** ad ogni sessione
4. **CLAUDE.md resta riutilizzabile** per altri progetti simili

### Esempio Deliverables Checklist

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

## Skills - Competenze Modulari

### Struttura di una Skill

```yaml
---
name: skill-name
description: >-
  Descrizione della skill con trigger keywords.
  PROACTIVE: MUST invoke when [condizione].
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# ABOUTME: Breve descrizione
# ABOUTME: Seconda riga descrizione

# Titolo Skill

## Quick Reference
[Tabella regole principali]

## Sezioni Specifiche
[Contenuto tecnico]

## Anti-Patterns
[Cosa NON fare]

## Checklist
[Controlli pre-commit]
```

### Quando creare una Skill

| Criterio | Azione |
|----------|--------|
| Linguaggio specifico | Creare skill (es. `lua`, `python`) |
| Tool/Framework specifico | Creare skill (es. `aws-bedrock`, `trivy`) |
| Workflow riutilizzabile | Creare skill (es. `scm`, `spec-driven-dev`) |
| Pattern architetturali | Creare skill (es. `design-patterns`) |

### Skills vs CLAUDE.md

| Aspetto | CLAUDE.md | Skills |
|---------|-----------|--------|
| Caricamento | Sempre | On-demand |
| Contenuto | Regole generali | Dettagli tecnici |
| Lunghezza | Conciso | Può essere lungo |
| Scope | Tutto il progetto | Dominio specifico |

---

## Workflow di Utilizzo

### Setup Iniziale Progetto

1. **Copia struttura base** `.claude/` nel progetto
2. **Personalizza CLAUDE.md**:
   - Tech stack
   - Project structure
   - Decision framework specifico
3. **Crea status.md**:
   - Project overview
   - RBAC/Business rules
   - Deliverables checklist
   - Quick commands
4. **Seleziona/crea skills** per le tecnologie usate
5. **Rimuovi skills** non necessarie (es. `typescript` se usi solo Lua)

### Durante lo Sviluppo

```
┌─────────────────┐
│  Nuova Sessione │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Leggi status.md │  ← Stato attuale, next steps
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Invoca skill    │  ← /lua, /aws-bedrock se necessario
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Lavora sui task │  ← TDD, commit dopo ogni fase
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Aggiorna        │  ← Checklist, next steps, blockers
│ status.md       │
└─────────────────┘
```

### Fine Sessione

1. **Aggiorna status.md**:
   - Marca task completati
   - Aggiorna "Last Updated"
   - Documenta blockers
   - Definisci next steps
2. **Commit** con messaggio descrittivo

---

## Convenzioni di Naming

### File

| Pattern | Uso | Esempio |
|---------|-----|---------|
| `UPPERCASE.md` | File principali | `CLAUDE.md`, `README.md` |
| `lowercase.md` | File di stato/template | `status.md`, `spec.md` |
| `kebab-case/` | Cartelle skills | `aws-bedrock/`, `spec-driven-dev/` |
| `SKILL.md` | File skill (sempre uppercase) | `skills/lua/SKILL.md` |

### Sezioni Markdown

| Elemento | Formato |
|----------|---------|
| Titoli principali | `# Titolo` |
| Sottosezioni | `## Sezione` |
| Tabelle | Per regole, checklist, riferimenti |
| Code blocks | Per comandi, configurazioni, esempi |
| Checklist | `- [ ]` / `- [x]` per deliverables |

---

## Best Practices

### DO (Fare)

- Mantenere CLAUDE.md conciso (< 500 righe)
- Aggiornare status.md ad ogni sessione
- Usare tabelle per informazioni strutturate
- Includere Quick Reference in ogni skill
- Documentare anti-patterns
- Includere checklist pre-commit

### DON'T (Non fare)

- Mescolare regole stabili con stato dinamico
- Creare skill troppo generiche
- Duplicare informazioni tra file
- Lasciare status.md non aggiornato
- Omettere la sezione Quick Reference

---

## Esempio Completo: Kong LLM Gateway

### CLAUDE.md (estratto)

```markdown
# Tech Stack (Kong Gateway + AWS Bedrock)

| Layer | Technology |
|-------|------------|
| API Gateway | Kong Gateway (DB-less mode) |
| Plugin Development | Lua (Kong PDK) |
| LLM Backend | AWS Bedrock |
| Infrastructure | Terraform, EKS, Helm |
```

### status.md (estratto)

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

### Separazione chiara

- **CLAUDE.md**: "Usa Lua per i plugin Kong" (regola)
- **status.md**: "Il plugin bedrock-proxy deve supportare Claude 3.5 Sonnet con rate limit 10k tokens/min" (requisito specifico)

---

## Conclusione

Questo pattern permette di:

1. **Scalare** la configurazione Claude Code per progetti complessi
2. **Separare** regole stabili da stato dinamico
3. **Modularizzare** competenze tramite skills
4. **Tracciare** progresso in modo strutturato
5. **Riutilizzare** la struttura base per progetti simili

La chiave è mantenere la disciplina nell'aggiornare `status.md` e nel non inquinare `CLAUDE.md` con dettagli che cambiano frequentemente.
