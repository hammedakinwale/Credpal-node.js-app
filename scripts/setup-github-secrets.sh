#!/bin/bash

# GitHub Secrets Automated Setup Script
# This script automatically retrieves values from AWS and Terraform,
# then sets them as GitHub Actions secrets using GitHub CLI

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  GitHub Actions Secrets Setup${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS CLI installed${NC}"

if ! command -v gh &> /dev/null; then
    echo -e "${RED}✗ GitHub CLI is not installed${NC}"
    echo "Install with: brew install gh"
    exit 1
fi
echo -e "${GREEN}✓ GitHub CLI installed${NC}"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ Terraform is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Terraform installed${NC}"

# Verify GitHub CLI is authenticated
echo -e "${YELLOW}Verifying GitHub authentication...${NC}"
if ! gh auth status &>/dev/null; then
    echo -e "${RED}✗ GitHub CLI not authenticated${NC}"
    echo "Run: gh auth login"
    exit 1
fi
echo -e "${GREEN}✓ GitHub CLI authenticated${NC}"

# Get AWS Account ID
echo -e "\n${YELLOW}Retrieving AWS Account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}✗ Failed to retrieve AWS Account ID${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS Account ID: $AWS_ACCOUNT_ID${NC}"

# Get AWS OIDC Role
echo -e "${YELLOW}Retrieving AWS OIDC Role ARN...${NC}"
AWS_ROLE=$(aws iam get-role --role-name github-actions-credpal-role --query 'Role.Arn' --output text 2>/dev/null) || {
    echo -e "${YELLOW}⚠ Could not find github-actions-credpal-role${NC}"
    read -p "Enter AWS OIDC Role ARN (or press Enter to skip): " AWS_ROLE
    if [ -z "$AWS_ROLE" ]; then
        echo -e "${YELLOW}⚠ Skipping AWS_ROLE_TO_ASSUME${NC}"
        AWS_ROLE=""
    fi
}
if [ -n "$AWS_ROLE" ]; then
    echo -e "${GREEN}✓ AWS OIDC Role: $AWS_ROLE${NC}"
fi

# Get RDS Endpoint from Terraform
echo -e "${YELLOW}Retrieving RDS Endpoint from Terraform...${NC}"
RDS_ENDPOINT=$(terraform output -raw rds_address 2>/dev/null) || {
    echo -e "${YELLOW}⚠ Could not get RDS endpoint from Terraform${NC}"
    read -p "Enter RDS Endpoint (or press Enter to skip): " RDS_ENDPOINT
}
if [ -n "$RDS_ENDPOINT" ]; then
    echo -e "${GREEN}✓ RDS Endpoint: $RDS_ENDPOINT${NC}"
fi

# Get Redis Endpoint from Terraform
echo -e "${YELLOW}Retrieving Redis Endpoint from Terraform...${NC}"
REDIS_ENDPOINT=$(terraform output -raw elasticache_endpoint 2>/dev/null) || {
    echo -e "${YELLOW}⚠ Could not get Redis endpoint from Terraform${NC}"
    read -p "Enter Redis Endpoint (or press Enter to skip): " REDIS_ENDPOINT
}
if [ -n "$REDIS_ENDPOINT" ]; then
    echo -e "${GREEN}✓ Redis Endpoint: $REDIS_ENDPOINT${NC}"
fi

# Get DB Secret ARN from AWS
echo -e "${YELLOW}Retrieving DB Secret ARN from AWS Secrets Manager...${NC}"
DB_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id credpal/db/credentials --query 'ARN' --output text 2>/dev/null) || {
    echo -e "${YELLOW}⚠ Could not find credpal/db/credentials secret${NC}"
    read -p "Enter DB Secret ARN (or press Enter to skip): " DB_SECRET_ARN
}
if [ -n "$DB_SECRET_ARN" ]; then
    echo -e "${GREEN}✓ DB Secret ARN: $DB_SECRET_ARN${NC}"
fi

# Confirm before setting secrets
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}  Secrets to be configured${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo "AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
[ -n "$AWS_ROLE" ] && echo "AWS_ROLE_TO_ASSUME: $AWS_ROLE"
[ -n "$RDS_ENDPOINT" ] && echo "RDS_ENDPOINT: $RDS_ENDPOINT"
[ -n "$REDIS_ENDPOINT" ] && echo "REDIS_ENDPOINT: $REDIS_ENDPOINT"
[ -n "$DB_SECRET_ARN" ] && echo "DB_SECRET_ARN: $DB_SECRET_ARN"

echo ""
read -p "Continue and set these secrets? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

# Set secrets
echo -e "\n${YELLOW}Setting secrets in GitHub...${NC}"

echo -n "Setting AWS_ACCOUNT_ID... "
gh secret set AWS_ACCOUNT_ID -b "$AWS_ACCOUNT_ID" && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

if [ -n "$AWS_ROLE" ]; then
    echo -n "Setting AWS_ROLE_TO_ASSUME... "
    gh secret set AWS_ROLE_TO_ASSUME -b "$AWS_ROLE" && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
fi

if [ -n "$RDS_ENDPOINT" ]; then
    echo -n "Setting RDS_ENDPOINT... "
    gh secret set RDS_ENDPOINT -b "$RDS_ENDPOINT" && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
fi

if [ -n "$REDIS_ENDPOINT" ]; then
    echo -n "Setting REDIS_ENDPOINT... "
    gh secret set REDIS_ENDPOINT -b "$REDIS_ENDPOINT" && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
fi

if [ -n "$DB_SECRET_ARN" ]; then
    echo -n "Setting DB_SECRET_ARN... "
    gh secret set DB_SECRET_ARN -b "$DB_SECRET_ARN" && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
fi

# Verify secrets
echo -e "\n${YELLOW}Verifying secrets...${NC}"
gh secret list

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✓ All secrets configured successfully!${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "Next steps:"
echo -e "1. Push code to main branch: ${BLUE}git push origin main${NC}"
echo -e "2. Monitor deployment: ${BLUE}gh run list${NC}"
echo -e "3. Watch logs: ${BLUE}gh run view --log${NC}"

echo -e "\n${GREEN}Setup complete! 🚀${NC}"
