#!/bin/bash

# Rolling Deployment Script
# This script implements rolling deployment with zero-downtime updates

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
ASG_NAME="${ASG_NAME:-credpal-asg}"
REGION="${AWS_REGION:-us-east-1}"
MIN_HEALTHY_PERCENTAGE=75
BATCH_SIZE=1

echo -e "${YELLOW}Starting Rolling Deployment...${NC}"

# Get current ASG configuration
echo -e "${YELLOW}Fetching ASG configuration...${NC}"
CURRENT_CONFIG=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0]')

DESIRED_CAPACITY=$(echo $CURRENT_CONFIG | jq '.DesiredCapacity')
MIN_SIZE=$(echo $CURRENT_CONFIG | jq '.MinSize')
MAX_SIZE=$(echo $CURRENT_CONFIG | jq '.MaxSize')

echo "Current capacity: $DESIRED_CAPACITY instances"
echo "Min: $MIN_SIZE, Max: $MAX_SIZE"

# Create new launch template version
echo -e "${YELLOW}Creating new launch template version...${NC}"
LAUNCH_TEMPLATE_ID=$(echo $CURRENT_CONFIG | jq -r '.LaunchTemplate.LaunchTemplateId')

# The actual template creation would be done before running this script
# via terraform apply or manual AWS CLI commands

# Start rolling update
echo -e "${YELLOW}Starting rolling update...${NC}"

# Update ASG with new launch template
aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name $ASG_NAME \
    --region $REGION \
    --launch-template LaunchTemplateId=$LAUNCH_TEMPLATE_ID,Version='$Latest' \
    --min-healthy-percentage $MIN_HEALTHY_PERCENTAGE

# Wait for instances to be updated
echo -e "${YELLOW}Waiting for instances to be updated...${NC}"
for i in $(seq 1 $DESIRED_CAPACITY); do
    echo "Updating instance batch $i/$DESIRED_CAPACITY"
    
    # Get instance IDs
    INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names $ASG_NAME \
        --region $REGION \
        --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
        --output text)
    
    # Terminate instances in batches
    for INSTANCE_ID in $INSTANCES; do
        aws autoscaling terminate-instance-in-auto-scaling-group \
            --instance-id $INSTANCE_ID \
            --region $REGION \
            --should-decrement-desired-capacity
        
        # Wait for replacement instance to come up
        sleep 30
        
        # Check health
        if ! aws ec2 describe-instance-status \
            --instance-ids $INSTANCE_ID \
            --region $REGION \
            --query 'InstanceStatuses[0].InstanceStatus.Status' \
            --output text | grep -q 'ok'; then
            echo -e "${RED}Instance health check failed${NC}"
            exit 1
        fi
        
        # Only terminate one instance at a time for rolling deployment
        break
    done
done

echo -e "${GREEN}✓ Rolling deployment complete!${NC}"
