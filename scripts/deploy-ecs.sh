#!/bin/bash

# ECS Deployment Script for credpal
# This script registers the task definition and updates the ECS service

set -e

# Configuration
CLUSTER_NAME="credpal-cluster"
SERVICE_NAME="credpal-service"
REGION="us-east-1"
TASK_DEFINITION_FILE=".aws/task.json"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  ECS Deployment Script for credpal${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo "Warning: jq is not installed. Some features may not work."
    echo "Install with: brew install jq"
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account ID: $ACCOUNT_ID${NC}"

# Get RDS endpoint from Terraform outputs (if terraform state exists)
echo -e "\n${YELLOW}Fetching infrastructure details...${NC}"

if [ -d "terraform" ] && [ -f "terraform/.terraform/terraform.tfstate" ]; then
    RDS_ENDPOINT=$(terraform output -raw rds_address 2>/dev/null || echo "")
    REDIS_ENDPOINT=$(terraform output -raw elasticache_endpoint 2>/dev/null || echo "")
    ECR_REPO_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
else
    echo "Warning: Terraform state not found. Using manual input required."
    read -p "Enter RDS endpoint: " RDS_ENDPOINT
    read -p "Enter Redis endpoint: " REDIS_ENDPOINT
    read -p "Enter ECR repository URL: " ECR_REPO_URL
fi

echo -e "${GREEN}✓ RDS Endpoint: $RDS_ENDPOINT${NC}"
echo -e "${GREEN}✓ Redis Endpoint: $REDIS_ENDPOINT${NC}"
echo -e "${GREEN}✓ ECR Repository URL: $ECR_REPO_URL${NC}"

# Update task.json with actual values
echo -e "\n${YELLOW}Updating task definition with actual values...${NC}"

# Create temporary task.json with substituted values
cp $TASK_DEFINITION_FILE /tmp/task-updated.json

# Use sed to replace placeholders (works on both macOS and Linux)
sed -i.bak "s|ACCOUNT_ID|$ACCOUNT_ID|g" /tmp/task-updated.json
sed -i.bak "s|RDS_ENDPOINT|$RDS_ENDPOINT|g" /tmp/task-updated.json
sed -i.bak "s|REDIS_ENDPOINT|$REDIS_ENDPOINT|g" /tmp/task-updated.json

# Clean up backup files
rm -f /tmp/task-updated.json.bak

echo -e "${GREEN}✓ Task definition updated${NC}"

# Register task definition
echo -e "\n${YELLOW}Registering task definition...${NC}"

TASK_DEF_RESPONSE=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-updated.json \
    --region $REGION)

TASK_DEF_ARN=$(echo $TASK_DEF_RESPONSE | jq -r '.taskDefinition.taskDefinitionArn')
TASK_DEF_REVISION=$(echo $TASK_DEF_RESPONSE | jq -r '.taskDefinition.revision')

echo -e "${GREEN}✓ Task definition registered${NC}"
echo -e "${GREEN}  ARN: $TASK_DEF_ARN${NC}"
echo -e "${GREEN}  Revision: $TASK_DEF_REVISION${NC}"

# Update ECS service
echo -e "\n${YELLOW}Updating ECS service...${NC}"

aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition $TASK_DEF_ARN \
    --force-new-deployment \
    --region $REGION > /dev/null

echo -e "${GREEN}✓ ECS service updated${NC}"

# Wait for service to stabilize (optional)
echo -e "\n${YELLOW}Waiting for service to stabilize (this may take a few minutes)...${NC}"

aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $REGION

echo -e "${GREEN}✓ Service is stable${NC}"

# Get service information
echo -e "\n${YELLOW}Retrieving service status...${NC}"

SERVICE_INFO=$(aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $REGION)

DESIRED_COUNT=$(echo $SERVICE_INFO | jq -r '.services[0].desiredCount')
RUNNING_COUNT=$(echo $SERVICE_INFO | jq -r '.services[0].runningCount')
STATUS=$(echo $SERVICE_INFO | jq -r '.services[0].status')

echo -e "${GREEN}✓ Service Status: $STATUS${NC}"
echo -e "${GREEN}  Desired tasks: $DESIRED_COUNT${NC}"
echo -e "${GREEN}  Running tasks: $RUNNING_COUNT${NC}"

# Get load balancer DNS (if available)
echo -e "\n${YELLOW}Retrieving application endpoint...${NC}"

if command -v terraform &> /dev/null && [ -d "terraform" ]; then
    ALB_DNS=$(terraform output -raw load_balancer_dns 2>/dev/null || echo "")
    if [ -n "$ALB_DNS" ]; then
        echo -e "${GREEN}✓ Application URL: http://$ALB_DNS${NC}"
    fi
fi

# Final summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Deployment successful!${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "Task Definition: ${GREEN}$TASK_DEF_ARN${NC}"
echo -e "Service Status: ${GREEN}$STATUS${NC}"
echo -e "Running Tasks: ${GREEN}$RUNNING_COUNT/$DESIRED_COUNT${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Monitor logs: aws logs tail /ecs/credpal --follow"
echo "2. Check service: aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME"
echo "3. View tasks: aws ecs list-tasks --cluster $CLUSTER_NAME"
echo "4. Test endpoint: curl http://<ALB_DNS>/health"

echo -e "\n${YELLOW}Cleanup:${NC}"
rm -f /tmp/task-updated.json

echo -e "\n${GREEN}Done!${NC}\n"
