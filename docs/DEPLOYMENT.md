# Deployment Guide

> Version: 0.0.9 | Last Updated: 2026-02-07

This guide covers the deployment pipeline, scripts, and configuration for deploying applications using Woodpecker CI/CD.

## Table of Contents

- [Overview](#overview)
- [Deployment Flow](#deployment-flow)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Deployment Methods](#deployment-methods)
- [Scripts](#scripts)
- [Rollback](#rollback)
- [Troubleshooting](#troubleshooting)

---

## Overview

The deployment system supports multiple deployment strategies:

| Method | Description | Use Case |
|--------|-------------|----------|
| Docker | Standalone containers | Simple single-container apps |
| Docker Compose | Multi-container apps | Apps with dependencies |
| SSH | Remote server deployment | Traditional servers |
| Kubernetes | K8s native deployment | Container orchestration |
| Helm | K8s with Helm charts | Complex K8s deployments |

### Key Features

- ✅ **Staged Deployments**: Deploy to staging before production
- ✅ **Health Checks**: Automated verification after deployment
- ✅ **Auto-Rollback**: Automatic rollback on health check failure
- ✅ **Issue Creation**: GitHub issues on deployment failures
- ✅ **Notifications**: Slack/webhook notifications
- ✅ **Backup & Restore**: Pre-deployment backups

---

## Deployment Flow

```
┌─────────────────┐
│  Pipeline Start │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Validate Config │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Build Artifacts │
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│ Deploy to Staging   │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Run Staging Tests   │
└────────┬────────────┘
         │
    ┌────┴────┐
    │  Pass?  │
    └────┬────┘
    Yes  │  No
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────────────────┐  ┌──────────────────┐
│ Deploy Production │  │ Create Issue     │
└────────┬──────────┘  │ Wait for Fix     │
         │             └──────────────────┘
         ▼
┌───────────────────────┐
│ Health Check Production│
└────────┬──────────────┘
         │
    ┌────┴────┐
    │  Pass?  │
    └────┬────┘
    Yes  │  No
    ┌────┴────┐
    │         │
    ▼         ▼
┌──────────┐  ┌────────────┐
│ Success! │  │ Rollback   │
│ Notify   │  │ Create Issue│
└──────────┘  └────────────┘
```

---

## Quick Start

### 1. Configure Secrets

Add these secrets to Woodpecker:

```bash
# Docker Registry
docker_username=your-username
docker_password=your-password

# SSH (for staging)
staging_ssh_key="-----BEGIN RSA PRIVATE KEY-----..."
staging_host=staging.example.com
staging_user=deploy

# SSH (for production)
production_ssh_key="-----BEGIN RSA PRIVATE KEY-----..."
production_host=prod.example.com
production_user=deploy

# GitHub (for issue creation)
github_token=ghp_xxxxxxxxxxxx

# Slack (optional)
slack_webhook=https://hooks.slack.com/services/xxx/yyy/zzz
```

### 2. Configure Deployment

Edit `config/deploy.yaml`:

```yaml
environments:
  staging:
    method: docker
    docker:
      network: staging-network
      ports:
        - host: 8080
          container: 3000
```

### 3. Run Deployment

**Via UI**: Trigger the deploy pipeline manually

**Via CLI**:
```bash
# Deploy to staging
./scripts/deploy.sh --env staging --app myapp --version 1.0.0

# Deploy to production
./scripts/deploy.sh --env production --app myapp --version 1.0.0
```

---

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DEPLOY_ENV` | Target environment | `staging` |
| `DEPLOY_METHOD` | Deployment method | `docker` |
| `APP_NAME` | Application name | `myapp` |
| `APP_VERSION` | Version to deploy | `latest` |
| `DOCKER_REGISTRY` | Docker registry URL | `docker.io` |
| `SSH_HOST` | Remote host for SSH | - |
| `SSH_USER` | SSH username | - |
| `SSH_KEY` | Path to SSH key | - |
| `KUBECONFIG` | Path to kubeconfig | - |
| `K8S_NAMESPACE` | Kubernetes namespace | `default` |

### Config File Structure

The `config/deploy.yaml` file is structured as:

```yaml
global:
  # Settings applied to all environments
  app:
    name: "myapp"
    health_endpoint: "/health"
  
environments:
  staging:
    method: docker
    docker:
      # Docker-specific settings
    kubernetes:
      # K8s-specific settings
      
  production:
    method: kubernetes
    # Production settings
```

---

## Deployment Methods

### Docker

Deploy as a standalone Docker container:

```bash
./scripts/deploy.sh --env staging --method docker --app myapp --version 1.0.0
```

**What happens:**
1. Pull image from registry
2. Stop existing container
3. Start new container with environment variables
4. Run health checks

### Docker Compose

Deploy using Docker Compose:

```bash
./scripts/deploy.sh --env staging --method docker-compose --app myapp
```

**Requirements:**
- `docker-compose.yml` or `docker-compose.{env}.yml` in project root

**What happens:**
1. Load environment-specific compose file
2. Pull all images
3. Recreate containers
4. Run health checks

### SSH

Deploy to a remote server via SSH:

```bash
./scripts/deploy.sh --env staging --method ssh --app myapp
```

**Required secrets:**
- `staging_ssh_key` or `production_ssh_key`
- `staging_host` or `production_host`
- `staging_user` or `production_user`

**What happens:**
1. SSH to remote server
2. Pull Docker image
3. Stop/remove existing container
4. Start new container

### Kubernetes

Deploy using kubectl:

```bash
./scripts/deploy.sh --env staging --method kubernetes --app myapp
```

**Requirements:**
- `kubeconfig_staging` or `kubeconfig_production` secret
- Kubernetes manifests in `k8s/{env}/`

**What happens:**
1. Apply Kubernetes manifests with envsubst
2. Update deployment image
3. Wait for rollout to complete
4. Run health checks

### Helm

Deploy using Helm charts:

```bash
./scripts/deploy.sh --env staging --method helm --app myapp
```

**Requirements:**
- Helm chart in `charts/{app_name}/`
- Values file: `values-{env}.yaml`

**What happens:**
1. Helm upgrade with environment values
2. Wait for release to be ready
3. Run health checks

---

## Scripts

### deploy.sh

Main deployment script supporting all methods.

```bash
# Basic usage
./scripts/deploy.sh --env staging --app myapp --version 1.0.0

# With config file
./scripts/deploy.sh --env production --config ./config/deploy.yaml

# Dry run (show what would happen)
./scripts/deploy.sh --env staging --dry-run

# Check status
./scripts/deploy.sh --env staging --action status

# Create backup
./scripts/deploy.sh --env production --action backup

# View logs
./scripts/deploy.sh --env staging --action logs
```

**Options:**

| Option | Description |
|--------|-------------|
| `-e, --env` | Target environment |
| `-v, --version` | Application version |
| `-a, --app` | Application name |
| `-m, --method` | Deployment method |
| `-c, --config` | Config file path |
| `--action` | Action (deploy/backup/status/logs) |
| `--dry-run` | Show actions without executing |
| `--verbose` | Enable debug output |

### rollback.sh

Rollback to a previous version.

```bash
# Rollback to previous version
./scripts/rollback.sh --env production --app myapp

# Rollback to specific version
./scripts/rollback.sh --env production --app myapp --to-version 1.0.0

# List available backups
./scripts/rollback.sh --env production --app myapp --list-backups

# Force rollback (skip confirmation)
./scripts/rollback.sh --env production --app myapp --force

# Dry run
./scripts/rollback.sh --env production --app myapp --dry-run
```

---

## Rollback

### Automatic Rollback

Automatic rollback triggers when:
1. Production health check fails
2. `rollback.auto_rollback: true` in config

### Manual Rollback

```bash
# List available backups
./scripts/rollback.sh --env production --list-backups

# Rollback to previous version
./scripts/rollback.sh --env production --app myapp

# Rollback to specific version
./scripts/rollback.sh --env production --app myapp --to-version 1.0.0
```

### Kubernetes Rollback

For Kubernetes deployments, you can also use native rollback:

```bash
# View rollout history
kubectl rollout history deployment/myapp

# Rollback to previous revision
kubectl rollout undo deployment/myapp

# Rollback to specific revision
kubectl rollout undo deployment/myapp --to-revision=2
```

### Helm Rollback

For Helm deployments:

```bash
# View release history
helm history myapp

# Rollback to previous release
helm rollback myapp

# Rollback to specific revision
helm rollback myapp 2
```

---

## Health Checks

### Configuration

```yaml
global:
  health_check:
    max_attempts: 30
    interval: 10  # seconds
    timeout: 5    # seconds

  app:
    health_endpoint: "/health"
    version_endpoint: "/version"
```

### Expected Response

**Health endpoint** (`/health`):
- Must return HTTP 2xx status code
- Body content is not checked

**Version endpoint** (`/version`):
```json
{
  "version": "1.0.0",
  "commit": "abc1234",
  "build_time": "2024-01-15T10:30:00Z"
}
```

---

## Notifications

### Slack

Configure in secrets:
```
slack_webhook=https://hooks.slack.com/services/xxx/yyy/zzz
```

Notifications are sent for:
- ✅ Successful deployments
- ❌ Failed deployments
- ⚠️ Rollback events

### GitHub Issues

On deployment failure, an issue is created with:
- Commit details
- Pipeline link
- Error information
- Suggested actions

---

## Troubleshooting

### Common Issues

#### Health Check Failing

```bash
# Check container logs
docker logs myapp-staging

# Check service availability
curl -v http://localhost:8080/health
```

#### SSH Connection Failing

```bash
# Test SSH connection
ssh -i /path/to/key deploy@staging.example.com 'echo ok'

# Check key permissions
chmod 600 /path/to/key
```

#### Kubernetes Deployment Stuck

```bash
# Check pod status
kubectl get pods -l app=myapp

# View pod logs
kubectl logs -l app=myapp

# Describe deployment
kubectl describe deployment myapp
```

### Debug Mode

Enable verbose output:

```bash
./scripts/deploy.sh --env staging --verbose

# Or set environment variable
VERBOSE=true ./scripts/deploy.sh --env staging
```

### Dry Run

Preview actions without executing:

```bash
./scripts/deploy.sh --env production --dry-run
```

---

## Best Practices

1. **Always deploy to staging first** - Catch issues before production
2. **Use semantic versioning** - Makes rollback easier
3. **Set up monitoring** - Know when deployments fail
4. **Keep backups** - Configure `backup_retention` appropriately
5. **Test rollback procedure** - Practice before you need it
6. **Use deployment windows** - Avoid deploying during peak hours
7. **Document custom configs** - Team should know the setup

---

## File Reference

| File | Purpose |
|------|---------|
| `pipelines/deploy.yml` | Woodpecker deployment pipeline |
| `scripts/deploy.sh` | Main deployment script |
| `scripts/rollback.sh` | Rollback script |
| `config/deploy.yaml` | Deployment configuration |
| `docs/DEPLOYMENT.md` | This documentation |

---

## See Also

- [Woodpecker CI Documentation](https://woodpecker-ci.org/docs/intro)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Helm Charts](https://helm.sh/docs/topics/charts/)
