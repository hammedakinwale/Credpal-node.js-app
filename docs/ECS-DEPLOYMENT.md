# ECS Deployment Guide for credpal

This guide walks you through deploying the credpal application to AWS ECS Fargate.

## Prerequisites

Before deploying, ensure you have:

1. **AWS Account**: Active AWS account with appropriate permissions
2. **AWS CLI**: Version 2.x installed and configured with credentials
3. **Terraform State**: Successfully applied Terraform configuration (infrastructure deployed)
4. **Docker Image**: Built and pushed to ECR repository
5. **GitHub Actions**: CI/CD pipeline configured and completed at least one successful run

### Verification Checklist

```bash
# Check AWS CLI
aws --version
aws sts get-caller-identity

# Check Terraform outputs are available
terraform output

# Verify ECR repository exists
aws ecr describe-repositories --repository-names credpal

# Verify ECS cluster exists
aws ecs describe-clusters --clusters credpal-cluster

# Verify RDS and ElastiCache endpoints
aws rds describe-db-instances --db-instance-identifier credpal-db
aws elasticache describe-replication-groups --replication-group-id credpal-redis
```

## Deployment Methods

### Method 1: Automated Deployment Script (Recommended)

The easiest way to deploy is using the provided deployment script:

```bash
chmod +x scripts/deploy-ecs.sh
./scripts/deploy-ecs.sh
```

This script automatically:
- Retrieves your AWS account ID
- Fetches RDS and Redis endpoints from Terraform
- Updates `.aws/task.json` with actual values
- Registers the task definition with ECS
- Updates the ECS service to use the new task definition
- Waits for the service to stabilize
- Shows you the application endpoint

### Method 2: Step-by-Step Manual Deployment

If you prefer to deploy manually or the script doesn't work, follow these steps:

#### Step 1: Get Infrastructure Details

```bash
# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $AWS_ACCOUNT_ID"

# Get RDS Endpoint (from Terraform output)
RDS_ENDPOINT=$(terraform output -raw rds_address)
echo "RDS Endpoint: $RDS_ENDPOINT"

# Get Redis Endpoint (from Terraform output)
REDIS_ENDPOINT=$(terraform output -raw elasticache_endpoint)
echo "Redis Endpoint: $REDIS_ENDPOINT"

# Get ECR Repository URL (from Terraform output)
ECR_REPO_URL=$(terraform output -raw ecr_repository_url)
echo "ECR URL: $ECR_REPO_URL"
```

#### Step 2: Update Task Definition

Edit `.aws/task.json` and replace the placeholders:

```bash
# Using sed (works on both macOS and Linux)
sed -i.bak "s|ACCOUNT_ID|$AWS_ACCOUNT_ID|g" .aws/task.json
sed -i.bak "s|RDS_ENDPOINT|$RDS_ENDPOINT|g" .aws/task.json
sed -i.bak "s|REDIS_ENDPOINT|$REDIS_ENDPOINT|g" .aws/task.json

# Verify the updates
cat .aws/task.json | grep -E "ecr.ecr|RDS|REDIS"
```

Or edit the file manually and replace:
- `ACCOUNT_ID` with your actual AWS account ID
- `RDS_ENDPOINT` with your RDS endpoint (e.g., `credpal-db.abc123.us-east-1.rds.amazonaws.com`)
- `REDIS_ENDPOINT` with your ElastiCache endpoint (e.g., `credpal-redis.abc123.ng.0001.use1.cache.amazonaws.com`)

#### Step 3: Register Task Definition

```bash
TASK_DEF_RESPONSE=$(aws ecs register-task-definition \
  --cli-input-json file://.aws/task.json \
  --region us-east-1)

# Extract task definition ARN
TASK_DEF_ARN=$(echo $TASK_DEF_RESPONSE | jq -r '.taskDefinition.taskDefinitionArn')
echo "Registered task definition: $TASK_DEF_ARN"
```

#### Step 4: Update ECS Service

```bash
aws ecs update-service \
  --cluster credpal-cluster \
  --service credpal-service \
  --task-definition $TASK_DEF_ARN \
  --force-new-deployment \
  --region us-east-1
```

#### Step 5: Monitor Deployment

```bash
# Watch service status
aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service \
  --region us-east-1 | jq '.services[0] | {status, desiredCount, runningCount}'

# Watch logs
aws logs tail /ecs/credpal --follow

# Check specific task logs
aws ecs list-tasks --cluster credpal-cluster
aws ecs describe-tasks --cluster credpal-cluster --tasks <TASK_ARN> \
  | jq '.tasks[0].containerInstanceArn'
```

## Verification

After deployment, verify the application is running:

### 1. Check Service Status

```bash
aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service \
  --region us-east-1 | jq '.services[0] | {status, desiredCount, runningCount, taskDefinition}'
```

Expected output:
```
{
  "status": "ACTIVE",
  "desiredCount": 2,
  "runningCount": 2,
  "taskDefinition": "arn:aws:ecs:us-east-1:ACCOUNT_ID:task-definition/credpal:1"
}
```

### 2. Check Task Logs

```bash
# Stream logs in real-time
aws logs tail /ecs/credpal --follow

# Or check specific time range
aws logs get-log-events \
  --log-group-name /ecs/credpal \
  --log-stream-name ecs/credpal/TASK_ID
```

Expected log output:
```
✓ Database connection established
✓ Redis connection established
✓ Metrics endpoint listening on port 3000
Server running on port 3000
```

### 3. Test API Endpoints

Get the load balancer DNS:

```bash
ALB_DNS=$(terraform output -raw load_balancer_dns)
echo "Testing: http://$ALB_DNS"

# Test health endpoint
curl http://$ALB_DNS/health
# Expected: {"status":"ok"}

# Test status endpoint
curl http://$ALB_DNS/status
# Expected: {"status":"ok","database":"connected","redis":"connected"}

# Test metrics endpoint
curl http://$ALB_DNS/metrics
# Expected: JSON with metrics data
```

### 4. Check CloudWatch Metrics

View auto-scaling metrics:

```bash
# View CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=credpal-service Name=ClusterName,Value=credpal-cluster \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average

# View memory utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=credpal-service Name=ClusterName,Value=credpal-cluster \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average
```

### 5. Review Auto-Scaling Status

```bash
# List auto-scaling targets
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs \
  --resource-ids service/credpal-cluster/credpal-service

# Check scaling activities
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --resource-id service/credpal-cluster/credpal-service
```

## Troubleshooting

### Service Won't Start

**Symptom**: Tasks fail to start or keep restarting

```bash
# Check task definition
aws ecs describe-task-definition \
  --task-definition credpal:1 | jq '.taskDefinition | {cpu, memory, containerDefinitions}'

# Check task logs
aws ecs list-tasks --cluster credpal-cluster | xargs -I {} \
  aws ecs describe-tasks --cluster credpal-cluster --tasks {} | \
  jq '.tasks[] | {taskArn, lastStatus, stopCode, containerInstanceArn}'

# Check ECS agent logs
aws ecs describe-container-instances --cluster credpal-cluster \
  | jq '.containerInstances[].containerInstanceArn'
```

### Connection Issues

**Symptom**: Application can't connect to RDS or Redis

```bash
# Verify RDS endpoint
nslookup $(terraform output -raw rds_address)

# Verify Redis endpoint  
nslookup $(terraform output -raw elasticache_endpoint)

# Check security groups allow traffic
aws ec2 describe-security-groups --group-ids sg-xxxxxx | jq '.SecurityGroups[0].IpPermissions'

# Test connection from ECS task
aws ecs execute-command \
  --cluster credpal-cluster \
  --task <TASK_ID> \
  --container credpal \
  --interactive \
  --command "curl http://localhost:3000/status"
```

### High Memory Usage

**Symptom**: Tasks use too much memory

```bash
# Check Node.js memory usage
aws ecs execute-command \
  --cluster credpal-cluster \
  --task <TASK_ID> \
  --container credpal \
  --interactive \
  --command "node -e \"console.log(process.memoryUsage())\""

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=credpal-service Name=ClusterName,Value=credpal-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

### Image Not Found

**Symptom**: "Unable to pull image" or "Image not found in registry"

```bash
# Verify image exists in ECR
aws ecr list-images --repository-name credpal

# Verify image is tagged correctly
aws ecr describe-images --repository-name credpal --image-ids imageTag=latest

# Check image digest
aws ecr batch-get-image \
  --repository-name credpal \
  --image-ids imageTag=latest \
  | jq '.images[0].imageId'
```

## Rollback

If you need to revert to a previous task definition:

```bash
# List previous task definitions
aws ecs list-task-definitions --family-prefix credpal | jq '.taskDefinitionArns'

# Update service to use previous version
aws ecs update-service \
  --cluster credpal-cluster \
  --service credpal-service \
  --task-definition credpal:1 \
  --force-new-deployment
```

## Next Steps

After successful deployment:

1. **Monitor Application**: Watch CloudWatch Logs and Metrics
2. **Load Testing**: Run load tests to verify auto-scaling
3. **Blue-Green Deployment**: Set up for safer deployments
4. **Backup Configuration**: Configure RDS automated backups
5. **Cost Optimization**: Review and optimize Fargate task sizes

For more information, see:
- [ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_types.html)
- [Task Definition Parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html)
- [ECS Service Updates](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/update-service.html)
