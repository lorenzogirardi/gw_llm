---
name: trivy
description: >-
  Security vulnerability scanning using Trivy for Kong Gateway project. Scans
  container images, Helm charts, Terraform IaC, and Lua dependencies.
  Blocks CRITICAL and HIGH severity. Triggers on "trivy", "vulnerability scan",
  "security scan", "container scan", "cve", "helm scan", "terraform scan".
  PROACTIVE: MUST invoke before committing infrastructure or image changes.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# ABOUTME: Security vulnerability scanning skill using Trivy
# ABOUTME: Enforces CRITICAL/HIGH blocking for Kong, Helm, and Terraform

# Trivy Security Scanning Skill

## Quick Reference

| Scan Type | Command | When |
|-----------|---------|------|
| Container | `trivy image <name>` | Dockerfile/image changes |
| Helm | `trivy config helm/` | Helm values changes |
| Terraform | `trivy config infra/terraform/` | IaC changes |
| Filesystem | `trivy fs .` | Dependency changes |

---

## When to Scan

| Trigger | Action |
|---------|--------|
| `Dockerfile` modified | Scan container image |
| `kong-values.yaml` changed | Scan Helm config |
| `*.tf` files changed | Scan Terraform IaC |
| Kong base image update | Scan new image |
| Before commit with infra | **MANDATORY** scan |

---

## Scan Commands

### Kong Container Image

```bash
# Build Kong image with custom plugins
docker build -t kong-bedrock:local .

# Scan the image
trivy image \
    --severity CRITICAL,HIGH \
    --exit-code 1 \
    --ignore-unfixed \
    kong-bedrock:local
```

### Official Kong Image

```bash
# Scan Kong base image
trivy image \
    --severity CRITICAL,HIGH \
    kong:3.6-alpine
```

### Helm Chart Scan

```bash
# Scan Helm values for misconfigurations
trivy config \
    --severity CRITICAL,HIGH \
    --exit-code 1 \
    infra/helm/

# Scan rendered manifests
helm template kong kong/kong -f infra/helm/kong-values.yaml | \
    trivy config --severity CRITICAL,HIGH -
```

### Terraform IaC Scan

```bash
# Scan all Terraform files
trivy config \
    --severity CRITICAL,HIGH \
    --exit-code 1 \
    infra/terraform/

# Scan specific module
trivy config infra/terraform/modules/eks/
trivy config infra/terraform/modules/bedrock/
```

### Kubernetes Manifest Scan

```bash
# If using raw manifests
trivy config \
    --severity CRITICAL,HIGH \
    k8s/
```

---

## Severity Policy

| Severity | Action | Commit Allowed |
|----------|--------|----------------|
| CRITICAL | **BLOCK** - Fix immediately | NO |
| HIGH | **BLOCK** - Fix or document exception | NO |
| MEDIUM | WARN - Plan remediation | YES |
| LOW | INFO - Document | YES |

---

## Common Findings

### Container Image

| Finding | Cause | Fix |
|---------|-------|-----|
| CVE in base image | Outdated Kong image | Update `FROM kong:X.Y` |
| CVE in Alpine packages | Outdated packages | Add `apk upgrade` |
| Root user | Running as root | Use `USER kong` |
| Writable filesystem | No read-only root | Set `readOnlyRootFilesystem: true` |

### Helm/Kubernetes

| Finding | Cause | Fix |
|---------|-------|-----|
| No resource limits | Missing limits | Add `resources.limits` |
| Privileged container | `privileged: true` | Remove or justify |
| Host network | `hostNetwork: true` | Use pod network |
| No security context | Missing securityContext | Add proper context |

### Terraform/AWS

| Finding | Cause | Fix |
|---------|-------|-----|
| Public S3 bucket | ACL misconfigured | Set private ACL |
| IAM wildcard | `Resource: "*"` | Scope to specific ARNs |
| Unencrypted storage | Missing encryption | Enable encryption |
| Open security group | 0.0.0.0/0 ingress | Restrict CIDR |

---

## Kong-Specific Checks

### Dockerfile Best Practices

```dockerfile
# GOOD: Minimal, non-root, updated
FROM kong:3.6-alpine

# Update packages
RUN apk update && apk upgrade --no-cache

# Copy custom plugins
COPY --chown=kong:kong plugins/ /usr/local/share/lua/5.1/kong/plugins/

# Don't run as root
USER kong

# BAD: Root user, outdated packages
FROM kong:3.0
COPY plugins/ /usr/local/share/lua/5.1/kong/plugins/
```

### Helm Values Security

```yaml
# kong-values.yaml

# GOOD: Security-hardened
deployment:
  pod:
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      fsGroup: 1000
    containers:
      kong:
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL

  resources:
    limits:
      cpu: "2"
      memory: "2Gi"
    requests:
      cpu: "500m"
      memory: "512Mi"
```

### Terraform IAM Least Privilege

```hcl
# GOOD: Scoped permissions
resource "aws_iam_role_policy" "bedrock_invoke" {
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel"  # Only invoke, not manage
      ]
      Resource = [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-*"
      ]
    }]
  })
}

# BAD: Wildcard permissions
resource "aws_iam_role_policy" "bad_policy" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:*"]  # Too broad
      Resource = ["*"]          # Too broad
    }]
  })
}
```

---

## CI Integration

### GitHub Actions

```yaml
# .github/workflows/security.yml
name: Security Scan

on:
  pull_request:
    paths:
      - 'Dockerfile'
      - 'infra/**'
      - 'kong-values.yaml'

jobs:
  trivy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: docker build -t kong-bedrock:${{ github.sha }} .

      - name: Scan image
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'kong-bedrock:${{ github.sha }}'
          format: 'sarif'
          output: 'trivy-image.sarif'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'

      - name: Scan IaC
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          scan-ref: 'infra/'
          format: 'sarif'
          output: 'trivy-iac.sarif'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'

      - name: Upload results
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-image.sarif'
```

---

## Remediation Strategies

### Strategy 1: Update Base Image

```dockerfile
# Check latest Kong version
# https://hub.docker.com/_/kong/tags

# Update FROM line
FROM kong:3.6-alpine  # Latest stable
```

### Strategy 2: Add Trivy Ignore

Create `.trivyignore`:

```
# CVE-2024-XXXXX: Not exploitable - Kong doesn't use affected component
# Justification: [Link to analysis]
# Review date: 2024-XX-XX
CVE-2024-XXXXX
```

**WARNING**: Every exclusion MUST have documented justification and review date.

### Strategy 3: Override in Helm

```yaml
# Fix security context issues
deployment:
  pod:
    securityContext:
      runAsNonRoot: true
```

### Strategy 4: Fix Terraform

```hcl
# Scope IAM permissions
resource = [
  "arn:aws:bedrock:${var.region}::foundation-model/${var.model_id}"
]
```

---

## Checklist

Before committing infrastructure changes:

- [ ] Trivy installed (`brew install trivy`)
- [ ] Container image scanned (if Dockerfile changed)
- [ ] Helm config scanned (if values changed)
- [ ] Terraform scanned (if IaC changed)
- [ ] No CRITICAL vulnerabilities
- [ ] No HIGH vulnerabilities (or documented exception)
- [ ] Any `.trivyignore` entries have justification
- [ ] Security context properly configured
- [ ] IAM follows least privilege

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `trivy: command not found` | `brew install trivy` |
| Slow image scan | Use `--skip-db-update` after first run |
| False positive | Add to `.trivyignore` with justification |
| Helm scan fails | Check YAML syntax first |
| Terraform scan incomplete | Run `terraform init` first |
| Old vulnerability DB | Run `trivy --download-db-only` |
