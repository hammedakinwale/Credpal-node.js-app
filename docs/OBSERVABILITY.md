# Observability

## Logging

### Application Logging
- Winston logger configured with JSON output
- Log levels: debug, info, warn, error
- Structured logging for better analysis
- Logs include timestamps and context

### CloudWatch Integration
```bash
# View logs
aws logs tail /aws/ec2/credpal --follow

# Create log groups and streams in Terraform
aws logs create-log-group --log-group-name /aws/credpal/app
aws logs create-log-stream --log-group-name /aws/credpal/app --log-stream-name production
```

### Log Retention
- Application logs: Stored in CloudWatch
- Retention policy: 30 days (configurable)
- Archive to S3 for long-term storage

## Metrics

### Application Metrics
- Request count and error rate
- Response times (average, p50, p95, p99)
- Memory usage (RSS, heap)
- Database connection pool status

### CloudWatch Metrics
- CPU utilization
- Network In/Out
- Disk I/O
- ALB target health

### Custom Metrics
```javascript
// Exposed via /metrics endpoint
{
  "uptime": 3600,
  "requestCount": 1250,
  "errorCount": 5,
  "errorRate": "0.40%",
  "avgResponseTime": "45.23ms",
  "memory": {
    "rss": "128MB",
    "heapTotal": "64MB",
    "heapUsed": "32MB"
  }
}
```

## Health Checks

### Readiness Probe
- Endpoint: `GET /health`
- Returns: Application status (200 OK)
- Checked every: 30 seconds
- Used by: Docker, ALB

### Liveness Probe
- Endpoint: `GET /status`
- Returns: Application + database status
- Includes database connectivity check
- Timeout: 3 seconds

## Monitoring & Alerting

### CloudWatch Alarms
1. **High CPU Usage** (> 70% for 2 periods)
   - Action: Scale up
   - Period: 5 minutes

2. **Low CPU Usage** (< 30% for 2 periods)
   - Action: Scale down
   - Period: 5 minutes

3. **Target Unhealthy**
   - Action: Replace instance
   - Period: 1 minute

4. **Database CPU High** (> 80%)
   - Action: SNS notification
   - Period: 5 minutes

### Recommended Additional Alarms
```terraform
# High error rate
aws cloudwatch put-metric-alarm \
  --alarm-name credpal-high-error-rate \
  --alarm-description "Alert when error rate > 5%" \
  --metric-name ErrorRate \
  --namespace CustomApp \
  --statistic Average \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold

# High response time
aws cloudwatch put-metric-alarm \
  --alarm-name credpal-high-latency \
  --alarm-description "Alert when p95 latency > 1000ms" \
  --metric-name ResponseTime \
  --namespace CustomApp \
  --statistic p95 \
  --period 300 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold
```

## Dashboards

### CloudWatch Dashboard
View key metrics in real-time:
- Request rate
- Error rate
- Response times
- CPU and memory usage
- Database performance
- ALB health

### Create Dashboard
```bash
aws cloudwatch put-dashboard --dashboard-name CredPal \
  --dashboard-body file://dashboard-config.json
```

## Distributed Tracing

### X-Ray Integration (Optional)
```javascript
const AWSXRay = require('aws-xray-sdk-core');
const http = AWSXRay.captureHTTPsGlobal(require('http'));
const pg = AWSXRay.captureClient(require('pg'));
```

## Log Aggregation

### ELK Stack Integration (Optional)
```bash
# Elasticsearch
docker run -d --name elasticsearch \
  -e "discovery.type=single-node" \
  -p 9200:9200 \
  docker.elastic.co/elasticsearch/elasticsearch:8.5.0

# Kibana
docker run -d --name kibana \
  -p 5601:5601 \
  docker.elastic.co/kibana/kibana:8.5.0
```

## SLA Monitoring

### Key SLO Targets
- **Availability**: 99.9% uptime
- **Response Time**: p95 < 200ms
- **Error Rate**: < 0.1%
- **Deployment Success**: > 99%

### Tracking SLOs
```bash
# Query CloudWatch for SLO metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --statistics Average \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-16T00:00:00Z \
  --period 3600
```

## Cost Monitoring

### CloudWatch Costs
- Logs: $0.50 per GB ingested
- Custom metrics: $0.30 per custom metric
- Alarms: $0.10 per alarm

### Set Up Cost Alerts
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name aws-billing-alert \
  --alarm-description "Alert when monthly bill > $100" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold
```
