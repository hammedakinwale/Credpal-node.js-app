# Deployment Guide

## Pre-Deployment Checklist

- [ ] All tests passing
- [ ] Code reviewed and approved
- [ ] Security scan passed (no critical vulnerabilities)
- [ ] Database migrations tested
- [ ] Environment variables configured
- [ ] Secrets Manager secrets configured
- [ ] Backup created
- [ ] Rollback plan documented

## Local Testing

```bash
# Build Docker image
docker build -t credpal-node-app:test .

# Run locally
docker run -d \
  --name credpal-test \
  -p 3000:3000 \
  -e DB_HOST=host.docker.internal \
  credpal-node-app:test

# Test endpoints
curl http://localhost:3000/health
curl http://localhost:3000/status
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{"data": {"test": true}}'

# Stop
docker stop credpal-test
docker rm credpal-test
```

## Staging Deployment

### Using Docker Compose

```bash
# Deploy to staging
docker-compose -f docker-compose.staging.yml up -d

# Run smoke tests
npm test -- --baseURL=http://localhost:3001

# View logs
docker-compose -f docker-compose.staging.yml logs -f app

# Tear down
docker-compose -f docker-compose.staging.yml down
```

### Using AWS

```bash
# Deploy staging stack
cd terraform
terraform apply -var="environment=staging" -auto-approve

# Get endpoint
terraform output staging_app_url

# Verify
curl $(terraform output staging_app_url)/health

# Destroy
terraform destroy -var="environment=staging" -auto-approve
```

## Production Deployment

### Option 1: Blue-Green Deployment (Recommended)

**Benefits**:
- Zero downtime
- Instant rollback
- A/B testing capable
- Easy traffic switching

```bash
# Prerequisites
# - Both blue and green containers exist and are healthy
# - Load balancer configured
# - Database migrations run

# Run deployment
cd scripts
chmod +x blue-green-deploy.sh
./blue-green-deploy.sh

# Monitor
curl https://app.example.com/health
curl https://app.example.com/metrics

# Rollback (if needed)
# Switch traffic back to blue container
docker update --restart=always credpal-app-blue
# Re-route ALB to blue
```

### Option 2: Rolling Deployment

**Benefits**:
- Gradual rollout
- Automatic monitoring
- Natural load testing

```bash
# Prerequisites
# - Auto Scaling Group created via Terraform
# - New launch template version created
# - Health checks configured

# Deploy
cd scripts
chmod +x rolling-deploy.sh
export ASG_NAME=credpal-asg
export AWS_REGION=us-east-1
./rolling-deploy.sh

# Monitor progress
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names credpal-asg \
  --query 'AutoScalingGroups[0].Instances'
```

### Option 3: Terraform Deployment

**Benefits**:
- Infrastructure as Code
- Reproducible
- Version controlled
- Automated

```bash
# Prerequisites
# - AWS credentials configured
# - Terraform state configured
# - Variables set

cd terraform

# Initialize (first time)
terraform init

# Validate
terraform validate

# Plan
terraform plan -out=production.tfplan

# Review plan carefully
cat production.tfplan

# Apply (requires approval in CI/CD)
terraform apply production.tfplan

# Save outputs
terraform output > outputs.json

# Update DNS to point to new ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456 \
  --change-batch file://dns-change.json
```

## Database Migrations

### Before Deployment

```bash
# Backup database
aws rds create-db-snapshot \
  --db-instance-identifier credpal-db \
  --db-snapshot-identifier credpal-db-pre-deploy-$(date +%s)

# Test migration locally
docker-compose down
docker-compose up -d postgres
docker-compose exec postgres psql -U postgres -d credpal -f db/migrate.sql

# Verify migration
docker-compose exec postgres psql -U postgres -d credpal -c "SELECT version();"

# Stop containers
docker-compose down
```

### During Deployment

```bash
# Connect to production database
aws rds-proxy create-db-proxy-endpoint \
  --db-proxy-name credpal-proxy \
  --db-proxy-endpoint-name migrate

# Run migrations
# Option 1: Via SSH to instance
ssh -i key.pem ec2-user@instance-ip
psql -h rds-endpoint -U postgres -d credpal -f migrate.sql

# Option 2: Lambda function
aws lambda invoke \
  --function-name credpal-migration \
  --payload '{"action":"migrate"}' \
  response.json
```

## Post-Deployment

### Verification

```bash
# Check application health
curl https://app.example.com/health

# Check status with DB connection
curl https://app.example.com/status

# View metrics
curl https://app.example.com/metrics

# Check logs
aws logs tail /aws/ec2/credpal-app --follow

# Monitor metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T01:00:00Z \
  --period 300 \
  --statistics Average
```

### Smoke Tests

```bash
# Create test script
cat > smoke-test.sh <<'EOF'
#!/bin/bash

ENDPOINT="https://app.example.com"

# Test health
curl -f $ENDPOINT/health || exit 1

# Test status
curl -f $ENDPOINT/status || exit 1

# Test process
curl -f -X POST $ENDPOINT/process \
  -H "Content-Type: application/json" \
  -d '{"data": {"test": true}}' || exit 1

echo "✓ All smoke tests passed"
EOF

chmod +x smoke-test.sh
./smoke-test.sh
```

## Rollback Procedures

### Quick Rollback (Blue-Green)

```bash
# Switch traffic back to blue container
cd scripts
# Manual ALB target group update
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --targets Id=credpal-app-blue

# Verify
curl https://app.example.com/health
```

### Full Rollback (Terraform)

```bash
cd terraform

# View previous state
terraform state list

# Rollback to previous version
git checkout HEAD~1 -- .
terraform init
terraform plan  # Review carefully
terraform apply -auto-approve
```

### Data Rollback

```bash
# Restore RDS snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier credpal-db-restored \
  --db-snapshot-identifier credpal-db-pre-deploy-xxxxx

# Update DNS to point to restored instance
# Verify data integrity
```

## Disaster Recovery

### RDS Failure

```bash
# Check backup
aws rds describe-db-snapshots \
  --db-instance-identifier credpal-db

# Restore to new instance
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier credpal-db-new \
  --db-snapshot-identifier latest-snapshot

# Update application connection string
# Test thoroughly before switching
```

### Complete Infrastructure Failure

```bash
# Recreate from Terraform
cd terraform
terraform init
terraform apply -auto-approve

# Restore database from snapshot
# Redeploy application
```

## Monitoring & Alerts

### Set Up CloudWatch Alarms

```bash
# Deployment success
aws cloudwatch put-metric-alarm \
  --alarm-name credpal-deployment-failed \
  --alarm-description "Alert on deployment failure" \
  --metric-name DeploymentFailure \
  --namespace AWS/CodeDeploy

# High error rate (> 5%)
aws cloudwatch put-metric-alarm \
  --alarm-name credpal-high-error-rate \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --metric-name 4XXError \
  --namespace AWS/ApplicationELB \
  --period 60 \
  --statistic Sum \
  --threshold 50
```

### Post-Deployment Monitoring

Monitor for:
- CPU utilization
- Memory usage
- Database connections
- Request latency
- Error rates
- Disk usage
- Network I/O

## Troubleshooting

### Application won't start

```bash
# Check logs
aws logs tail /aws/ec2/credpal-app --follow --since 5m

# Check container
docker ps -a
docker logs credpal-app

# Check system resources
docker stats credpal-app
```

### Database connection failing

```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier credpal-db

# Check security groups
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Test connection
psql -h credpal-db.c9akciq32.us-east-1.rds.amazonaws.com \
  -U postgres \
  -d credpal \
  -c "SELECT 1"
```

### High latency

```bash
# Check ALB
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Check instance CPU/memory
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T01:00:00Z \
  --period 300 \
  --statistics Average
```

## Deployment Schedule

Recommended deployment windows:
- **Non-peak hours**: 2-4 AM UTC
- **Staging**: Any time
- **Production**: Coordinated with team
- **Critical fixes**: ASAP with immediate monitoring

## Deployment Approval Process

1. Developer submits PR
2. Code review (2+ approvals)
3. Automated tests pass
4. Security scan passes
5. Manual staging deployment
6. QA verification
7. Production approval (requires team lead)
8. Automated production deployment
9. Post-deployment verification

## Communication

Notify stakeholders:
- Ops team 1 hour before deployment
- Support team of changes
- Customers if user-facing changes
- Post-deployment summary to team
