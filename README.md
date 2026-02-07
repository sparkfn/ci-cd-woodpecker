# CI/CD Woodpecker Pipeline

An automated CI/CD system using Woodpecker CI with AI-powered auto-fix capabilities.

## Features

- 🔍 **Multi-project watching** — Monitor N repositories simultaneously
- 🧪 **Automated testing** — Run tests on every push/PR
- 🔒 **Security scanning** — Trivy integration for vulnerability detection
- 🤖 **AI Auto-fix** — Automatic code fixes using AI coding agents
- 📝 **Auto-issue creation** — Create GitHub issues on failures
- 🔀 **Auto-PR** — Automatically create PRs for fixes
- 🚀 **Deployment pipeline** — Staging → Production with gates
- 🔔 **Webhook + Polling** — Dual notification mechanism

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Woodpecker CI                            │
├─────────────────────────────────────────────────────────────────┤
│  Watch Repos → Test → Security Scan → Pass/Fail                │
│                                          │                      │
│                        ┌─────────────────┴──────────────┐       │
│                        ▼                                ▼       │
│                   [PASS]                            [FAIL]      │
│                      │                                 │        │
│                      ▼                                 ▼        │
│              Deploy Staging                    Create Issue     │
│                      │                                 │        │
│                      ▼                                 ▼        │
│              Deploy Test                        AI Auto-fix     │
│                      │                                 │        │
│              ┌───────┴───────┐                         ▼        │
│              ▼               ▼                    Create PR     │
│          [PASS]          [FAIL]                        │        │
│              │               │                         ▼        │
│              ▼               ▼                   Wait Merge     │
│         Deploy Live    Create Issue                    │        │
│                              │                         ▼        │
│                              ▼                    Re-trigger    │
│                        Wait Merge                               │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

1. **Clone and configure**
   ```bash
   cd ~/Dev/ci-cd-woodpecker
   cp .env.example .env
   # Edit .env with your values
   ```

2. **Set up GitHub App**
   ```bash
   ./scripts/setup-github-app.sh
   ```

3. **Start Woodpecker**
   ```bash
   docker compose up -d
   ```

4. **Access UI**
   - Woodpecker: http://localhost:8000

## Directory Structure

```
ci-cd-woodpecker/
├── docker-compose.yml      # Woodpecker server + agent
├── .env.example            # Environment template
├── CHANGELOG.md            # Version history
├── README.md               # This file
├── config/
│   └── woodpecker.conf     # Server configuration
├── pipelines/
│   ├── base.yml            # Base pipeline template
│   ├── security.yml        # Security scanning
│   ├── deploy.yml          # Deployment pipeline
│   └── ai-fix.yml          # AI auto-fix pipeline
├── scripts/
│   ├── setup-github-app.sh # GitHub App setup
│   ├── create-issue.sh     # Auto-issue creation
│   ├── create-pr.sh        # Auto-PR creation
│   ├── ai-fix.sh           # AI fix trigger
│   ├── webhook-handler.sh  # Webhook receiver
│   └── poll-service.sh     # Polling service
└── docs/
    ├── SETUP.md            # Detailed setup guide
    ├── PIPELINES.md        # Pipeline documentation
    └── TROUBLESHOOTING.md  # Common issues
```

## Requirements

- Docker & Docker Compose
- GitHub account with App/OAuth configured
- (Optional) AI coding agent (Claude Code, Codex, OpenHands)

## Configuration

See `.env.example` for all configuration options.

## License

MIT
