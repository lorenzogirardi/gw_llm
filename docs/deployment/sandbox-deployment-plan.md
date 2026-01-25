# Piano Deployment Sandbox - Nuovo Account AWS

**Data prevista:** 2025-01-26
**Region:** us-east-1
**Account:** [DA DEFINIRE]

---

## Pre-Requisiti

### 1. Accesso Account AWS

- [ ] Credenziali AWS con permessi amministrativi
- [ ] AWS CLI configurato (`aws configure`)
- [ ] Verifica account: `aws sts get-caller-identity`

```bash
# Output atteso
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/admin"
}
```

---

## Fase 1: Setup Account (30 min)

### 1.1 Terraform State Backend

```bash
# Variabili
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-east-1"
export PROJECT_NAME="stargate-llm-gateway"
export ENVIRONMENT="sandbox"

# Crea S3 bucket per Terraform state
aws s3api create-bucket \
    --bucket "${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}" \
    --region ${AWS_REGION}

# Abilita versioning
aws s3api put-bucket-versioning \
    --bucket "${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}" \
    --versioning-configuration Status=Enabled

# Abilita encryption
aws s3api put-bucket-encryption \
    --bucket "${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}" \
    --server-side-encryption-configuration '{
        "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'

# Block public access
aws s3api put-public-access-block \
    --bucket "${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}" \
    --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'
```

### 1.2 DynamoDB per State Locking

```bash
aws dynamodb create-table \
    --table-name "${PROJECT_NAME}-terraform-locks" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region ${AWS_REGION}
```

### 1.3 IAM User per CI/CD (opzionale)

```bash
# Crea user per GitHub Actions
aws iam create-user --user-name github-actions-${PROJECT_NAME}

# Attach policy (usa policy esistente o crea custom)
aws iam attach-user-policy \
    --user-name github-actions-${PROJECT_NAME} \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Crea access key
aws iam create-access-key --user-name github-actions-${PROJECT_NAME}

# SALVA OUTPUT - Access Key ID e Secret Access Key
```

---

## Fase 2: Secrets Manager (15 min)

### 2.1 Genera Secrets

```bash
# Funzione per generare secret random
generate_secret() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

# Genera tutti i secrets
export ORIGIN_VERIFY_SECRET=$(generate_secret)
export ADMIN_HEADER_SECRET=$(generate_secret)
export LITELLM_MASTER_KEY="sk-$(generate_secret)"
export GRAFANA_ADMIN_PASSWORD=$(generate_secret)
export LANGFUSE_NEXTAUTH_SECRET=$(generate_secret)
export LANGFUSE_SALT=$(generate_secret)

# Mostra secrets (SALVA IN POSTO SICURO!)
echo "=== SECRETS (SALVA QUESTI VALORI!) ==="
echo "ORIGIN_VERIFY_SECRET: $ORIGIN_VERIFY_SECRET"
echo "ADMIN_HEADER_SECRET: $ADMIN_HEADER_SECRET"
echo "LITELLM_MASTER_KEY: $LITELLM_MASTER_KEY"
echo "GRAFANA_ADMIN_PASSWORD: $GRAFANA_ADMIN_PASSWORD"
echo "LANGFUSE_NEXTAUTH_SECRET: $LANGFUSE_NEXTAUTH_SECRET"
echo "LANGFUSE_SALT: $LANGFUSE_SALT"
```

### 2.2 Crea Secrets in AWS

```bash
# Origin Verify Secret
aws secretsmanager create-secret \
    --name "stargate-sandbox/origin-verify-secret" \
    --secret-string "$ORIGIN_VERIFY_SECRET" \
    --region ${AWS_REGION}

# Admin Header Secret
aws secretsmanager create-secret \
    --name "stargate-sandbox/admin-header-secret" \
    --secret-string "$ADMIN_HEADER_SECRET" \
    --region ${AWS_REGION}

# LiteLLM Master Key
aws secretsmanager create-secret \
    --name "stargate-sandbox/litellm-master-key" \
    --secret-string "$LITELLM_MASTER_KEY" \
    --region ${AWS_REGION}

# Grafana Admin Password
aws secretsmanager create-secret \
    --name "stargate-sandbox/grafana-admin-password" \
    --secret-string "$GRAFANA_ADMIN_PASSWORD" \
    --region ${AWS_REGION}

# Langfuse NextAuth Secret
aws secretsmanager create-secret \
    --name "stargate-sandbox/langfuse-nextauth-secret" \
    --secret-string "$LANGFUSE_NEXTAUTH_SECRET" \
    --region ${AWS_REGION}

# Langfuse Salt
aws secretsmanager create-secret \
    --name "stargate-sandbox/langfuse-salt" \
    --secret-string "$LANGFUSE_SALT" \
    --region ${AWS_REGION}
```

### 2.3 Verifica Secrets

```bash
aws secretsmanager list-secrets \
    --region ${AWS_REGION} \
    --query "SecretList[?starts_with(Name, 'stargate-sandbox')].Name" \
    --output table
```

**Output atteso:**
```
--------------------------------------------
|              ListSecrets                 |
+------------------------------------------+
|  stargate-sandbox/admin-header-secret    |
|  stargate-sandbox/grafana-admin-password |
|  stargate-sandbox/langfuse-nextauth-secret|
|  stargate-sandbox/langfuse-salt          |
|  stargate-sandbox/litellm-master-key     |
|  stargate-sandbox/origin-verify-secret   |
+------------------------------------------+
```

---

## Fase 3: Bedrock Model Access (10 min)

### 3.1 Richiedi Accesso Modelli

```bash
# Vai alla console AWS Bedrock
echo "https://${AWS_REGION}.console.aws.amazon.com/bedrock/home?region=${AWS_REGION}#/modelaccess"
```

**Modelli da abilitare:**
- [ ] `anthropic.claude-haiku-4-5-20251001-v1:0`
- [ ] `anthropic.claude-sonnet-4-5-20250929-v1:0`
- [ ] `anthropic.claude-opus-4-5-20251101-v1:0`

**Nota:** L'approvazione può richiedere alcuni minuti.

### 3.2 Verifica Accesso

```bash
aws bedrock list-foundation-models \
    --region ${AWS_REGION} \
    --query "modelSummaries[?contains(modelId, 'claude')].modelId" \
    --output table
```

---

## Fase 4: Configurazione Terraform (15 min)

### 4.1 Aggiorna Backend

Modifica `infra/terraform/environments/sandbox/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "stargate-llm-gateway-terraform-state-ACCOUNT_ID"  # <-- Sostituisci
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "stargate-llm-gateway-terraform-locks"
  }
}
```

### 4.2 Crea terraform.tfvars

```bash
cd infra/terraform/environments/sandbox

cat > terraform.tfvars << 'EOF'
# AWS Region
aws_region = "us-east-1"

# VPC Configuration
create_vpc          = true
vpc_cidr            = "10.20.0.0/16"
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnet_cidrs = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
public_subnet_cidrs  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]

# Use NAT Gateway (not NAT Instance)
use_nat_gateway = true

# Secrets Manager ARNs (verranno popolati dopo creazione)
origin_verify_secret_arn          = ""  # <-- Da compilare
admin_header_secret_arn           = ""  # <-- Da compilare
litellm_master_key_secret_arn     = ""  # <-- Da compilare
grafana_admin_password_secret_arn = ""  # <-- Da compilare
langfuse_public_key_secret_arn    = ""  # <-- Opzionale
langfuse_secret_key_secret_arn    = ""  # <-- Opzionale
langfuse_database_url_secret_arn  = ""  # <-- Creato da RDS module
langfuse_nextauth_secret_arn      = ""  # <-- Da compilare
langfuse_salt_secret_arn          = ""  # <-- Da compilare

# WAF
enable_waf             = true
enable_waf_bot_control = true
waf_rate_limit         = 1000

# RDS
rds_instance_class          = "db.r6g.large"
rds_allocated_storage       = 100
rds_multi_az                = true
rds_backup_retention_period = 7

# LiteLLM
litellm_task_cpu      = 2048
litellm_task_memory   = 4096
litellm_desired_count = 2
litellm_min_capacity  = 2
litellm_max_capacity  = 6

# Grafana
grafana_image         = "grafana/grafana-oss:11.4.0"
grafana_task_cpu      = 512
grafana_task_memory   = 1024
grafana_desired_count = 2

# Langfuse
langfuse_task_cpu      = 1024
langfuse_task_memory   = 2048
langfuse_desired_count = 2

# Victoria Metrics
victoria_metrics_task_cpu      = 512
victoria_metrics_task_memory   = 1024
victoria_metrics_retention_days = 30
EOF
```

### 4.3 Ottieni Secret ARNs

```bash
# Ottieni ARNs e aggiorna tfvars
echo "origin_verify_secret_arn          = \"$(aws secretsmanager describe-secret --secret-id stargate-sandbox/origin-verify-secret --query ARN --output text --region ${AWS_REGION})\""
echo "admin_header_secret_arn           = \"$(aws secretsmanager describe-secret --secret-id stargate-sandbox/admin-header-secret --query ARN --output text --region ${AWS_REGION})\""
echo "litellm_master_key_secret_arn     = \"$(aws secretsmanager describe-secret --secret-id stargate-sandbox/litellm-master-key --query ARN --output text --region ${AWS_REGION})\""
echo "grafana_admin_password_secret_arn = \"$(aws secretsmanager describe-secret --secret-id stargate-sandbox/grafana-admin-password --query ARN --output text --region ${AWS_REGION})\""
echo "langfuse_nextauth_secret_arn      = \"$(aws secretsmanager describe-secret --secret-id stargate-sandbox/langfuse-nextauth-secret --query ARN --output text --region ${AWS_REGION})\""
echo "langfuse_salt_secret_arn          = \"$(aws secretsmanager describe-secret --secret-id stargate-sandbox/langfuse-salt --query ARN --output text --region ${AWS_REGION})\""
```

---

## Fase 5: Deploy Terraform (45-60 min)

### 5.1 Init

```bash
cd infra/terraform/environments/sandbox
terraform init
```

### 5.2 Validate

```bash
terraform validate
```

### 5.3 Plan

```bash
terraform plan -out=tfplan
```

**Verifica output:**
- ~50-60 risorse da creare
- Nessun errore
- Review risorse critiche (RDS, ECS, CloudFront)

### 5.4 Apply

```bash
terraform apply tfplan
```

**Tempo stimato:** 30-45 minuti (RDS Multi-AZ è il più lento)

### 5.5 Salva Output

```bash
terraform output > sandbox-outputs.txt
```

---

## Fase 6: Post-Deployment (20 min)

### 6.1 Verifica Servizi

```bash
# Ottieni CloudFront URL
CF_URL=$(terraform output -raw cloudfront_url)
echo "CloudFront URL: $CF_URL"

# Test health endpoint
curl -s "$CF_URL/health/liveliness" | jq .

# Test models endpoint (richiede API key)
curl -s "$CF_URL/v1/models" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq .
```

### 6.2 Verifica Sicurezza

```bash
# Ottieni ALB DNS
ALB_DNS=$(terraform output -raw alb_dns_name)

# Test accesso diretto ALB (deve ritornare 403)
curl -s "http://$ALB_DNS" | jq .
# Output atteso: {"error": {"code": "DIRECT_ACCESS_FORBIDDEN", ...}}

# Test con header corretto (deve funzionare)
curl -s "http://$ALB_DNS" \
    -H "X-Origin-Verify: $ORIGIN_VERIFY_SECRET" | head -20
```

### 6.3 Verifica Dashboard

```bash
# Grafana
echo "Grafana: $CF_URL/grafana"
echo "User: admin"
echo "Password: $GRAFANA_ADMIN_PASSWORD"

# Langfuse
echo "Langfuse: $CF_URL:8080"
```

### 6.4 Crea Primo Utente

```bash
# Crea utente test
curl -X POST "$CF_URL/user/new" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "X-Admin-Secret: $ADMIN_HEADER_SECRET" \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "test@company.com",
        "max_budget": 50.0,
        "budget_duration": "monthly",
        "models": ["claude-haiku-4-5", "claude-sonnet-4-5"]
    }'

# Genera API key per utente
curl -X POST "$CF_URL/key/generate" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "X-Admin-Secret: $ADMIN_HEADER_SECRET" \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "test@company.com",
        "key_alias": "test-key",
        "duration": "30d"
    }'
```

### 6.5 Test LLM Call

```bash
# Usa la key generata
TEST_KEY="sk-xxxxx"  # <-- Dalla risposta precedente

curl -X POST "$CF_URL/v1/chat/completions" \
    -H "Authorization: Bearer $TEST_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "claude-haiku-4-5",
        "messages": [{"role": "user", "content": "Hello, this is a test!"}],
        "max_tokens": 50
    }'
```

---

## Checklist Finale

### Account Setup
- [ ] S3 bucket per Terraform state creato
- [ ] DynamoDB table per locking creato
- [ ] IAM user per CI/CD creato (opzionale)

### Secrets
- [ ] origin-verify-secret creato
- [ ] admin-header-secret creato
- [ ] litellm-master-key creato
- [ ] grafana-admin-password creato
- [ ] langfuse-nextauth-secret creato
- [ ] langfuse-salt creato
- [ ] Secrets salvati in posto sicuro

### Bedrock
- [ ] Claude Haiku 4.5 abilitato
- [ ] Claude Sonnet 4.5 abilitato (opzionale)
- [ ] Claude Opus 4.5 abilitato (opzionale)

### Terraform
- [ ] backend.tf aggiornato con account ID
- [ ] terraform.tfvars creato con ARNs
- [ ] terraform init completato
- [ ] terraform plan senza errori
- [ ] terraform apply completato

### Verifica
- [ ] CloudFront risponde
- [ ] ALB blocca accesso diretto (403)
- [ ] Health endpoint OK
- [ ] Grafana accessibile
- [ ] Langfuse accessibile
- [ ] LLM call funziona

---

## Troubleshooting

### Terraform Init Fallisce

```bash
# Verifica bucket esiste
aws s3 ls s3://stargate-llm-gateway-terraform-state-${AWS_ACCOUNT_ID}

# Verifica DynamoDB table
aws dynamodb describe-table --table-name stargate-llm-gateway-terraform-locks
```

### Bedrock Access Denied

```bash
# Verifica model access
aws bedrock get-foundation-model-availability \
    --model-id anthropic.claude-haiku-4-5-20251001-v1:0 \
    --region us-east-1
```

### ECS Task Non Parte

```bash
# Check task logs
aws logs tail /ecs/stargate-llm-gateway-sandbox/litellm --follow

# Check task status
aws ecs describe-tasks \
    --cluster stargate-llm-gateway-sandbox \
    --tasks $(aws ecs list-tasks --cluster stargate-llm-gateway-sandbox --query 'taskArns[0]' --output text)
```

### RDS Connection Issues

```bash
# Verifica security group
aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=*rds*" \
    --query "SecurityGroups[].{Name:GroupName,Ingress:IpPermissions}"
```

---

## Costi Stimati

| Componente | Costo Mensile |
|------------|---------------|
| ECS Fargate (LiteLLM 2x 2vCPU) | ~$120 |
| ECS Fargate (Grafana 2x) | ~$30 |
| ECS Fargate (Victoria 1x) | ~$15 |
| ECS Fargate (Langfuse 2x) | ~$60 |
| RDS r6g.large Multi-AZ | ~$180 |
| NAT Gateway | ~$35 |
| EFS (50 GB) | ~$15 |
| CloudFront | ~$5 |
| WAF (Bot Control) | ~$15 |
| **Totale Fisso** | **~$475/mese** |
| Bedrock usage | Pay-per-use |

---

## Contatti

In caso di problemi:
- Documentazione: `docs/security/sandbox-*.md`
- Architettura: `docs/architecture/sandbox-enterprise-architecture.md`
