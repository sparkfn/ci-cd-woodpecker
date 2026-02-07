# Webhook & Polling Guide

> Version: 0.0.10 | Last Updated: 2026-02-07

This guide covers webhook handling and polling services for CI/CD automation with Woodpecker.

## Table of Contents

- [Overview](#overview)
- [Webhook Handler](#webhook-handler)
- [Polling Service](#polling-service)
- [On-Merge Pipeline](#on-merge-pipeline)
- [Configuration](#configuration)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

## Overview

Two methods are available for detecting repository events:

| Method | Use Case | Pros | Cons |
|--------|----------|------|------|
| **Webhooks** | Standard setup | Real-time, efficient | Requires public endpoint |
| **Polling** | Restricted environments | Works anywhere | Delayed, API rate limits |

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        Git Provider                          │
│                (GitHub / GitLab / Gitea)                     │
└─────────────────────────┬────────────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          │                               │
          ▼                               ▼
┌─────────────────────┐       ┌─────────────────────┐
│   Webhook Handler   │       │   Polling Service   │
│   (webhook-handler) │       │   (poll-service)    │
│   Port 9000         │       │   Every 60s         │
└─────────┬───────────┘       └─────────┬───────────┘
          │                             │
          └──────────────┬──────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │   Event Processing  │
              │   - Route events    │
              │   - Trigger builds  │
              │   - Send notifs     │
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │  Woodpecker Server  │
              │  Pipeline Execution │
              └─────────────────────┘
```

---

## Webhook Handler

The webhook handler receives events from Git providers in real-time.

### Quick Start

```bash
# Start webhook server
./scripts/webhook-handler.sh --serve --port 9000

# Test with a payload file
./scripts/webhook-handler.sh --process /tmp/webhook.json

# Process from stdin
cat payload.json | ./scripts/webhook-handler.sh --stdin
```

### Setup GitHub Webhooks

1. Go to your repository → Settings → Webhooks → Add webhook

2. Configure:
   - **Payload URL**: `https://your-server.com:9000/webhook`
   - **Content type**: `application/json`
   - **Secret**: Your webhook secret
   - **Events**: Select events to trigger on:
     - Push
     - Pull requests
     - Releases

3. Save and test with the ping event

### Setup GitLab Webhooks

1. Go to project → Settings → Webhooks

2. Configure:
   - **URL**: `https://your-server.com:9000/webhook`
   - **Secret token**: Your webhook secret
   - **Trigger**: Push events, Merge request events, Tag push events

### Supported Events

| Event | GitHub | GitLab | Gitea | Action |
|-------|--------|--------|-------|--------|
| Push | ✅ | ✅ | ✅ | Trigger CI pipeline |
| Pull Request | ✅ | ✅ (MR) | ✅ | Trigger CI, update status |
| Merge | ✅ | ✅ | ✅ | Trigger on-merge pipeline |
| Tag | ✅ | ✅ | ✅ | Trigger release pipeline |
| Release | ✅ | ✅ | ✅ | Trigger deploy pipeline |
| Ping | ✅ | ❌ | ✅ | Confirm webhook setup |

### Running as a Service

Create a systemd service file:

```ini
# /etc/systemd/system/webhook-handler.service
[Unit]
Description=Webhook Handler Service
After=network.target

[Service]
Type=simple
User=woodpecker
Environment=WEBHOOK_PORT=9000
Environment=WEBHOOK_SECRET=your-secret
Environment=WOODPECKER_TOKEN=your-token
Environment=WOODPECKER_SERVER=http://localhost:8000
ExecStart=/opt/ci-cd/scripts/webhook-handler.sh --serve
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable webhook-handler
sudo systemctl start webhook-handler
```

---

## Polling Service

The polling service checks for changes when webhooks aren't available.

### Quick Start

```bash
# Start polling daemon
./scripts/poll-service.sh --start

# Run single poll cycle
./scripts/poll-service.sh --once

# Check specific repository
./scripts/poll-service.sh --check-repo myorg/myrepo

# View status
./scripts/poll-service.sh --status

# Stop service
./scripts/poll-service.sh --stop
```

### Configuration

Edit `config/webhook.yaml`:

```yaml
polling:
  enabled: true
  interval: 60  # seconds
  
  repositories:
    - myorg/myapp
    - myorg/another-repo
  
  checks:
    new_commits: true
    merged_prs: true
    new_tags: true
```

### How It Works

1. **State Tracking**: Maintains state in `/var/lib/poll-service/state.json`
2. **API Polling**: Checks Git provider API for changes
3. **Change Detection**: Compares current state to last known state
4. **Event Trigger**: Fires events when changes detected

```
Poll Cycle
    │
    ▼
┌─────────────────────┐
│ Load previous state │
│ (last known commit) │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Query Git API       │
│ (current commit)    │
└──────────┬──────────┘
           │
           ▼
     ┌─────┴─────┐
     │ Changed?  │
     └─────┬─────┘
       Yes │ No
     ┌─────┴─────┐
     │           │
     ▼           ▼
┌──────────┐  ┌──────────┐
│ Trigger  │  │ Sleep    │
│ Pipeline │  │ Interval │
└──────────┘  └──────────┘
```

### Running as a Service

```ini
# /etc/systemd/system/poll-service.service
[Unit]
Description=CI/CD Polling Service
After=network.target

[Service]
Type=simple
User=woodpecker
Environment=POLL_INTERVAL=60
Environment=GITHUB_TOKEN=your-token
Environment=WOODPECKER_TOKEN=your-token
Environment=WOODPECKER_SERVER=http://localhost:8000
ExecStart=/opt/ci-cd/scripts/poll-service.sh --start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## On-Merge Pipeline

The `pipelines/on-merge.yml` pipeline runs after a PR is merged.

### What It Does

1. **Displays merge information**
2. **Runs full test suite** (including integration tests)
3. **Builds production artifacts**
4. **Builds and pushes Docker image**
5. **Updates CHANGELOG.md**
6. **Triggers staging deployment**
7. **Creates release tag** (if conditions met)
8. **Sends notifications**

### Triggering

The on-merge pipeline is triggered by:

1. **Webhook**: When PR is closed with `merged: true`
2. **Polling**: When a new merge commit is detected on main
3. **Manual**: Via Woodpecker UI or API

### Release Tagging

A release tag is automatically created when:

- PR has a `release` label, OR
- Commit message starts with `release:`

```bash
# Example merge that creates release
git merge feature-branch -m "release: v1.2.0 - New features"
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `MERGE_PR_NUMBER` | PR number that was merged |
| `MERGE_HEAD_BRANCH` | Source branch |
| `MERGE_BASE_BRANCH` | Target branch |
| `MERGE_TITLE` | PR title |
| `MERGE_TIMESTAMP` | When merged |

---

## Configuration

### webhook.yaml

The main configuration file at `config/webhook.yaml`:

```yaml
# Webhook server settings
webhook:
  server:
    port: 9000
    bind: "0.0.0.0"
  security:
    require_signature: true
    secret: "${WEBHOOK_SECRET}"

# Event routing
events:
  push:
    enabled: true
    branches: [main, master, develop]
    actions: [trigger_pipeline]
  
  pull_request:
    enabled: true
    actions_filter: [opened, synchronize, closed]
    actions: [trigger_pipeline, update_status]
  
  merge:
    enabled: true
    target_branches: [main, master]
    actions: [trigger_deploy_pipeline, notify_slack]

# Polling settings
polling:
  enabled: true
  interval: 60
  repositories:
    - myorg/myapp
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WEBHOOK_PORT` | Server port | `9000` |
| `WEBHOOK_SECRET` | Signature secret | - |
| `GITHUB_TOKEN` | GitHub API token | - |
| `GITLAB_TOKEN` | GitLab API token | - |
| `WOODPECKER_SERVER` | Woodpecker URL | `http://localhost:8000` |
| `WOODPECKER_TOKEN` | Woodpecker API token | - |
| `SLACK_WEBHOOK` | Slack notification URL | - |

---

## Security

### Webhook Signature Validation

All major Git providers sign webhook payloads:

| Provider | Header | Algorithm |
|----------|--------|-----------|
| GitHub | `X-Hub-Signature-256` | HMAC-SHA256 |
| GitLab | `X-Gitlab-Token` | Token match |
| Gitea | `X-Gitea-Signature` | HMAC-SHA256 |

The webhook handler validates signatures automatically when `WEBHOOK_SECRET` is set.

### API Token Permissions

**GitHub Token** (for polling/API calls):
- `repo` - Access repositories
- `read:org` - Read organization data (optional)

**Woodpecker Token**:
- Generated via Woodpecker UI
- Has permission to trigger builds

### IP Whitelisting

For additional security, whitelist Git provider IPs:

```yaml
webhook:
  security:
    ip_whitelist:
      # GitHub webhook IPs (check GitHub docs for current list)
      - 192.30.252.0/22
      - 185.199.108.0/22
```

### HTTPS

For production, run behind a reverse proxy with HTTPS:

```nginx
# nginx configuration
server {
    listen 443 ssl;
    server_name webhook.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## Troubleshooting

### Webhooks Not Received

1. **Check webhook delivery status** in Git provider settings
2. **Verify server is accessible** from the internet
3. **Check firewall rules** allow incoming connections on webhook port
4. **Test with curl**:
   ```bash
   curl -X POST http://your-server:9000/webhook \
     -H "Content-Type: application/json" \
     -d '{"test": true}'
   ```

### Signature Validation Failing

1. **Verify secret matches** in both Git provider and webhook handler
2. **Check for encoding issues** - secret should be raw string
3. **Enable debug logging**:
   ```bash
   VERBOSE=true ./scripts/webhook-handler.sh --serve
   ```

### Polling Not Detecting Changes

1. **Check API token permissions**
2. **Verify rate limits** - GitHub has 5000 requests/hour
3. **Check state file**:
   ```bash
   cat /var/lib/poll-service/state.json
   ```
4. **Run manual check**:
   ```bash
   ./scripts/poll-service.sh --check-repo myorg/myrepo --verbose
   ```

### Pipeline Not Triggering

1. **Verify Woodpecker token** is valid
2. **Check Woodpecker server URL** is correct
3. **Test API connection**:
   ```bash
   curl -H "Authorization: Bearer $WOODPECKER_TOKEN" \
     $WOODPECKER_SERVER/api/user
   ```

### Debug Mode

Enable verbose logging:

```bash
# Webhook handler
VERBOSE=true ./scripts/webhook-handler.sh --serve

# Polling service
./scripts/poll-service.sh --once --verbose
```

### Log Files

- Webhook logs: `/var/log/webhook-handler.log`
- Polling logs: `/var/log/poll-service.log`

```bash
# View recent logs
tail -f /var/log/webhook-handler.log

# View polling state
cat /var/lib/poll-service/state.json | python3 -m json.tool
```

---

## File Reference

| File | Purpose |
|------|---------|
| `scripts/webhook-handler.sh` | Webhook receiver and processor |
| `scripts/poll-service.sh` | Polling service for change detection |
| `pipelines/on-merge.yml` | Pipeline triggered on PR merge |
| `config/webhook.yaml` | Webhook and polling configuration |
| `docs/WEBHOOKS.md` | This documentation |

---

## See Also

- [GitHub Webhooks](https://docs.github.com/en/webhooks)
- [GitLab Webhooks](https://docs.gitlab.com/ee/user/project/integrations/webhooks.html)
- [Gitea Webhooks](https://docs.gitea.io/en-us/webhooks/)
- [Woodpecker CI API](https://woodpecker-ci.org/docs/usage/api)
