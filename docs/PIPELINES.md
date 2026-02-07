# Woodpecker CI Pipeline Documentation

> Comprehensive guide to the CI/CD pipeline templates in this project.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Pipeline Files](#pipeline-files)
- [Configuration Reference](#configuration-reference)
- [Pipeline Stages](#pipeline-stages)
- [Customization](#customization)
- [Secrets Management](#secrets-management)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project provides production-ready Woodpecker CI pipeline templates that can be used as-is or customized for your specific needs.

### Features

- ✅ **Auto-detection** - Automatically detects package managers (npm, yarn, pnpm)
- ✅ **Parallel execution** - Lint and typecheck run in parallel for faster builds
- ✅ **Multi-stage builds** - Clear separation of concerns (validate → install → test → build)
- ✅ **Docker support** - Built-in Docker image building with multi-arch support
- ✅ **Conditional execution** - Steps run only when relevant files change
- ✅ **Skip CI** - Supports `[skip ci]` in commit messages
- ✅ **Notifications** - Success/failure notifications built-in

---

## Quick Start

### 1. Copy the Pipeline File

Copy `.woodpecker.yml` to your repository root:

```bash
cp .woodpecker.yml /path/to/your/repo/
```

### 2. Enable Woodpecker for Your Repository

1. Go to your Woodpecker CI dashboard
2. Click "Add Repository"
3. Select your repository
4. Woodpecker will automatically detect the `.woodpecker.yml` file

### 3. Push Changes

```bash
git add .woodpecker.yml
git commit -m "Add Woodpecker CI pipeline"
git push
```

Your pipeline will run automatically on the next push!

---

## Pipeline Files

### `.woodpecker.yml`

The main pipeline file that goes in your repository root. This is a complete, ready-to-use pipeline.

**Location:** Repository root  
**Purpose:** Main CI/CD pipeline for your project

### `pipelines/base.yml`

A reusable template with common pipeline patterns and YAML anchors.

**Location:** `pipelines/base.yml`  
**Purpose:** Reference template for creating custom pipelines

### `pipelines/security.yml`

Security scanning pipeline using Trivy for vulnerability detection.

**Location:** `pipelines/security.yml`  
**Purpose:** Container and dependency vulnerability scanning

### `pipelines/on-failure.yml`

Failure handling pipeline that creates GitHub issues automatically.

**Location:** `pipelines/on-failure.yml`  
**Purpose:** Automatic issue creation on pipeline failures

---

## Configuration Reference

### Environment Variables

Woodpecker provides these built-in variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `CI_REPO` | Full repository name | `myorg/myrepo` |
| `CI_REPO_OWNER` | Repository owner | `myorg` |
| `CI_REPO_NAME` | Repository name | `myrepo` |
| `CI_COMMIT_SHA` | Full commit SHA | `abc123def456...` |
| `CI_COMMIT_BRANCH` | Branch name | `main` |
| `CI_COMMIT_TAG` | Tag name (if tagged) | `v1.0.0` |
| `CI_COMMIT_MESSAGE` | Commit message | `Fix bug #123` |
| `CI_COMMIT_AUTHOR` | Commit author | `john@example.com` |
| `CI_PIPELINE_NUMBER` | Pipeline number | `42` |
| `CI_PIPELINE_EVENT` | Event type | `push`, `pull_request`, `tag` |

### Secrets

Configure secrets in the Woodpecker UI under Repository → Settings → Secrets:

| Secret | Purpose |
|--------|---------|
| `docker_username` | Docker registry username |
| `docker_password` | Docker registry password/token |
| `github_token` | GitHub API token for releases |

### Labels

Use labels to select specific agents:

```yaml
labels:
  platform: linux/amd64    # Architecture
  backend: docker          # Agent type
  # Custom labels for agent selection:
  # gpu: nvidia            # Select GPU-enabled agents
```

---

## Pipeline Stages

The pipeline executes in these stages:

```
┌─────────────────────────────────────────────────────────────────┐
│ Stage 1: Setup & Validation                                      │
│ └── validate                                                     │
├─────────────────────────────────────────────────────────────────┤
│ Stage 2: Dependencies                                            │
│ └── install                                                      │
├─────────────────────────────────────────────────────────────────┤
│ Stage 3: Quality Checks (parallel)                               │
│ ├── lint                                                         │
│ └── typecheck                                                    │
├─────────────────────────────────────────────────────────────────┤
│ Stage 4: Testing                                                 │
│ └── test                                                         │
├─────────────────────────────────────────────────────────────────┤
│ Stage 5: Build                                                   │
│ └── build                                                        │
├─────────────────────────────────────────────────────────────────┤
│ Stage 6: Docker Build (main branch only)                         │
│ └── docker-build                                                 │
├─────────────────────────────────────────────────────────────────┤
│ Stage 7: Release (tags only)                                     │
│ └── release                                                      │
└─────────────────────────────────────────────────────────────────┘
```

### Stage Details

#### validate
- Prints pipeline information for debugging
- Always runs first
- Helps identify configuration issues

#### install
- Auto-detects package manager (npm, yarn, pnpm)
- Uses lockfile for reproducible builds
- Caches can be added for faster builds

#### lint & typecheck
- Run in parallel to save time
- Skip gracefully if not configured
- Detect TypeScript projects automatically

#### test
- Runs after lint/typecheck pass
- Detects test framework from package.json
- Fails the pipeline on test failures

#### build
- Compiles/bundles the application
- Only runs after tests pass
- Output can be cached for Docker builds

#### docker-build
- Only runs on main/master branch
- Multi-architecture support (amd64, arm64)
- Dry-run by default (set `dry_run: false` to push)

#### release
- Only runs on git tags
- Can publish to npm, create GitHub releases, etc.

---

## Customization

### Adding Custom Steps

```yaml
steps:
  # ... existing steps ...

  my-custom-step:
    image: alpine:latest
    commands:
      - echo "Running custom step"
      - ./scripts/my-script.sh
    depends_on:
      - build
    when:
      - event: push
        branch: main
```

### Adding Services

```yaml
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
      POSTGRES_DB: testdb

  redis:
    image: redis:7-alpine
```

Access services by their name (e.g., `postgres:5432`).

### Path-Based Triggers

Only run steps when specific files change:

```yaml
when:
  - event: push
    path:
      include:
        - "src/**"
        - "package.json"
      exclude:
        - "docs/**"
        - "*.md"
```

### Matrix Builds

Run the same steps with different configurations:

```yaml
matrix:
  include:
    - NODE_VERSION: 18
    - NODE_VERSION: 20
    - NODE_VERSION: 22

steps:
  test:
    image: node:${NODE_VERSION}-alpine
    commands:
      - npm test
```

### Caching

Speed up builds with caching:

```yaml
steps:
  restore-cache:
    image: meltwater/drone-cache
    settings:
      backend: filesystem
      restore: true
      cache_key: "npm-{{ checksum 'package-lock.json' }}"
      mount:
        - node_modules

  install:
    # ... install step ...

  save-cache:
    image: meltwater/drone-cache
    settings:
      backend: filesystem
      rebuild: true
      cache_key: "npm-{{ checksum 'package-lock.json' }}"
      mount:
        - node_modules
```

---

## Secrets Management

### Adding Secrets

1. Go to Woodpecker UI → Repository → Settings → Secrets
2. Add a new secret with name and value
3. Reference in pipeline:

```yaml
steps:
  deploy:
    image: alpine:latest
    environment:
      API_KEY:
        from_secret: api_key
    commands:
      - echo "Deploying with API key..."
```

### Secret Scopes

- **Repository secrets** - Available to all pipelines in a repo
- **Organization secrets** - Shared across all repos in an org
- **Global secrets** - Available to all repos (admin only)

### Limiting Secret Exposure

```yaml
settings:
  password:
    from_secret: docker_password
  # Secret is passed to plugin, not exposed in logs
```

---

## Troubleshooting

### Pipeline Not Triggering

1. Check `.woodpecker.yml` is in the repository root
2. Verify the repository is enabled in Woodpecker
3. Check the `when` conditions match your event

### Step Failing

1. Check the step logs in Woodpecker UI
2. Ensure required secrets are configured
3. Test commands locally first

### Docker Build Issues

1. Verify Dockerfile exists and is valid
2. Check registry credentials are correct
3. Ensure agent has Docker access

### Skipping CI

Add `[skip ci]` or `[ci skip]` to your commit message:

```bash
git commit -m "Update README [skip ci]"
```

### Debugging

Add debug output to any step:

```yaml
steps:
  debug:
    image: alpine:latest
    commands:
      - env | sort          # Print all environment variables
      - ls -la              # List files
      - cat .woodpecker.yml # Show pipeline config
```

---

## Best Practices

1. **Keep pipelines fast** - Parallelize where possible
2. **Use caching** - Avoid downloading dependencies every time
3. **Fail early** - Run quick checks (lint) before slow ones (tests)
4. **Use specific images** - Pin versions (e.g., `node:20-alpine` not `node:latest`)
5. **Limit secrets** - Only expose secrets to steps that need them
6. **Document changes** - Update this file when modifying pipelines

---

## Related Documentation

- [Woodpecker CI Documentation](https://woodpecker-ci.org/docs/intro)
- [Pipeline Syntax](https://woodpecker-ci.org/docs/usage/pipeline-syntax)
- [Plugins Index](https://woodpecker-ci.org/plugins)
- [Environment Variables](https://woodpecker-ci.org/docs/usage/environment)
