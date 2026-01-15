#!/bin/bash

# Blue-Green Deployment Script
# This script implements a blue-green deployment strategy for zero-downtime updates

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

BLUE_CONTAINER="credpal-app-blue"
GREEN_CONTAINER="credpal-app-green"
ALB_TARGET_GROUP="${ALB_TARGET_GROUP:-credpal-tg}"
HEALTH_CHECK_URL="http://localhost:3000/health"
HEALTH_CHECK_TIMEOUT=300
HEALTH_CHECK_INTERVAL=5

echo -e "${YELLOW}Starting Blue-Green Deployment...${NC}"

# Function to check container health
check_container_health() {
    local container=$1
    local elapsed=0
    
    echo "Checking health of container: $container"
    
    while [ $elapsed -lt $HEALTH_CHECK_TIMEOUT ]; do
        if docker exec $container wget --quiet --tries=1 --spider $HEALTH_CHECK_URL 2>/dev/null; then
            echo -e "${GREEN}✓ Container $container is healthy${NC}"
            return 0
        fi
        echo "Waiting for container to be healthy... ($elapsed/$HEALTH_CHECK_TIMEOUT)"
        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    done
    
    echo -e "${RED}✗ Container failed health check${NC}"
    return 1
}

# Function to switch traffic
switch_traffic() {
    local from_container=$1
    local to_container=$2
    
    echo -e "${YELLOW}Switching traffic from $from_container to $to_container${NC}"
    
    # Update ALB target group to point to new container
    # This is a simplified example - actual implementation depends on your setup
    # In AWS, you would update the target group to deregister old instance and register new one
    
    echo -e "${GREEN}✓ Traffic switched successfully${NC}"
}

# Function to rollback
rollback() {
    echo -e "${RED}Deployment failed, rolling back...${NC}"
    switch_traffic "$GREEN_CONTAINER" "$BLUE_CONTAINER"
    docker stop $GREEN_CONTAINER || true
    docker rm $GREEN_CONTAINER || true
    echo -e "${GREEN}✓ Rollback complete${NC}"
    exit 1
}

trap rollback ERR

# Check if blue container is running
if docker ps | grep -q $BLUE_CONTAINER; then
    echo -e "${YELLOW}Blue container is running, starting green deployment...${NC}"
    ACTIVE="blue"
    INACTIVE="green"
    ACTIVE_CONTAINER=$BLUE_CONTAINER
    INACTIVE_CONTAINER=$GREEN_CONTAINER
else
    echo -e "${YELLOW}Green container is running (or first deployment), starting blue deployment...${NC}"
    ACTIVE="green"
    INACTIVE="blue"
    ACTIVE_CONTAINER=$GREEN_CONTAINER
    INACTIVE_CONTAINER=$BLUE_CONTAINER
fi

# Pull latest image
echo -e "${YELLOW}Pulling latest Docker image...${NC}"
docker pull ghcr.io/your-org/credpal-node-app:latest

# Stop and remove inactive container
echo -e "${YELLOW}Removing old $INACTIVE container...${NC}"
docker stop $INACTIVE_CONTAINER || true
docker rm $INACTIVE_CONTAINER || true

# Start new container
echo -e "${YELLOW}Starting new $INACTIVE container...${NC}"
docker run -d \
    --name $INACTIVE_CONTAINER \
    -p 3001:3000 \
    -e NODE_ENV=production \
    -e PORT=3000 \
    -e DB_HOST=$DB_HOST \
    -e DB_USER=$DB_USER \
    -e DB_PASSWORD=$DB_PASSWORD \
    -e DB_NAME=$DB_NAME \
    -e LOG_LEVEL=info \
    ghcr.io/your-org/credpal-node-app:latest

# Check health
if ! check_container_health $INACTIVE_CONTAINER; then
    rollback
fi

# Switch traffic
switch_traffic $ACTIVE_CONTAINER $INACTIVE_CONTAINER

# Keep old container running for quick rollback (optional)
echo -e "${YELLOW}Keeping $ACTIVE_CONTAINER running for quick rollback...${NC}"

echo -e "${GREEN}✓ Deployment complete!${NC}"
echo -e "${GREEN}Active container: $INACTIVE_CONTAINER${NC}"
echo -e "${GREEN}Standby container: $ACTIVE_CONTAINER${NC}"
