# GitHub Actions Setup for ECR Deployment

This guide explains how to set up GitHub Actions to automatically build and deploy your application to AWS ECS using ECR.

## Prerequisites

- AWS Account with IAM permissions
- GitHub repository with secrets configured
- Node.js 20+ installed locally

## Setup Steps

### 1. Create IAM Role for GitHub Actions

Create an IAM role that GitHub Actions can assume using OpenID Connect (OIDC).

```bash
# Create trust policy file
cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:GITHUB_ORG/credpal:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF
```

Replace:
- `ACCOUNT_ID` with your AWS account ID
- `GITHUB_ORG` with your GitHub organization/username
- `credpal` with your repository name

```bash
# Create the role
aws iam create-role \
  --role-name github-actions-ecr-role \
  --assume-role-policy-document file://trust-policy.json

# Get the ARN
aws iam list-roles --query "Roles[?RoleName=='github-actions-ecr-role'].Arn" --output text
```

### 2. Attach ECR and ECS Policies

```bash
# Attach ECR permissions
aws iam attach-role-policy \
  --role-name github-actions-ecr-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# Create inline policy for ECS updates
cat > ecs-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeClusters"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name github-actions-ecr-role \
  --policy-name ecs-update \
  --policy-document file://ecs-policy.json
```

### 3. Add GitHub Secrets

1. Go to your GitHub repository
2. Settings → Secrets and variables → Actions
3. Add the following secret:

**Secret Name:** `AWS_ROLE_TO_ASSUME`
**Value:** `arn:aws:iam::ACCOUNT_ID:role/github-actions-ecr-role`

Replace `ACCOUNT_ID` with your AWS account ID.

### 4. Update Terraform Outputs

The pipeline needs to know your ECS cluster and service names. Ensure `terraform/outputs.tf` includes:

```terraform
output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
```

### 5. Test the Pipeline

1. Push a commit to the main branch
2. Go to GitHub Actions tab
3. Monitor the pipeline:
   - **test** job: Runs tests
   - **build-and-push** job: Builds and pushes to ECR
   - **security-scan** job: Runs Trivy security scan
   - **deploy-staging** job: Updates staging ECS service
   - **deploy-production** job: Updates production ECS service

## Pipeline Workflow

```
Commit to main
    ↓
[test] - Run linter, tests, coverage
    ↓
[build-and-push] - Build Docker image, push to ECR
    ↓
[security-scan] - Scan image for vulnerabilities
    ↓
[deploy-staging] - Update staging ECS service
    ↓
[deploy-production] - Update production ECS service
```

## Important Notes

### Image Tags

The pipeline tags images with:
- `latest` - latest main branch build
- `{commit-sha}` - specific commit identifier

ECS service pulls the `latest` tag automatically.

### Environment Variables

All sensitive data should be stored in:
- **AWS Secrets Manager** - for application secrets (DB passwords, API keys)
- **GitHub Secrets** - for AWS credentials only

Never commit secrets to git.

### Troubleshooting

**"Role assumption failed"**
- Verify the role ARN in the secret is correct
- Check the trust policy has the correct GitHub repository path

**"ECR push failed"**
- Ensure `github-actions-ecr-role` has `AmazonEC2ContainerRegistryPowerUser` policy
- Check ECR repository exists in the correct region

**"ECS update failed"**
- Verify cluster and service names match
- Check the role has ECS update permissions

## Manual Deployment

If you need to deploy without pushing to main:

```bash
# Get the latest image
aws ecr describe-images \
  --repository-name credpal \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags' \
  --output text

# Update ECS service
aws ecs update-service \
  --cluster credpal-cluster \
  --service credpal-service \
  --force-new-deployment
```

## Monitoring

View pipeline execution in GitHub Actions:
- **Logs**: Actions tab → workflow run
- **Artifacts**: Coverage reports, security scans

View ECS deployment:
```bash
# Check service status
aws ecs describe-services \
  --cluster credpal-cluster \
  --services credpal-service

# View task logs
aws logs tail /ecs/credpal --follow
```

## Security Best Practices

✅ **Use OIDC** - No long-lived credentials needed
✅ **Minimal permissions** - Role only has required permissions
✅ **Environment approval** - Production requires approval
✅ **Image scanning** - Trivy scans for vulnerabilities
✅ **Secrets management** - AWS Secrets Manager for application secrets
