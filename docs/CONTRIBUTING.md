# Contributing Guide

## Code Standards

### JavaScript/Node.js
- Use ES6+ features
- Async/await for asynchronous operations
- Error handling with try/catch
- Meaningful variable names
- Comments for complex logic

### Formatting
```bash
# Format code
npm run format

# Lint code
npm run lint

# Fix linting issues
npm run lint -- --fix
```

## Testing

```bash
# Run tests
npm test

# Run with coverage
npm test -- --coverage

# Run specific test file
npm test -- src/app.test.js

# Watch mode
npm run test:watch
```

## Commit Messages

Follow conventional commits:
```
feat: add new feature
fix: fix a bug
docs: documentation changes
style: code style changes
refactor: refactor code
perf: performance improvements
test: add/update tests
chore: maintenance tasks
```

Example:
```
feat: add /metrics endpoint

- Add metrics collection middleware
- Expose request/error statistics
- Include memory usage metrics
- Helps with observability
```

## Pull Requests

1. Create feature branch: `git checkout -b feature/name`
2. Make changes and commit
3. Push: `git push origin feature/name`
4. Create PR with description
5. Address review comments
6. Squash commits if needed
7. Merge when approved

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation

## Testing
- [ ] Unit tests added
- [ ] Integration tests added
- [ ] Manual testing done

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated
- [ ] Tests pass
- [ ] No new warnings generated
```

## Release Process

1. Update version in package.json
2. Update CHANGELOG.md
3. Create git tag: `git tag v1.0.0`
4. Push tag: `git push origin v1.0.0`
5. GitHub Actions creates release
6. Docker image pushed with version tag

## Security

- Never commit sensitive data
- Use environment variables
- Validate all inputs
- Keep dependencies updated
- Report security issues privately

## Reporting Issues

Include:
- Environment (OS, Node version, Docker version)
- Steps to reproduce
- Expected behavior
- Actual behavior
- Error messages/logs
- Screenshots if applicable
