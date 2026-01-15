# EC2 to ECS Migration Guide

## Overview

The infrastructure has been successfully migrated from EC2-based deployment (using Auto Scaling Groups) to **AWS ECS Fargate**, which is a serverless container orchestration service.

## Key Changes

### Infrastructure Changes

#### Removed
- **EC2 Launch Templates**: No longer provisioning EC2 instances
- **Auto Scaling Groups**: Replaced with ECS Service auto-scaling
- **user_data.sh**: No longer needed for instance initialization
- **EC2 IAM Instance Profile**: Replaced with ECS task roles

#### Added
- **ECS Cluster**: Manages containerized workloads
- **ECS Task Definition**: Defines how Docker containers run (CPU, memory, environment variables)
- **ECS Service**: Runs and maintains desired number of task instances
- **CloudWatch Log Group**: Centralized logging for ECS tasks
- **ECS Task Execution Role**: Allows ECS to pull images and push logs
- **ECS Task Role**: Provides application permissions (Secrets Manager, etc.)

### File Changes

| File | Changes |
|------|---------|
| `terraform/ecs.tf` | **NEW** - Complete ECS infrastructure |
| `terraform/load_balancer.tf` | Removed EC2/ASG resources, changed target group type to "ip" |
| `terraform/iam.tf` | Replaced EC2 roles with ECS task execution and task roles |
| `terraform/security_groups.tf` | Added ECS tasks security group, updated RDS/ElastiCache to reference it |
| `terraform/variables.tf` | Added `ecs_task_cpu`, `ecs_task_memory`, `ecr_repository_url` |
| `terraform/outputs.tf` | Removed ASG output, added ECS cluster/service/task outputs |

## Configuration

### ECR Repository

The ECR repository is now created automatically by Terraform as part of the infrastructure deployment. No manual setup required!

When you run `terraform apply`, it will:
- Create an ECR repository named `credpal`
- Set up image scanning on push
- Configure a lifecycle policy to keep the last 10 images
- Output the repository URL for pushing images

### Task Configuration

ECS Fargate task defaults:
- **CPU**: 512 vCPU (0.5 core)
- **Memory**: 1024 MB (1 GB)
- **Launch Type**: Fargate (serverless)
- **Desired Count**: 2 tasks
- **Min Tasks**: 2
- **Max Tasks**: 4

Adjust these via variables:
```terraform
ecs_task_cpu        = "1024"  # Valid values: 256, 512, 1024, 2048, 4096
ecs_task_memory     = "2048"  # Must match CPU specifications
desired_capacity    = 2
min_size           = 2
max_size           = 4
```

## Deployment Steps

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

### 2. Plan and Apply Infrastructure

```bash
# Review the changes
terraform plan

# Deploy all infrastructure including ECR
terraform apply
```

**Output will include:**
- ECR repository URL
- ECS cluster name
- Load balancer DNS
- RDS endpoint
- ElastiCache endpoint

### 3. Build and Push Docker Image to ECR

```bash
# Get the ECR repository URL from Terraform outputs
ECR_REPO_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=us-east-1

# Get login token
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REPO_URL

# Build Docker image
docker build -t credpal:latest ..

# Tag image for ECR
docker tag credpal:latest $ECR_REPO_URL:latest

# Push to ECR
docker push $ECR_REPO_URL:latest
```

### 4. Verify Deployment

```bash
# Check ECS cluster
aws ecs list-clusters

# Check ECS service
aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service

# Check running tasks
aws ecs list-tasks --cluster credpal-cluster

# Get task details
aws ecs describe-tasks \
  --cluster credpal-cluster \
  --tasks <TASK_ARN>

# View logs
aws logs tail /ecs/credpal --follow
```

## Auto-Scaling

ECS Service uses **Application Auto Scaling** with target tracking policies:

- **CPU Scaling**: Scales when CPU utilization exceeds 70%
- **Memory Scaling**: Scales when memory utilization exceeds 80%

Minimum tasks: 2 (ensures high availability)
Maximum tasks: 4 (cost control)

## Environment Variables

The ECS task definition automatically passes these to the container:

```
NODE_ENV              = production
PORT                  = 3000
DB_HOST               = (RDS endpoint)
DB_PORT               = 5432
DB_NAME               = credpal
DB_USER               = (from Secrets Manager)
DB_PASSWORD           = (from Secrets Manager)
REDIS_HOST            = (ElastiCache endpoint)
REDIS_PORT            = 6379
```

## Logging

All application logs are sent to CloudWatch Logs under `/ecs/credpal`.

View logs in real-time:
```bash
aws logs tail /ecs/credpal --follow
```

## Security Groups

- **ALB**: Accepts traffic on 80 (HTTP) and 443 (HTTPS)
- **ECS Tasks**: Accepts traffic from ALB on port 3000
- **RDS**: Accepts traffic from ECS tasks on port 5432
- **ElastiCache**: Accepts traffic from ECS tasks on port 6379

All egress traffic is allowed to enable external API calls.

## Cost Considerations

### ECS Fargate Pricing
- Pay only for vCPU and memory resources used
- **Example**: 2 tasks × 0.5 vCPU × 1 GB = roughly $30-40/month

### Previous EC2 Pricing
- t3.medium instances: ~$25-30/month per instance
- ECS Fargate is often more cost-effective for variable workloads

## Rollback to EC2 (if needed)

If you need to revert to EC2:
1. Checkout previous Terraform version from git
2. Keep the ECS infrastructure for reference
3. Update load balancer target group type back to "instance"
4. Re-apply Terraform with EC2 resources

## Benefits of ECS Fargate

✅ **No Server Management**: AWS manages the underlying infrastructure
✅ **Auto-Scaling**: Automatic scaling based on CPU/memory metrics
✅ **Cost-Effective**: Pay only for resources used
✅ **Container-Native**: Designed for containerized workloads
✅ **Security**: Network isolation via VPC, encrypted secrets
✅ **Integration**: Seamless with CloudWatch, ECR, Secrets Manager

## Troubleshooting

### Tasks not starting
```bash
# Check service events
aws ecs describe-services --cluster credpal-cluster --services credpal-service

# Check task logs
aws logs tail /ecs/credpal --follow
```

### Image pull failures
- Verify ECR repository exists
- Check image URI is correct
- Ensure IAM permissions allow image pull

### Database connection issues
- Verify RDS security group allows ECS task SG
- Check Secrets Manager secret has correct credentials
- Ensure RDS is accessible from private subnets

### Service stuck in "DEPLOYING"
- Likely a health check failure
- Check logs: `aws logs tail /ecs/credpal --follow`
- Verify application starts on port 3000
- Check health endpoint returns 200 OK

## Next Steps

1. ✅ Review this migration guide
2. ✅ Build and push Docker image to ECR
3. ✅ Update `ecr_repository_url` variable
4. ✅ Run `terraform apply`
5. ✅ Monitor ECS service in AWS Console
6. ✅ Test application endpoint
7. ✅ Set up CloudWatch alarms (optional)
