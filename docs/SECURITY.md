# Security Configuration

## Environment Variables

All sensitive data should be stored in environment variables and never committed to the repository.

Required environment variables:
- `NODE_ENV`: Application environment (development, staging, production)
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password (stored in AWS Secrets Manager)
- `DB_HOST`: Database host
- `DB_PORT`: Database port
- `DB_NAME`: Database name
- `LOG_LEVEL`: Log level (debug, info, warn, error)

## Secrets Management

### Local Development
1. Copy `.env.example` to `.env`
2. Update with local values (never commit `.env`)

### AWS Production
1. Store all secrets in AWS Secrets Manager
2. EC2 instances retrieve secrets using IAM roles
3. Implement secret rotation policies

### Docker Secrets
```bash
docker run \
  -e DB_PASSWORD="$(aws secretsmanager get-secret-value --secret-id credpal/db/password --query SecretString --output text)" \
  ...
```

## Security Best Practices

### Application Security
- ✓ Helmet.js for HTTP headers
- ✓ CORS enabled (configured as needed)
- ✓ Input validation and sanitization
- ✓ Error messages don't expose sensitive info
- ✓ Rate limiting (can be added via express-rate-limit)
- ✓ SQL injection prevention (using parameterized queries)

### Container Security
- ✓ Non-root user (UID 1001)
- ✓ Multi-stage builds (minimal attack surface)
- ✓ No secret files in images
- ✓ Regular base image updates
- ✓ Health checks configured
- ✓ Read-only root filesystem (can be enforced)

### Network Security
- ✓ Security groups with minimal permissions
- ✓ Private subnets for databases
- ✓ SSL/TLS encryption in transit
- ✓ Encrypted RDS storage
- ✓ VPC isolation

### Data Security
- ✓ RDS encryption at rest
- ✓ Database backups enabled (30-day retention)
- ✓ Automated backup windows
- ✓ CloudWatch monitoring
- ✓ Enhanced monitoring for RDS

### CI/CD Security
- ✓ GitHub token for registry authentication
- ✓ Secrets not logged in CI/CD
- ✓ Trivy vulnerability scanning
- ✓ SARIF upload for security tracking
- ✓ Manual approval for production

### Access Control
- ✓ IAM roles for EC2 (least privilege)
- ✓ No hardcoded credentials
- ✓ Secrets Manager for credential rotation
- ✓ CloudTrail logging (AWS best practice)

## Compliance

- GDPR: Data protection through encryption and access controls
- PCI-DSS: Network segmentation and encryption
- SOC 2: Monitoring, logging, and audit trails

## Security Checklist

- [ ] Environment variables configured in CI/CD
- [ ] Secrets Manager initialized in AWS
- [ ] Security groups properly configured
- [ ] RDS backups enabled
- [ ] CloudWatch alarms set up
- [ ] CloudTrail logging enabled
- [ ] VPC Flow Logs enabled
- [ ] Regular security updates scheduled
- [ ] Vulnerability scanning in CI/CD
- [ ] Disaster recovery plan documented
