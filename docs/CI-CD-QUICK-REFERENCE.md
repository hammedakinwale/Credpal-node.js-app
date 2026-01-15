# GitHub Actions CI/CD Quick Reference

## TL;DR - Get Started in 5 Minutes

### 1. Set Up Secrets (2 minutes)
```bash
chmod +x scripts/setup-github-secrets.sh
./scripts/setup-github-secrets.sh
```

### 2. Deploy (Automatic on push)
```bash
git push origin main
```

### 3. Monitor
```bash
gh run list
gh run view <RUN_ID> --log
```

---

## What Happens When You Push to main

```
1. Test Stage (2-3 min)
   └─ npm test with PostgreSQL

2. Build & Push Stage (3-4 min)
   └─ Docker build → ECR push

3. Security Scan Stage (1-2 min)
   └─ Trivy vulnerability scan

4. Deploy to Staging (5-10 min)
   └─ Register task definition → Update ECS service

5. Deploy to Production (5-10 min)
   └─ Register task definition → Update ECS service

Total: 15-25 minutes from push to production
```

---

## Required GitHub Secrets

| Secret | Value | How to Get |
|--------|-------|-----------|
| `AWS_ROLE_TO_ASSUME` | OIDC role ARN | `aws iam get-role --role-name github-actions-credpal-role --query 'Role.Arn'` |
| `AWS_ACCOUNT_ID` | 12-digit account ID | `aws sts get-caller-identity --query 'Account'` |
| `RDS_ENDPOINT` | RDS endpoint | `terraform output -raw rds_address` |
| `REDIS_ENDPOINT` | ElastiCache endpoint | `terraform output -raw elasticache_endpoint` |
| `DB_SECRET_ARN` | Secrets Manager ARN | `aws secretsmanager describe-secret --secret-id credpal/db/credentials --query 'ARN'` |

### Set Secrets Manually
```bash
# Option 1: GitHub CLI
gh secret set AWS_ACCOUNT_ID -b "123456789012"
gh secret set AWS_ROLE_TO_ASSUME -b "arn:aws:iam::123456789012:role/github-actions-credpal-role"
gh secret set RDS_ENDPOINT -b "credpal-db.abc123.us-east-1.rds.amazonaws.com"
gh secret set REDIS_ENDPOINT -b "credpal-redis.abc123.ng.0001.use1.cache.amazonaws.com"
gh secret set DB_SECRET_ARN -b "arn:aws:secretsmanager:us-east-1:123456789012:secret:credpal/db/credentials-abc123"

# Option 2: GitHub Web UI
# Go to Settings → Secrets and variables → Actions → New repository secret
```

### Verify Secrets
```bash
gh secret list
```

---

## Key Files

| File | Purpose |
|------|---------|
| `.github/workflows/ci-cd.yml` | Pipeline definition (5 stages) |
| `.aws/task.json` | ECS task definition template |
| `scripts/setup-github-secrets.sh` | Automated secrets setup |
| `docs/GITHUB-SECRETS-SETUP.md` | Detailed secrets guide |
| `docs/CI-CD-PIPELINE.md` | Full pipeline documentation |

---

## Placeholder Replacement

The pipeline automatically replaces these in `.aws/task.json`:

```
ACCOUNT_ID          → GitHub secret: AWS_ACCOUNT_ID
RDS_ENDPOINT        → GitHub secret: RDS_ENDPOINT
REDIS_ENDPOINT      → GitHub secret: REDIS_ENDPOINT
credpal/db/credentials → GitHub secret: DB_SECRET_ARN
```

Example:
```json
{
  "image": "ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/credpal:latest",
  "environment": [
    {"name": "DB_HOST", "value": "RDS_ENDPOINT"},
    {"name": "REDIS_HOST", "value": "REDIS_ENDPOINT"}
  ],
  "secrets": [
    {"name": "DB_USER", "valueFrom": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:credpal/db/credentials:username::"}
  ]
}
```

Gets converted to:
```json
{
  "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/credpal:latest",
  "environment": [
    {"name": "DB_HOST", "value": "credpal-db.abc123.us-east-1.rds.amazonaws.com"},
    {"name": "REDIS_HOST", "value": "credpal-redis.abc123.ng.0001.use1.cache.amazonaws.com"}
  ],
  "secrets": [
    {"name": "DB_USER", "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:credpal/db/credentials-abc123:username::"}
  ]
}
```

---

## Common Commands

### View Workflow Status
```bash
# List recent workflows
gh run list

# View workflow details
gh run view <RUN_ID>

# Stream logs in real-time
gh run view <RUN_ID> --log --tail

# Watch workflow execution
gh run watch <RUN_ID>
```

### Check Deployment Status
```bash
# ECS service status
aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service \
  | jq '.services[0] | {status, desiredCount: .desiredCount, runningCount: .runningCount}'

# CloudWatch logs
aws logs tail /ecs/credpal --follow

# Task definitions
aws ecs list-task-definitions --family-prefix credpal
```

### Test Application
```bash
# Get ALB DNS
ALB_DNS=$(terraform output -raw load_balancer_dns)

# Health check
curl http://$ALB_DNS/health

# Status check
curl http://$ALB_DNS/status

# Metrics
curl http://$ALB_DNS/metrics | jq
```

### Rollback Deployment
```bash
# Get previous task definition
PREV=$(aws ecs list-task-definitions --family-prefix credpal --query 'taskDefinitionArns | [-2]' --output text)

# Rollback
aws ecs update-service \
  --cluster credpal-cluster \
  --service credpal-service \
  --task-definition $PREV \
  --force-new-deployment
```

---

## Troubleshooting

### Tests Fail
```bash
# Check CI logs
gh run view <RUN_ID> --log

# Run locally
npm ci
npm test

# Check database
npm test -- --verbose
```

### Docker Build Fails
```bash
# Build locally
docker build -t credpal:latest .

# Check ECR
aws ecr describe-repositories --repository-names credpal
```

### Task Definition Registration Fails
```bash
# Validate JSON
jq . .aws/task.json

# Check secrets are set
gh secret list

# Check ECS resources
aws ecs describe-clusters --clusters credpal-cluster
```

### Service Won't Deploy
```bash
# Check logs
aws logs tail /ecs/credpal --follow

# Check service events
aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service \
  | jq '.services[0].events'

# Check task status
aws ecs describe-tasks \
  --cluster credpal-cluster \
  --tasks <TASK_ARN> \
  | jq '.tasks[0] | {lastStatus, containerInstanceArn, stoppedReason}'
```

---

## Performance

| Stage | Duration | Notes |
|-------|----------|-------|
| Test | 2-3 min | PostgreSQL setup included |
| Build & Push | 3-4 min | ~50MB image |
| Security | 1-2 min | Trivy scan |
| Deploy Staging | 5-10 min | Includes stabilization |
| Deploy Production | 5-10 min | Includes stabilization |
| **Total** | **15-25 min** | Full pipeline |

---

## Security

✅ **What's Secured**:
- AWS credentials via OIDC (no long-lived keys)
- GitHub secrets encrypted at rest
- Task definition secrets from AWS Secrets Manager
- ECR access via IAM roles
- TLS encryption for all communications

✅ **Best Practices**:
- Rotate secrets every 90 days
- Use separate secrets for staging/production
- Monitor CloudWatch logs for errors
- Enable audit logging
- Review GitHub Actions permissions monthly

---

## Workflow Stages in Detail

### Test Stage
- **Triggers**: All pushes
- **Duration**: 2-3 minutes
- **Actions**: npm test with real PostgreSQL
- **Failure Impact**: Blocks build stage

### Build & Push Stage
- **Triggers**: main branch only
- **Duration**: 3-4 minutes
- **Actions**: Docker build → ECR push
- **Tags**: commit SHA + latest
- **Failure Impact**: Blocks deployment stages

### Security Scan Stage
- **Triggers**: All pushes
- **Duration**: 1-2 minutes
- **Tool**: Trivy
- **Output**: SARIF report to GitHub Security
- **Failure Impact**: Informational only (doesn't block)

### Deploy to Staging
- **Triggers**: main branch only
- **Duration**: 5-10 minutes
- **Actions**: Task definition registration → ECS update → stabilization
- **Failure Impact**: Blocks production deployment

### Deploy to Production
- **Triggers**: main branch + staging success
- **Duration**: 5-10 minutes
- **Actions**: Task definition registration → ECS update → stabilization
- **Failure Impact**: Critical - production is down

---

## Environment Variables

### Available in All Jobs
```yaml
AWS_REGION: us-east-1
ECR_REPOSITORY: credpal
```

### Available in Build Stage
```yaml
ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
IMAGE_TAG: ${{ github.sha }}
```

### Available in Deploy Stages
```yaml
RDS_ENDPOINT: ${{ secrets.RDS_ENDPOINT }}
REDIS_ENDPOINT: ${{ secrets.REDIS_ENDPOINT }}
DB_SECRET_ARN: ${{ secrets.DB_SECRET_ARN }}
AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID }}
```

---

## Logs Location

| Logs | Location | Access |
|------|----------|--------|
| **GitHub Actions** | GitHub UI or `gh run view` | Real-time |
| **Docker Build** | GitHub Actions logs | During build |
| **Test Output** | GitHub Actions logs | After tests |
| **ECS Task** | CloudWatch `/ecs/credpal` | Real-time streaming |
| **ECS Service Events** | AWS Console | Historical |

---

## Timeline

```
Day 1: Initial setup
  ├─ Install GitHub CLI: gh auth login
  ├─ Run secrets setup: ./scripts/setup-github-secrets.sh
  └─ Verify secrets: gh secret list

Day 2: First deployment
  ├─ Push code: git push origin main
  ├─ Monitor: gh run watch <RUN_ID>
  └─ Verify: curl http://$ALB_DNS/health
```

---

## Next Steps

1. **Setup**: `./scripts/setup-github-secrets.sh`
2. **Verify**: `gh secret list`
3. **Deploy**: `git push origin main`
4. **Monitor**: `gh run list`
5. **Verify**: `curl http://$ALB_DNS/health`

---

**Ready to deploy? Push to main and watch the magic happen! 🚀**
