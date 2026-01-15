# GitHub Secrets Setup Guide

This guide explains how to configure GitHub Actions secrets for the credpal CI/CD pipeline to enable automated ECS deployment.

## Required Secrets

The CI/CD pipeline requires the following secrets to be configured in your GitHub repository:

### 1. AWS_ROLE_TO_ASSUME (Required)
**Purpose**: OIDC role for AWS authentication  
**Format**: ARN  
**Example**: `arn:aws:iam::123456789012:role/github-actions-credpal-role`

**How to get**:
```bash
# From your AWS account
aws iam get-role --role-name github-actions-credpal-role --query 'Role.Arn' --output text
```

### 2. AWS_ACCOUNT_ID (Required)
**Purpose**: Your AWS account ID for ECR image URI  
**Format**: 12-digit number  
**Example**: `123456789012`

**How to get**:
```bash
# From your AWS account
aws sts get-caller-identity --query 'Account' --output text
```

### 3. RDS_ENDPOINT (Required)
**Purpose**: RDS PostgreSQL database endpoint  
**Format**: Full endpoint URL  
**Example**: `credpal-db.abc123xyz.us-east-1.rds.amazonaws.com`

**How to get**:
```bash
# From Terraform outputs
terraform output -raw rds_address

# Or from AWS CLI
aws rds describe-db-instances --db-instance-identifier credpal-db \
  --query 'DBInstances[0].Endpoint.Address' --output text
```

### 4. REDIS_ENDPOINT (Required)
**Purpose**: ElastiCache Redis cluster endpoint  
**Format**: Full endpoint URL  
**Example**: `credpal-redis.abc123xyz.ng.0001.use1.cache.amazonaws.com`

**How to get**:
```bash
# From Terraform outputs
terraform output -raw elasticache_endpoint

# Or from AWS CLI
aws elasticache describe-replication-groups \
  --replication-group-id credpal-redis \
  --query 'ReplicationGroups[0].PrimaryEndpoint.Address' --output text
```

### 5. DB_SECRET_ARN (Required)
**Purpose**: AWS Secrets Manager secret ARN for database credentials  
**Format**: Full ARN  
**Example**: `arn:aws:secretsmanager:us-east-1:123456789012:secret:credpal/db/credentials-abc123`

**How to get**:
```bash
# From AWS CLI
aws secretsmanager describe-secret --secret-id credpal/db/credentials \
  --query 'ARN' --output text

# Or from Terraform outputs
terraform output -raw db_secret_arn
```

## Setting Up Secrets in GitHub

### Method 1: GitHub Web UI (Recommended for beginners)

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. For each secret:
   - **Name**: Exact name (e.g., `AWS_ACCOUNT_ID`)
   - **Secret**: Value from above
   - Click **Add secret**

### Method 2: GitHub CLI

```bash
# Install GitHub CLI (if not already installed)
# macOS: brew install gh
# Then authenticate: gh auth login

# Set each secret
gh secret set AWS_ROLE_TO_ASSUME -b "arn:aws:iam::123456789012:role/github-actions-credpal-role"
gh secret set AWS_ACCOUNT_ID -b "123456789012"
gh secret set RDS_ENDPOINT -b "credpal-db.abc123xyz.us-east-1.rds.amazonaws.com"
gh secret set REDIS_ENDPOINT -b "credpal-redis.abc123xyz.ng.0001.use1.cache.amazonaws.com"
gh secret set DB_SECRET_ARN -b "arn:aws:secretsmanager:us-east-1:123456789012:secret:credpal/db/credentials-abc123"

# Verify secrets were set
gh secret list
```

### Method 3: Terraform (If managing secrets as IaC)

```hcl
# In your Terraform configuration
variable "github_secrets" {
  type = map(string)
  default = {
    AWS_ACCOUNT_ID   = "123456789012"
    RDS_ENDPOINT     = "credpal-db.abc123xyz.us-east-1.rds.amazonaws.com"
    REDIS_ENDPOINT   = "credpal-redis.abc123xyz.ng.0001.use1.cache.amazonaws.com"
    DB_SECRET_ARN    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:credpal/db/credentials-abc123"
  }
}
```

## Automated Setup Script

Save this as `scripts/setup-github-secrets.sh`:

```bash
#!/bin/bash

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Setting up GitHub Actions secrets...${NC}\n"

# Get values from Terraform and AWS
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
AWS_ROLE=$(aws iam get-role --role-name github-actions-credpal-role --query 'Role.Arn' --output text)
RDS_ENDPOINT=$(terraform output -raw rds_address)
REDIS_ENDPOINT=$(terraform output -raw elasticache_endpoint)
DB_SECRET=$(aws secretsmanager describe-secret --secret-id credpal/db/credentials --query 'ARN' --output text)

echo -e "${GREEN}✓ AWS Account ID: $AWS_ACCOUNT_ID${NC}"
echo -e "${GREEN}✓ AWS Role: $AWS_ROLE${NC}"
echo -e "${GREEN}✓ RDS Endpoint: $RDS_ENDPOINT${NC}"
echo -e "${GREEN}✓ Redis Endpoint: $REDIS_ENDPOINT${NC}"
echo -e "${GREEN}✓ DB Secret ARN: $DB_SECRET${NC}\n"

# Set secrets using GitHub CLI
echo "Setting secrets in GitHub..."

gh secret set AWS_ROLE_TO_ASSUME -b "$AWS_ROLE"
gh secret set AWS_ACCOUNT_ID -b "$AWS_ACCOUNT_ID"
gh secret set RDS_ENDPOINT -b "$RDS_ENDPOINT"
gh secret set REDIS_ENDPOINT -b "$REDIS_ENDPOINT"
gh secret set DB_SECRET_ARN -b "$DB_SECRET"

echo -e "\n${GREEN}✓ All secrets configured!${NC}"
echo -e "\nVerify with:"
echo "gh secret list"
```

Run it:
```bash
chmod +x scripts/setup-github-secrets.sh
./scripts/setup-github-secrets.sh
```

## Verify Secrets Are Set

### Using GitHub CLI
```bash
gh secret list
```

Expected output:
```
AWS_ACCOUNT_ID          Updated 2024-01-15
AWS_ROLE_TO_ASSUME      Updated 2024-01-15
DB_SECRET_ARN           Updated 2024-01-15
REDIS_ENDPOINT          Updated 2024-01-15
RDS_ENDPOINT            Updated 2024-01-15
```

### Using GitHub Web UI
1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Verify all 5 secrets are listed

### Using GitHub API
```bash
# List all secrets (names only, values are hidden)
gh api repos/YOUR_USERNAME/credpal-sample/actions/secrets
```

## How Secrets Are Used in CI/CD

The CI/CD pipeline uses these secrets in the deployment steps:

### In `.github/workflows/ci-cd.yml`

**Staging Deployment**:
```yaml
- name: Update task definition with staging values
  run: |
    sed -i "s|ACCOUNT_ID|${{ secrets.AWS_ACCOUNT_ID }}|g" task.json
    sed -i "s|RDS_ENDPOINT|${{ secrets.RDS_ENDPOINT }}|g" task.json
    sed -i "s|REDIS_ENDPOINT|${{ secrets.REDIS_ENDPOINT }}|g" task.json
    sed -i "s|credpal/db/credentials|${{ secrets.DB_SECRET_ARN }}|g" task.json
```

**Production Deployment**:
```yaml
- name: Update task definition with production values
  run: |
    sed -i "s|ACCOUNT_ID|${{ secrets.AWS_ACCOUNT_ID }}|g" task.json
    sed -i "s|RDS_ENDPOINT|${{ secrets.RDS_ENDPOINT }}|g" task.json
    sed -i "s|REDIS_ENDPOINT|${{ secrets.REDIS_ENDPOINT }}|g" task.json
    sed -i "s|credpal/db/credentials|${{ secrets.DB_SECRET_ARN }}|g" task.json
```

## Security Best Practices

### ✅ DO

- ✅ Use repository secrets for each environment separately
- ✅ Rotate secrets periodically (especially AWS credentials)
- ✅ Use short-lived credentials with OIDC when possible
- ✅ Limit secret access to required workflows
- ✅ Audit secret access in GitHub logs
- ✅ Use distinct secrets for staging vs production

### ❌ DON'T

- ❌ Commit secrets to the repository
- ❌ Use the same secrets for staging and production
- ❌ Store secrets in `.env` files
- ❌ Share secrets via email or Slack
- ❌ Hard-code values in workflow files
- ❌ Use overly permissive IAM roles

## Troubleshooting

### Secret Not Found Error

**Error**: `The secret is not defined`

**Solution**:
```bash
# Check if secret is set
gh secret list | grep AWS_ACCOUNT_ID

# If not found, set it
gh secret set AWS_ACCOUNT_ID -b "$(aws sts get-caller-identity --query 'Account' --output text)"
```

### Deployment Fails with "Unknown Variable"

**Error**: `sed: can't find ACCOUNT_ID in task.json`

**Cause**: Secret variable wasn't replaced properly

**Solution**:
1. Check secret value is not empty:
   ```bash
   gh secret view AWS_ACCOUNT_ID
   ```
2. Verify placeholder in task.json matches exactly:
   ```bash
   grep ACCOUNT_ID .aws/task.json
   ```

### ECR Image Not Pushed

**Error**: `image not found in registry`

**Cause**: `AWS_ACCOUNT_ID` secret might be wrong

**Solution**:
```bash
# Verify account ID is correct
aws sts get-caller-identity --query 'Account' --output text

# Update secret if needed
gh secret set AWS_ACCOUNT_ID -b "$(aws sts get-caller-identity --query 'Account' --output text)"
```

### RDS/Redis Connection Failed

**Error**: `database connection failed` or `redis connection failed`

**Cause**: Endpoints might have changed or are incorrect

**Solution**:
```bash
# Get current endpoints
echo "RDS:" $(terraform output -raw rds_address)
echo "Redis:" $(terraform output -raw elasticache_endpoint)

# Update secrets
gh secret set RDS_ENDPOINT -b "$(terraform output -raw rds_address)"
gh secret set REDIS_ENDPOINT -b "$(terraform output -raw elasticache_endpoint)"
```

## Complete Setup Checklist

- [ ] AWS account credentials configured locally
- [ ] GitHub repository created and cloned
- [ ] GitHub CLI installed and authenticated
- [ ] AWS OIDC role created for GitHub Actions (see GITHUB-SETUP.md)
- [ ] `AWS_ROLE_TO_ASSUME` secret set
- [ ] `AWS_ACCOUNT_ID` secret set
- [ ] `RDS_ENDPOINT` secret set
- [ ] `REDIS_ENDPOINT` secret set
- [ ] `DB_SECRET_ARN` secret set
- [ ] Secrets verified with `gh secret list`
- [ ] Push to main branch to trigger workflow
- [ ] Verify workflow runs successfully
- [ ] Check deployment in AWS console

## Next Steps

1. **Set all 5 secrets** using the method of your choice
2. **Verify secrets** are configured: `gh secret list`
3. **Trigger workflow** by pushing to main branch
4. **Monitor deployment** in GitHub Actions tab
5. **Verify application** is running in ECS

## Related Documentation

- [GITHUB-SETUP.md](./GITHUB-SETUP.md) - OIDC configuration
- [ECS-DEPLOYMENT.md](./ECS-DEPLOYMENT.md) - ECS deployment details
- [CI/CD Workflow](../.github/workflows/ci-cd.yml) - Pipeline configuration

---

**All set! Your GitHub Actions secrets are now ready for automated ECS deployments. 🚀**
