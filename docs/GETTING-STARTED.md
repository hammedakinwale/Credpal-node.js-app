# Getting Started Guide

## Initial Setup

### 1. Clone Repository

```bash
git clone https://github.com/your-org/credpal-node-app.git
cd credpal-node-app
```

### 2. Copy Environment Files

```bash
# For local development
cp .env.example .env

# Edit with your settings
nano .env
```

### 3. Install Node Dependencies

```bash
npm install
```

### 4. Start Services

```bash
# Start all services (PostgreSQL, Redis, Node app)
docker-compose up -d

# View logs
docker-compose logs -f app

# Test the application
curl http://localhost:3000/health
```

## Development Workflow

### 1. Make Changes

```bash
# Edit source files in src/
nano src/app.js
```

### 2. Test Changes

```bash
# Run unit tests
npm test

# Watch mode for development
npm run test:watch

# Run specific test file
npm test -- src/app.test.js
```

### 3. Verify Locally

```bash
# Rebuild container
docker-compose build app

# Restart service
docker-compose up -d app

# Test endpoint
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{"data": {"test": true}}'
```

### 4. Commit & Push

```bash
# Check git status
git status

# Stage changes
git add .

# Commit with descriptive message
git commit -m "feat: add new endpoint"

# Push to feature branch
git push origin feature/name

# Create Pull Request on GitHub
```

## Docker Development

### Build Image

```bash
# Build with default tag
docker build -t credpal-node-app:latest .

# Build with specific tag
docker build -t credpal-node-app:1.0.0 .

# Build with build args
docker build -t credpal-node-app:latest \
  --build-arg NODE_VERSION=20 \
  --build-arg BASE_IMAGE=node:20-alpine .
```

### Run Locally

```bash
# Run with default settings
docker run -d \
  --name credpal-app \
  -p 3000:3000 \
  credpal-node-app:latest

# Run with environment variables
docker run -d \
  --name credpal-app \
  -p 3000:3000 \
  -e NODE_ENV=development \
  -e DB_HOST=postgres \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgres \
  credpal-node-app:latest

# Run with volume mount (for development)
docker run -d \
  --name credpal-app \
  -p 3000:3000 \
  -v $(pwd)/src:/app/src \
  credpal-node-app:latest

# View logs
docker logs -f credpal-app

# Stop container
docker stop credpal-app

# Remove container
docker rm credpal-app
```

### Debug Container

```bash
# Execute command in running container
docker exec credpal-app npm test

# Get shell access
docker exec -it credpal-app sh

# Inspect environment variables
docker exec credpal-app env

# View file system
docker exec credpal-app ls -la src/
```

## Database Management

### PostgreSQL

```bash
# Connect to database
docker-compose exec postgres psql -U postgres -d credpal

# List tables
\dt

# View data
SELECT * FROM process_logs;

# Exit psql
\q

# Backup database
docker-compose exec postgres pg_dump -U postgres credpal > backup.sql

# Restore database
docker-compose exec -T postgres psql -U postgres credpal < backup.sql
```

### Redis

```bash
# Connect to Redis
docker-compose exec redis redis-cli

# List keys
KEYS *

# Set key
SET key "value"

# Get key
GET key

# Exit redis-cli
exit
```

## Testing

### Unit Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run specific test file
npm test -- src/app.test.js

# Run with coverage
npm test -- --coverage

# Update snapshots (if using snapshots)
npm test -- -u
```

### Integration Tests

```bash
# Test with running services
docker-compose up -d
npm test

# Test with coverage
npm test -- --coverage

# Generate HTML coverage report
npm test -- --coverage --collectCoverageFrom="src/**"
open coverage/lcov-report/index.html
```

### Manual Testing

```bash
# Health check
curl http://localhost:3000/health

# Status with database check
curl http://localhost:3000/status

# Process data
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{"data": {"userId": 123}}'

# Get metrics
curl http://localhost:3000/metrics | jq

# Test with verbose output
curl -v http://localhost:3000/health

# Test with response headers
curl -i http://localhost:3000/health

# Measure response time
curl -w "@curl-format.txt" -o /dev/null -s http://localhost:3000/health
```

### Load Testing

```bash
# Using Apache Bench
ab -n 1000 -c 10 http://localhost:3000/health

# Using wrk
wrk -t4 -c100 -d30s http://localhost:3000/health

# Using Apache Bench with POST
ab -n 100 -c 10 -p data.json \
  -T application/json \
  http://localhost:3000/process
```

## Cleanup

### Stop Services

```bash
# Stop all services but keep data
docker-compose stop

# Stop and remove containers
docker-compose down

# Stop and remove everything (including volumes)
docker-compose down -v
```

### Clean Up Docker

```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes
docker volume prune

# Remove everything unused
docker system prune -a --volumes
```

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 3000
lsof -i :3000

# Kill process
kill -9 <PID>

# Or use different port
docker run -p 3001:3000 credpal-node-app:latest
```

### Container Won't Start

```bash
# Check logs
docker logs <container-id>

# Inspect container
docker inspect <container-id>

# Check resource usage
docker stats <container-id>
```

### Database Connection Refused

```bash
# Check if postgres is running
docker ps | grep postgres

# Check logs
docker logs <postgres-container-id>

# Verify network
docker network ls
docker network inspect credpal-network
```

### Permission Denied

```bash
# Run docker with sudo
sudo docker-compose up

# Or add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

## Performance Tips

### Development

```bash
# Use node_modules caching in Docker
docker-compose build --no-cache app

# Use development mode for faster startup
NODE_ENV=development npm start

# Enable debugging
DEBUG=credpal:* npm start
```

### Production

```bash
# Use production mode
NODE_ENV=production npm start

# Monitor resource usage
docker stats

# Set memory limits
docker run -m 512m credpal-node-app:latest
```

## Next Steps

1. **Read the full README**: [README.md](../README.md)
2. **Review API documentation**: [docs/API.md](../docs/API.md)
3. **Set up CI/CD**: Push to GitHub and enable Actions
4. **Deploy to staging**: Use staging docker-compose
5. **Deploy to production**: Follow deployment guide

## Common Issues

### npm install fails
```bash
# Clear cache
npm cache clean --force

# Reinstall
rm -rf node_modules package-lock.json
npm install
```

### Docker image too large
```bash
# Check layers
docker history credpal-node-app:latest

# Rebuild without cache
docker build --no-cache -t credpal-node-app:latest .
```

### Tests timeout
```bash
# Increase timeout
npm test -- --testTimeout=10000
```

## Getting Help

- **Documentation**: Check [docs/](../docs/) folder
- **Issues**: [GitHub Issues](https://github.com/your-org/credpal-node-app/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/credpal-node-app/discussions)
- **Email**: devops@example.com

Happy coding! 🚀
