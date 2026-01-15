# API Documentation

## Overview

The CredPal API is a simple, production-ready REST API running on Node.js with Express.js. All responses are JSON formatted.

## Base URL

```
Local:      http://localhost:3000
Staging:    http://staging.example.com
Production: https://app.example.com
```

## Authentication

Currently, the API has no authentication. Production deployment should include:
- API keys for service-to-service communication
- JWT tokens for user authentication
- OAuth 2.0 for third-party integrations

## Rate Limiting

Currently unlimited. Recommended rate limits:
- Per IP: 1000 requests/hour
- Per user: 10000 requests/hour
- Burst: 100 requests/minute

## Response Format

All responses follow this format:

### Success Response

```json
{
  "status": "ok|healthy|success",
  "data": {},
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

### Error Response

```json
{
  "error": "Error message",
  "message": "Detailed error information",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

## HTTP Status Codes

| Code | Meaning | Use Case |
|------|---------|----------|
| 200 | OK | Successful request |
| 201 | Created | Resource created |
| 204 | No Content | Successful deletion |
| 400 | Bad Request | Invalid parameters |
| 401 | Unauthorized | Authentication required |
| 403 | Forbidden | Access denied |
| 404 | Not Found | Resource not found |
| 500 | Server Error | Unexpected error |
| 503 | Unavailable | Service down |

## Endpoints

### 1. Health Check

**Endpoint**: `GET /health`

**Purpose**: Quick health check for monitoring and load balancer

**Response** (200 OK):
```json
{
  "status": "ok",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Usage**:
```bash
curl http://localhost:3000/health
```

---

### 2. Status

**Endpoint**: `GET /status`

**Purpose**: Detailed application status including database connectivity

**Response** (200 OK):
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "database": "connected",
  "uptime": 3600
}
```

**Response** (503 Service Unavailable):
```json
{
  "status": "unhealthy",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "error": "Connection refused: 5432"
}
```

**Usage**:
```bash
curl http://localhost:3000/status
```

---

### 3. Metrics

**Endpoint**: `GET /metrics`

**Purpose**: Application metrics for monitoring and observability

**Response** (200 OK):
```json
{
  "uptime": 3600,
  "requestCount": 1250,
  "errorCount": 5,
  "errorRate": "0.40%",
  "avgResponseTime": "45.23ms",
  "memory": {
    "rss": "128MB",
    "heapTotal": "64MB",
    "heapUsed": "32MB",
    "external": "2MB"
  }
}
```

**Usage**:
```bash
curl http://localhost:3000/metrics
```

---

### 4. Process Data

**Endpoint**: `POST /process`

**Purpose**: Process and store data in the database

**Request Headers**:
```
Content-Type: application/json
```

**Request Body**:
```json
{
  "data": {
    "key1": "value1",
    "key2": "value2",
    "nested": {
      "field": "value"
    }
  }
}
```

**Response** (200 OK):
```json
{
  "message": "Data processed successfully",
  "id": 1,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Response** (400 Bad Request):
```json
{
  "error": "Missing data field"
}
```

**Response** (500 Server Error):
```json
{
  "error": "Processing failed",
  "message": "Unexpected error message"
}
```

**Usage**:
```bash
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "userId": 123,
      "action": "purchase",
      "amount": 99.99
    }
  }'
```

**Database Storage**:
```sql
-- Data stored in process_logs table
SELECT * FROM process_logs WHERE id = 1;

-- Result:
-- id | data | created_at | updated_at
-- 1 | {"userId": 123, "action": "purchase", "amount": 99.99} | 2024-01-15 10:30:00 | 2024-01-15 10:30:00
```

---

### 5. Not Found

**Endpoint**: `GET /any-unknown-endpoint`

**Response** (404 Not Found):
```json
{
  "error": "Endpoint not found"
}
```

---

## Error Handling

### Common Errors

#### Missing Required Field
```bash
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{}'
```

Response (400):
```json
{
  "error": "Missing data field"
}
```

#### Database Connection Error
```bash
# When database is down
curl http://localhost:3000/status
```

Response (503):
```json
{
  "status": "unhealthy",
  "error": "Connection refused: postgres:5432"
}
```

#### Server Error
```bash
# Any unexpected error
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{...invalid...}'
```

Response (500):
```json
{
  "error": "Internal server error",
  "message": "Error details (development mode only)"
}
```

## Examples

### Health Check Script

```bash
#!/bin/bash

ENDPOINT="http://localhost:3000"

# Function to check health
check_health() {
  response=$(curl -s -w "\n%{http_code}" $ENDPOINT/health)
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | head -n1)
  
  if [ "$http_code" = "200" ]; then
    echo "✓ Health check passed"
    return 0
  else
    echo "✗ Health check failed (HTTP $http_code)"
    echo "$body"
    return 1
  fi
}

check_health
```

### Data Processing Script

```bash
#!/bin/bash

ENDPOINT="http://localhost:3000"

# Process multiple data items
for i in {1..5}; do
  echo "Processing item $i..."
  
  response=$(curl -s -X POST $ENDPOINT/process \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "item_number": '$i',
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "value": '$((RANDOM))'
      }
    }')
  
  echo "$response" | jq .
done
```

### Monitoring Script

```bash
#!/bin/bash

ENDPOINT="http://localhost:3000"
INTERVAL=10

while true; do
  echo "=== $(date) ==="
  
  # Get metrics
  curl -s $ENDPOINT/metrics | jq '{
    uptime: .uptime,
    requests: .requestCount,
    errors: .errorCount,
    errorRate: .errorRate,
    memory: .memory.heapUsed
  }'
  
  sleep $INTERVAL
done
```

## SDK Usage

### Node.js/JavaScript

```javascript
const axios = require('axios');

const API = axios.create({
  baseURL: 'http://localhost:3000',
  timeout: 5000,
  headers: {
    'Content-Type': 'application/json'
  }
});

// Health check
async function checkHealth() {
  const response = await API.get('/health');
  console.log(response.data);
}

// Get status
async function getStatus() {
  const response = await API.get('/status');
  console.log(response.data);
}

// Process data
async function processData(data) {
  const response = await API.post('/process', { data });
  console.log(response.data);
}

// Usage
checkHealth();
processData({ userId: 123, action: 'test' });
```

### Python

```python
import requests
import json

API_URL = 'http://localhost:3000'

# Health check
def check_health():
    response = requests.get(f'{API_URL}/health')
    return response.json()

# Process data
def process_data(data):
    response = requests.post(
        f'{API_URL}/process',
        json={'data': data},
        headers={'Content-Type': 'application/json'}
    )
    return response.json()

# Usage
print(check_health())
result = process_data({'userId': 123, 'action': 'test'})
print(result)
```

### cURL

```bash
# Health check
curl http://localhost:3000/health

# Status with timing
curl -w "\nTime: %{time_total}s\n" \
  http://localhost:3000/status

# Process data
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{"data": {"test": true}}' \
  | jq

# Pretty print response
curl -s http://localhost:3000/metrics | jq '.' | less
```

## Pagination (Future Implementation)

When implementing pagination:

```json
{
  "data": [...],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "total": 1000,
    "totalPages": 50,
    "hasNext": true,
    "hasPrev": false
  }
}
```

## Versioning

Future API versions:
- `/v1/...` (current)
- `/v2/...` (future)

Backward compatibility will be maintained for 6 months.

## Changelog

### v1.0.0 (Current)
- Initial release
- Health check endpoint
- Status endpoint
- Process endpoint
- Metrics endpoint

## Support

- GitHub Issues: [Create issue](https://github.com/your-org/credpal-node-app/issues)
- Email: api-support@example.com
- Slack: #credpal-support
