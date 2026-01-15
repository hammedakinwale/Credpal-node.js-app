# Production Deployment Checklist

This checklist ensures your application is ready for production deployment to AWS.

## Pre-Deployment Setup (One-Time)

### AWS Account Setup
- [ ] AWS Account created
- [ ] IAM user with appropriate permissions
- [ ] AWS CLI configured locally: `aws configure`
- [ ] AWS region set to us-east-1 (or your preferred region)

### Local Development
- [ ] Node.js 20+ installed
- [ ] Docker installed and running
- [ ] Docker image builds successfully: `docker build -t credpal:latest .`
- [ ] Application runs locally: `docker run -p 3000:3000 credpal:latest`
- [ ] Health endpoint responds: `curl http://localhost:3000/health`

### Repository Setup
- [ ] GitHub repository created and public/private configured
- [ ] Repository cloned locally
- [ ] All code committed and pushed to main branch
- [ ] GitHub Actions workflows visible in repository

### GitHub Actions Configuration
- [ ] AWS OIDC provider created in IAM
- [ ] GitHub Actions role created with ECR/ECS permissions
- [ ] `AWS_ROLE_TO_ASSUME` secret added to GitHub repository
- [ ] Secret value is correct ARN format

### Terraform Preparation
- [ ] AWS credentials configured: `aws sts get-caller-identity`
- [ ] Terraform installed (version 1.0+)
- [ ] `terraform/terraform.tfvars` configured with your values
- [ ] Database passwords generated and secure
- [ ] SSL/TLS enabled setting confirmed

## Deployment Steps

### Step 1: Initialize Infrastructure (Terraform Init)
```bash
cd terraform
terraform init
terraform plan
# Review the plan - should show ~40+ resources
```

- [ ] `terraform init` completes successfully
- [ ] `terraform plan` shows expected resources
- [ ] No errors or warnings about missing variables

### Step 2: Create AWS Resources
```bash
terraform apply
# Review the plan and type 'yes' to confirm
```

Wait for completion (~10 minutes):
- [ ] VPC created
- [ ] RDS instance provisioning
- [ ] ElastiCache cluster provisioning
- [ ] ECS cluster created
- [ ] Load balancer created
- [ ] ECR repository created
- [ ] IAM roles and policies created
- [ ] CloudWatch log group created

**Save the outputs:**
```bash
terraform output -json > terraform-outputs.json
```

- [ ] ECR repository URL noted: `terraform output -raw ecr_repository_url`
- [ ] Load balancer DNS noted: `terraform output -raw load_balancer_dns`
- [ ] RDS endpoint noted: `terraform output -raw rds_address`

### Step 3: Build and Push Docker Image
```bash
# Get ECR repository URL
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=us-east-1

# Authenticate Docker with ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL

# Build image
docker build -t credpal:latest .

# Tag and push
docker tag credpal:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

- [ ] Docker image builds successfully
- [ ] Image pushed to ECR
- [ ] Image visible in ECR console
- [ ] Image scanning passed (no critical vulnerabilities)

### Step 4: Verify ECS Deployment
```bash
# Wait for tasks to start (2-3 minutes)
watch aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service
```

- [ ] Service status shows "ACTIVE"
- [ ] Running count matches desired count
- [ ] Tasks are in "RUNNING" state
- [ ] Health checks passing

### Step 5: Test Application Endpoints
```bash
# Get load balancer DNS
ALB_DNS=$(terraform output -raw load_balancer_dns)

# Test health endpoint
curl http://$ALB_DNS/health

# Test status endpoint
curl http://$ALB_DNS/status

# Test process endpoint
curl -X POST http://$ALB_DNS/process \
  -H "Content-Type: application/json" \
  -d '{"action":"test"}'

# Test metrics endpoint
curl http://$ALB_DNS/metrics
```

- [ ] GET /health returns 200 OK
- [ ] GET /status returns 200 with database info
- [ ] POST /process returns 200 with data stored
- [ ] GET /metrics returns application metrics
- [ ] No 5xx errors in responses

### Step 6: Monitor Logs
```bash
# Stream application logs
aws logs tail /ecs/credpal --follow
```

- [ ] Logs appear in CloudWatch
- [ ] No error messages
- [ ] Request logs show successful responses
- [ ] Database connections established

### Step 7: Configure GitHub Actions (Optional)
If you want automatic deployments:

```bash
# Create OIDC provider (if not exists)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com

# Create GitHub Actions role (see GITHUB-SETUP.md)
```

- [ ] OIDC provider created
- [ ] GitHub Actions role created
- [ ] `AWS_ROLE_TO_ASSUME` secret configured
- [ ] Pipeline tests successfully on next push

### Step 8: Security Verification
```bash
# Check RDS is in private subnet
aws rds describe-db-instances --db-instance-identifier credpal-db \
  --query 'DBInstances[0].[DBSubnetGroup.Subnets[*].SubnetAvailabilityZone]'

# Check security groups
aws ec2 describe-security-groups --filters Name=group-name,Values=credpal-* \
  --query 'SecurityGroups[*].[GroupName,GroupId]'

# Check encryption
aws rds describe-db-instances --db-instance-identifier credpal-db \
  --query 'DBInstances[0].[StorageEncrypted,DBParameterGroups[0].ParameterApplyStatus]'
```

- [ ] RDS in private subnets
- [ ] ElastiCache in private subnets
- [ ] ECS tasks in private subnets
- [ ] ALB in public subnets
- [ ] Database encryption enabled
- [ ] Security group rules minimal (least privilege)

## Post-Deployment Verification

### Database Verification
```bash
# Check database is accessible from application
psql -h $(terraform output -raw rds_address) \
  -U postgres \
  -d credpal \
  -c "SELECT version();"
```

- [ ] Can connect to RDS
- [ ] Database schema initialized
- [ ] Tables created
- [ ] Data persists across deployments

### Cache Verification
```bash
# Check Redis is accessible
redis-cli -h $(aws elasticache describe-cache-clusters \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
  --output text) ping
```

- [ ] Can connect to ElastiCache
- [ ] Redis responding to PING
- [ ] Cache operations working

### Load Balancer Verification
```bash
# Test HTTP → HTTPS redirect
curl -i http://<ALB_DNS>/health | grep -E "Location|301"

# Test HTTPS (if certificate configured)
curl -k https://<ALB_DNS>/health
```

- [ ] HTTP traffic redirected to HTTPS
- [ ] HTTPS certificate valid (if configured)
- [ ] All endpoints accessible through ALB

### Auto-Scaling Verification
```bash
# Check current desired count
aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service \
  --query 'services[0].desiredCount'

# Check auto-scaling target
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs \
  --resource-ids service/credpal-cluster/credpal-service
```

- [ ] Desired count matches min_size (2)
- [ ] Auto-scaling policies active
- [ ] Min/max task counts correct

## Rollback Plan

If deployment encounters issues:

### Option 1: Revert to Previous Image
```bash
# List recent images
aws ecr describe-images --repository-name credpal \
  --query 'sort_by(imageDetails,&imagePushedAt)[-5:].[imagePushedAt,imageTags]'

# Update service with previous image
aws ecs update-service \
  --cluster credpal-cluster \
  --service credpal-service \
  --force-new-deployment
```

### Option 2: Destroy Infrastructure
```bash
terraform destroy  # Requires confirmation
```

- [ ] Backup any critical data before destroy
- [ ] Verify all resources deleted in AWS console

## Monitoring Setup (Post-Deployment)

### CloudWatch Alarms
```bash
# Create CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name credpal-high-cpu \
  --alarm-description "Alert when CPU > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold
```

- [ ] CPU utilization alarm created
- [ ] Memory alarm created (if needed)
- [ ] Error rate alarm created (if needed)
- [ ] Alarm notifications configured

### Logging
```bash
# View recent errors
aws logs filter-log-events \
  --log-group-name /ecs/credpal \
  --filter-pattern "ERROR"
```

- [ ] Error logs monitored
- [ ] Access logs analyzed
- [ ] Performance logs reviewed

## Go-Live Checklist

- [ ] Application tested on production URL
- [ ] All endpoints responding correctly
- [ ] Database connectivity verified
- [ ] Cache layer operational
- [ ] Logs being generated
- [ ] Monitoring and alarms active
- [ ] Rollback procedure tested
- [ ] Team notified of deployment
- [ ] Runbook documented for on-call support

## Maintenance Tasks

### Daily
- [ ] Check CloudWatch alarms
- [ ] Monitor application logs
- [ ] Review error rates

### Weekly
- [ ] Verify backups (RDS snapshots)
- [ ] Review CloudWatch metrics
- [ ] Check security group rules

### Monthly
- [ ] Update base image in Dockerfile
- [ ] Review and update dependencies
- [ ] Security patch assessment
- [ ] Cost analysis

## Support Contacts

| Role | Contact | Escalation |
|------|---------|-----------|
| DevOps Lead | [Name] | [Escalation Process] |
| AWS Architect | [Name] | [Escalation Process] |
| Database Admin | [Name] | [Escalation Process] |
| On-Call | [Rotation] | [Contact Info] |

## Additional Resources

- [ECS-MIGRATION.md](./ECS-MIGRATION.md) - ECS Fargate migration details
- [GITHUB-SETUP.md](./GITHUB-SETUP.md) - GitHub Actions setup
- [docs/DEPLOYMENT.md](./DEPLOYMENT.md) - Detailed deployment guide
- [docs/SECURITY.md](./SECURITY.md) - Security best practices
- [docs/OBSERVABILITY.md](./OBSERVABILITY.md) - Monitoring setup
