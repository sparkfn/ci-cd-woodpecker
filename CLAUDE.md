# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a CI/CD automation system built on **Woodpecker CI** with AI-powered auto-fix capabilities. It is an infrastructure/DevOps project — there is no application source code, build system, or test suite in this repo. The repo contains pipeline definitions (YAML), shell scripts, configuration files, and templates.

## Common Commands

```bash
# Start the Woodpecker CI server + agent
docker compose up -d

# View logs
docker compose logs -f woodpecker-server
docker compose logs -f woodpecker-agent

# Stop services
docker compose down

# Initial setup
cp .env.example .env          # then edit with real values
./scripts/setup-github-app.sh  # configure GitHub integration
```

### Script Usage

```bash
# AI auto-fix (triggered by failed pipelines)
./scripts/ai-fix.sh --error-file <path> --repo <path> [--provider claude-code|codex|openhands|opencode]

# Deployment
./scripts/deploy.sh --env staging --version 1.0.0 --app myapp --config ./config/deploy.yaml
./scripts/deploy.sh --env production --action status --app myapp

# Create GitHub issue on failure
./scripts/create-issue.sh --title "Build failed" --template pipeline-failure --repo owner/repo

# Create PR from fix branch
./scripts/create-pr.sh --source ai-fix/123 --target main --title "Fix: resolve test failure"

# Rollback
./scripts/rollback.sh --env production --app myapp
```

All scripts support `--dry-run` and `--verbose` flags.

## Architecture

The system follows this flow: **Watch Repos → Test → Security Scan → Pass/Fail**, then branches:

- **On pass:** Deploy staging → run deployment tests → deploy production (with automatic rollback on health check failure)
- **On fail:** Create GitHub issue → trigger AI auto-fix → create PR from fix → wait for merge → re-trigger pipeline

### Key Directories

- **`pipelines/`** — Modular Woodpecker pipeline definitions (YAML). `base.yml` provides reusable YAML anchors (`&base_step`, `&main_only`, `&pr_only`, `&tag_only`). Other pipelines import variables/patterns from it.
- **`scripts/`** — Bash scripts that implement the actual logic invoked by pipeline steps. All use `set -euo pipefail` and follow the same logging pattern (`log_info`, `log_success`, `log_warn`, `log_error`).
- **`config/`** — YAML configuration files consumed by scripts. `ai-fix.yaml` configures AI providers/strategies, `deploy.yaml` defines per-environment deployment settings, `webhook.yaml` configures event routing, `trivy.yaml` configures security scanning.
- **`config/issue-templates/`** — Markdown templates for auto-created GitHub issues (test-failure, build-failure, security-vulnerability, pipeline-failure).
- **`config/pr-templates/`** — Markdown templates for auto-created PRs (default, ai-fix, security-fix, hotfix, feature).

### Pipeline Relationships

1. **`.woodpecker.yml`** — Root pipeline for any repo using this system (validate → install → lint/typecheck → test → build → docker-build → release)
2. **`pipelines/on-failure.yml`** — Triggered on pipeline failure; creates issues, sends webhooks, archives failure artifacts
3. **`pipelines/ai-fix.yml`** — Triggered manually or by webhook; runs AI coding agent to fix the failure
4. **`pipelines/auto-pr.yml`** — Triggered after AI fix; creates a PR from the fix branch
5. **`pipelines/on-merge.yml`** — Triggered when PR merges to main; runs full tests, builds Docker image, triggers staging deploy
6. **`pipelines/deploy.yml`** — Staging → production deployment with health checks, rollback, and issue creation on failure
7. **`pipelines/security.yml`** — Trivy-based scanning (filesystem, dependencies, secrets, IaC, Docker images, SBOM generation)

### AI Auto-fix System

The AI fix loop is configured in `config/ai-fix.yaml` and executed by `scripts/ai-fix.sh`. Supported providers: `claude-code` (priority 1), `codex` (priority 2), `openhands`, `opencode`. The system:
1. Creates a fix branch from the default branch
2. Runs the AI provider with error context (up to `max_attempts` times, default 3)
3. Verifies the fix by running the project's test suite
4. Commits, pushes, and triggers auto-PR creation
5. Rolls back on verification failure

Safety limits are defined in `config/ai-fix.yaml` under `safety:` (max 20 files, 500 lines changed; protected files like `.env`, `*.pem`, `*.key`).

### Dual Notification Mechanism

Events are detected via either GitHub webhooks (`scripts/webhook-handler.sh`, configured in `config/webhook.yaml`) or polling (`scripts/poll-service.sh`) for environments where webhooks are unavailable.

## Configuration

All configuration flows through environment variables (`.env` file) and YAML config files. The `.env.example` documents every variable. Key secrets that must be set:
- `WOODPECKER_AGENT_SECRET` — server-agent auth (generate with `openssl rand -hex 32`)
- `WOODPECKER_GITHUB_CLIENT` / `WOODPECKER_GITHUB_SECRET` — GitHub OAuth
- `GITHUB_TOKEN` — for issue/PR creation
- `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` — for AI auto-fix
- `WEBHOOK_SECRET` — webhook signature validation

Deployment config (`config/deploy.yaml`) supports multiple methods per environment: `docker`, `docker-compose`, `ssh`, `kubernetes`, `helm`. The deploy script parses this YAML using `yq` (preferred) or `python3` as fallback.
