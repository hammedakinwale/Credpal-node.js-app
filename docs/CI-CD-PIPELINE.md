# CI/CD Pipeline Deployment Guide

This guide explains how the updated GitHub Actions CI/CD pipeline automatically deploys your credpal application to AWS ECS.

## Overview

The CI/CD pipeline now performs automated end-to-end deployment:

```
Code Push (main branch)
    ↓
Run Tests (Jest, PostgreSQL)
    ↓
Build Docker Image
    ↓
Push to ECR
    ↓
Security Scan (Trivy)
    ↓
Deploy to Staging (with task.json)
    ↓
Deploy to Production (with task.json)
```

## Pipeline Stages

### 1. Test (Runs on all pushes)

**Trigger**: Any push to any branch  
**Actions**:
- Set up Node.js 20
- Install dependencies
- Run linter
- Run Jest tests with PostgreSQL
- Upload coverage to Codecov

**Duration**: 2-3 minutes

```yaml
npm test -- --coverage
```

### 2. Build & Push (Runs on main branch pushes only)

**Trigger**: Push to main branch  
**Requires**: Test stage to pass  
**Actions**:
- Configure AWS credentials via OIDC
- Login to Amazon ECR
- Build Docker image
- Push to ECR with commit SHA tag
- Push to ECR with `latest` tag

**Result**: Image available at:
```
$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/credpal:latest
$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/credpal:$COMMIT_SHA
```

### 3. Security Scan (Runs on all pushes)

**Trigger**: All pushes  
**Tool**: Trivy  
**Actions**:
- Scan filesystem for vulnerabilities
- Generate SARIF report
- Upload to GitHub Security tab

**Duration**: 1-2 minutes

### 4. Deploy to Staging (Runs on main branch)

**Trigger**: Push to main branch  
**Requires**: Build & Push stage to pass  
**Environment**: Staging (requires approval in some workflows)  
**Actions**:
1. **Replace placeholders in task.json**:
   - `ACCOUNT_ID` → AWS account ID
   - `RDS_ENDPOINT` → RDS endpoint
   - `REDIS_ENDPOINT` → Redis endpoint
   - `credpal/db/credentials` → Secrets Manager ARN

2. **Register task definition** with AWS ECS

3. **Update service** to use new task definition

4. **Wait for stabilization** (2-5 minutes)

**Task Definition Updates**:
```bash
sed -i "s|ACCOUNT_ID|${{ secrets.AWS_ACCOUNT_ID }}|g" task.json
sed -i "s|RDS_ENDPOINT|${{ secrets.RDS_ENDPOINT }}|g" task.json
sed -i "s|REDIS_ENDPOINT|${{ secrets.REDIS_ENDPOINT }}|g" task.json
sed -i "s|credpal/db/credentials|${{ secrets.DB_SECRET_ARN }}|g" task.json
```

**Duration**: 5-10 minutes (including wait)

### 5. Deploy to Production (Runs on main branch)

**Trigger**: Push to main branch  
**Requires**: Deploy to Staging stage to pass  
**Environment**: Production (requires approval)  
**Actions**:
- Replace placeholders (same as staging)
- Register new task definition
- Update ECS service for production
- Wait for stabilization

**Duration**: 5-10 minutes

## GitHub Secrets Required

The pipeline requires these secrets to be configured:

| Secret | Purpose | Example |
|--------|---------|---------|
| `AWS_ROLE_TO_ASSUME` | OIDC role for AWS auth | `arn:aws:iam::123456789012:role/github-actions-credpal-role` |
| `AWS_ACCOUNT_ID` | Your AWS account ID | `123456789012` |
| `RDS_ENDPOINT` | RDS database endpoint | `credpal-db.abc123.us-east-1.rds.amazonaws.com` |
| `REDIS_ENDPOINT` | ElastiCache Redis endpoint | `credpal-redis.abc123.ng.0001.use1.cache.amazonaws.com` |
| `DB_SECRET_ARN` | Secrets Manager ARN for DB creds | `arn:aws:secretsmanager:us-east-1:123456789012:secret:credpal/db/credentials-abc123` |

### Set Up Secrets

**Automated Setup** (Recommended):
```bash
chmod +x scripts/setup-github-secrets.sh
./scripts/setup-github-secrets.sh
```

**Manual Setup**:
See [docs/GITHUB-SECRETS-SETUP.md](GITHUB-SECRETS-SETUP.md) for detailed instructions.

## Deployment Flow

### Local Development
```
1. Make code changes
2. Test locally: npm test
3. Commit and push: git push origin main
```

### Automatic Pipeline Execution
```
GitHub detects push to main
    ↓
Run test job (all branches)
    ↓
Run build-and-push job (main only)
    ├─ Configure AWS credentials (OIDC)
    ├─ Login to ECR
    ├─ Build Docker image
    ├─ Push with commit SHA and latest tags
    └─ Generate image URI
    ↓
Run security-scan job
    ├─ Scan with Trivy
    └─ Upload SARIF report
    ↓
Run deploy-staging job (main only)
    ├─ Replace task.json placeholders
    ├─ Register task definition
    ├─ Update ECS service
    └─ Wait for service stabilization
    ↓
Run deploy-production job (main only)
    ├─ Replace task.json placeholders
    ├─ Register task definition
    ├─ Update ECS service
    └─ Wait for service stabilization
```

## Placeholder Replacement

The pipeline uses `sed` to replace placeholders in `.aws/task.json`:

### Example Task Definition
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

### Replacement Process
```bash
# Get values from GitHub secrets
ACCOUNT_ID=${{ secrets.AWS_ACCOUNT_ID }}
RDS_ENDPOINT=${{ secrets.RDS_ENDPOINT }}
REDIS_ENDPOINT=${{ secrets.REDIS_ENDPOINT }}
DB_SECRET_ARN=${{ secrets.DB_SECRET_ARN }}

# Copy original task.json
cp .aws/task.json /tmp/task.json

# Replace placeholders
sed -i "s|ACCOUNT_ID|$ACCOUNT_ID|g" /tmp/task.json
sed -i "s|RDS_ENDPOINT|$RDS_ENDPOINT|g" /tmp/task.json
sed -i "s|REDIS_ENDPOINT|$REDIS_ENDPOINT|g" /tmp/task.json
sed -i "s|credpal/db/credentials|$DB_SECRET_ARN|g" /tmp/task.json

# Result: Ready for ECS registration
```

## Viewing Workflow Status

### GitHub Web UI

1. Go to your repository
2. Click **Actions** tab
3. View running or completed workflows
4. Click workflow name to see details
5. Click job name to see logs

### GitHub CLI

```bash
# List recent workflows
gh run list

# View details of a run
gh run view <RUN_ID>

# View logs
gh run view <RUN_ID> --log

# Stream logs in real-time
gh run view <RUN_ID> --log --tail

# Check status
gh run view <RUN_ID> --json status,conclusion
```

### Common Commands

```bash
# Get latest run status
gh run list --limit 1

# Get all runs for current branch
gh run list --branch main

# Get run with specific status
gh run list --status completed
gh run list --status in_progress

# Get logs for failed run
gh run list --status failure | head -1
gh run view <RUN_ID> --log
```

## Troubleshooting

### Test Stage Fails

**Problem**: Tests fail in CI but pass locally

**Debug**:
```bash
# Check GitHub logs for error details
gh run view <RUN_ID> --log

# Reproduce locally
npm ci  # Clean install (like CI)
npm test -- --coverage

# Check database connections
npm test -- --verbose
```

**Common Causes**:
- Different Node.js version
- PostgreSQL connection issues
- Missing environment variables
- Module caching issues

### Build & Push Fails

**Problem**: Docker build or ECR push fails

**Debug**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Build locally
docker build -t credpal:latest .

# Check ECR repository
aws ecr describe-repositories --repository-names credpal

# Check ECR permissions
aws ecr get-authorization-token
```

**Common Causes**:
- AWS OIDC role misconfigured
- ECR repository doesn't exist
- Docker layer caching issues
- Dockerfile errors

### Deployment Fails

**Problem**: Task definition registration or service update fails

**Debug**:
```bash
# Check task definition JSON is valid
jq . .aws/task.json

# Check secrets are set
gh secret list

# Verify ECS resources exist
aws ecs describe-clusters --clusters credpal-cluster
aws ecs describe-services --cluster credpal-cluster --services credpal-service

# Check CloudWatch logs
aws logs tail /ecs/credpal --follow
```

**Common Causes**:
- Invalid JSON after placeholder replacement
- Missing GitHub secrets
- ECS cluster/service doesn't exist
- IAM role permissions issue

### Service Doesn't Stabilize

**Problem**: Tasks fail to become healthy or service times out

**Debug**:
```bash
# Check task status
aws ecs list-tasks --cluster credpal-cluster
aws ecs describe-tasks --cluster credpal-cluster --tasks <TASK_ARN>

# Check logs
aws logs tail /ecs/credpal --follow

# Check service events
aws ecs describe-services --cluster credpal-cluster --services credpal-service | jq '.services[0].events'

# Check health check endpoint
curl http://<ALB_DNS>/health
```

**Common Causes**:
- Health check endpoint not responding
- Database/Redis connection failed
- Security group blocking traffic
- Task definition has wrong image

## Monitoring Deployments

### Real-time Monitoring

```bash
# Watch workflow in real-time
gh run watch <RUN_ID>

# Stream logs
gh run view <RUN_ID> --log --tail

# Monitor ECS deployment
aws ecs wait services-stable \
  --cluster credpal-cluster \
  --services credpal-service

# Watch CloudWatch logs
aws logs tail /ecs/credpal --follow
```

### Post-Deployment Checks

```bash
# Get deployment status
aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service \
  | jq '.services[0] | {status, desiredCount, runningCount}'

# Check recent task definitions
aws ecs list-task-definitions --family-prefix credpal \
  --query 'taskDefinitionArns | [-2:]'

# Verify application health
ALB_DNS=$(terraform output -raw load_balancer_dns)
curl http://$ALB_DNS/health
```

## Rollback Procedure

If a deployment causes issues:

```bash
# Get previous task definition
PREV_TASK=$(aws ecs list-task-definitions \
  --family-prefix credpal \
  --query 'taskDefinitionArns | [-2]' \
  --output text)

# Rollback service
aws ecs update-service \
  --cluster credpal-cluster \
  --service credpal-service \
  --task-definition $PREV_TASK \
  --force-new-deployment

# Monitor rollback
aws ecs wait services-stable \
  --cluster credpal-cluster \
  --services credpal-service
```

## Pipeline Configuration Files

### Workflow Definition
**File**: `.github/workflows/ci-cd.yml`  
**Size**: ~250 lines  
**Triggers**: Pushes to main and pull requests  
**Jobs**: 5 stages (test, build, scan, deploy-staging, deploy-production)

### Task Definition Template
**File**: `.aws/task.json`  
**Size**: ~93 lines  
**Placeholders**: 4 (ACCOUNT_ID, RDS_ENDPOINT, REDIS_ENDPOINT, DB Secret ARN)  
**Updated by**: CI/CD pipeline with `sed` commands

### Secrets Configuration
**Location**: GitHub repository Settings → Secrets  
**Secrets**: 5 required (AWS_ROLE_TO_ASSUME, AWS_ACCOUNT_ID, RDS_ENDPOINT, REDIS_ENDPOINT, DB_SECRET_ARN)  
**Setup**: Use `scripts/setup-github-secrets.sh`

## Performance Metrics

| Stage | Average Duration | Notes |
|-------|------------------|-------|
| Test | 2-3 min | Includes DB setup and cleanup |
| Build & Push | 3-4 min | Image size ~50MB, ECR push varies |
| Security Scan | 1-2 min | Trivy vulnerability scan |
| Deploy Staging | 5-10 min | Includes service stabilization wait |
| Deploy Production | 5-10 min | Includes service stabilization wait |
| **Total** | **15-25 min** | From push to production |

## Cost Implications

- **ECR Storage**: ~50MB per image, $0.50/month for 100 images
- **ECS Tasks**: Pay per task hour (Fargate pricing)
- **Data Transfer**: Out to GitHub, CloudWatch logs
- **Build Time**: GitHub Actions minutes (included in free tier for public repos)

## Best Practices

✅ **DO**
- Push only tested code to main
- Keep task.json placeholders consistent
- Rotate secrets regularly
- Monitor CloudWatch logs after deployment
- Use semantic versioning in commits
- Tag releases in Git

❌ **DON'T**
- Push work-in-progress to main
- Commit secrets to repository
- Modify task.json values directly (use placeholders)
- Ignore failed tests
- Deploy frequently without monitoring
- Use same secrets for staging and production

## Next Steps

1. **Set up secrets**: `./scripts/setup-github-secrets.sh`
2. **Push to main**: `git push origin main`
3. **Monitor workflow**: `gh run list`
4. **Watch deployment**: `aws logs tail /ecs/credpal --follow`
5. **Verify application**: `curl http://$ALB_DNS/health`

---

**Your CI/CD pipeline is ready for automated deployments! 🚀**
