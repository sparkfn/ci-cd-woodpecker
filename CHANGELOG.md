# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.12] - 2026-02-08

### Added
- Webhook handler Docker service (`docker/webhook-handler/Dockerfile`)
- Traefik `/webhooks` route to webhook-handler container (priority 200, StripPrefix middleware)
- Webhook deploy pipeline trigger on Dockerfile changes
- Webhook log persistence directory (`data/logs/webhook/`)

### Changed
- Traefik priority labels: woodpecker-server `100`, webhook-handler `200`
- `.env.example`: updated `WEBHOOK_ENDPOINT` default to `https://ci.sparkfn.io/webhooks`, added `WEBHOOK_PORT`, `WOODPECKER_TOKEN`, `WEBHOOK_VERBOSE`
- `docs/WEBHOOKS.md`: added Docker deployment section, updated payload URLs, updated architecture diagram

## [0.0.11] - 2026-02-07

### Fixed
- Agent healthcheck: use `/bin/woodpecker-agent ping` instead of `pgrep` (distroless image)

### Validated
- End-to-end pipeline for `whatsappWebJs_api` trial (install → wait-for-db → test → build)
- Pipeline failure notification: auto-creates GitHub issue on both API and frontend repos
- `notify-failure` step correctly skips on success, triggers on failure

## [0.0.10] - 2026-02-07

### Fixed
- Pin Woodpecker images to `v3.13.0` (rolling `v3` tag caused server/agent version mismatch)
- Upgrade from Woodpecker v2 to v3 (v2 `latest` tag pulled buggy v2.8.3)
- Use `woodpecker-server ping` for healthcheck (distroless image has no wget/curl)
- Use external `traefik` network only (avoid Docker subnet pool exhaustion)
- Update data mount path to `/var/lib/woodpecker` (v3 default)
- Add `command: agent` to agent service (required in v3)
- Configure Docker daemon address pools (`/24` subnets) to support pipeline network creation

### Validated
- End-to-end pipeline execution with `whatsappWebJs_frontend` trial
- GitHub webhook → Woodpecker → clone → install → lint → test → build flow confirmed working

## [0.0.9] - 2026-02-07

### Added
- **Server Deployment with Traefik Integration**
  - Updated `docker-compose.yml` with production ports (8090/9090)
  - Traefik reverse proxy labels for `ci.sparkfn.io` with HTTPS
  - Connected to external `traefik` network
  - Configurable `WOODPECKER_OPEN` for initial setup
  - Created `data/woodpecker/` and `data/logs/` subdirectories

### Changed
- Default host port from 8000 → 8090 (avoids conflict with existing services)
- Default gRPC port from 9000 → 9090
- Updated `.env.example` with new port defaults and host URL

### Infrastructure
- Closes #1

## [0.0.8] - 2026-02-07

### Added
- **Auto-PR Creation System**
  - `scripts/create-pr.sh` - GitHub PR creation script with full API integration
  - `pipelines/auto-pr.yml` - Woodpecker pipeline for automatic PR creation
  - `config/pr-templates/` - Directory with PR templates:
    - `default.md` - Standard PR template
    - `ai-fix.md` - Template for AI-generated fixes
    - `security-fix.md` - Template for security vulnerability fixes
    - `hotfix.md` - Template for urgent production fixes
    - `feature.md` - Template for new features

### Features
- Automatic PR creation from fix branches
- Support for draft PRs
- Auto-merge capability when checks pass
- Label management and auto-labeling based on branch name
- Reviewer assignment (individual and team)
- Issue linking with automatic comments
- Template selection based on branch type
- Webhook notifications for PR events

## [0.0.7] - 2026-02-07

### Added
- **AI Auto-fix Integration**
  - `scripts/ai-fix.sh` - AI fix trigger script supporting multiple providers
  - `pipelines/ai-fix.yml` - Woodpecker pipeline for AI-powered fixes
  - `config/ai-fix.yaml` - Comprehensive AI fix configuration
  - `docs/AI_FIX.md` - Complete documentation for AI auto-fix system

### Features
- Support for multiple AI providers:
  - Claude Code (Anthropic) - recommended for complex fixes
  - OpenAI Codex / GPT-4 - general purpose fixing
  - OpenHands (formerly OpenDevin) - full environment simulation
  - OpenCode - lightweight CLI agent
- Multiple fix strategies:
  - Test failure fixes
  - Security vulnerability patches
  - Lint/format error corrections
  - Build failure resolution
- Safety features:
  - Protected file lists
  - Change limits (files/lines)
  - Automatic rollback on verification failure
  - Backup branch creation
- Configurable retry attempts with timeout
- Dry-run mode for testing
- Detailed logging and interaction saving

## [0.0.1] - 2026-02-07

### Added
- Initial project scaffolding
- README.md with architecture overview
- .env.example with all configuration options
- Directory structure (scripts/, pipelines/, config/, docs/)
- CHANGELOG.md

### Project Structure
```
ci-cd-woodpecker/
├── README.md
├── .env.example
├── CHANGELOG.md
├── config/
│   ├── ai-fix.yaml
│   └── pr-templates/
│       ├── default.md
│       ├── ai-fix.md
│       ├── security-fix.md
│       ├── hotfix.md
│       └── feature.md
├── docs/
│   └── AI_FIX.md
├── pipelines/
│   ├── ai-fix.yml
│   └── auto-pr.yml
└── scripts/
    ├── ai-fix.sh
    └── create-pr.sh
```

---

## Planned Releases

### [0.0.2] - Docker Compose Setup
- Woodpecker server container
- Woodpecker agent container
- Volume bindings for persistence
- Network configuration

### [0.0.3] - GitHub Integration
- GitHub OAuth App setup script
- GitHub App configuration
- Token management

### [0.0.4] - Base Pipeline Template
- .woodpecker.yml template
- Multi-project configuration
- Basic test pipeline

### [0.0.5] - Security Scanning
- Trivy integration
- Vulnerability reporting
- Severity thresholds

### [0.0.6] - Auto-issue Creation
- GitHub issue creation on failure
- Issue templates
- Label management

### [0.0.9] - Deployment Pipeline
- Staging deployment
- Production deployment
- Rollback support

### [0.0.10] - Webhook & Polling
- Webhook receiver service
- Polling service
- Event routing
