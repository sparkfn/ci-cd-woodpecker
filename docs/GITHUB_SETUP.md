# GitHub Integration Setup Guide

This guide walks you through setting up GitHub integration for Woodpecker CI. You can choose between two authentication methods:

1. **GitHub OAuth App** - Simpler, user-based authentication
2. **GitHub App** - More granular permissions, app-based authentication

---

## Table of Contents

- [Quick Start](#quick-start)
- [Option 1: GitHub OAuth App](#option-1-github-oauth-app)
- [Option 2: GitHub App](#option-2-github-app)
- [Personal Access Token](#personal-access-token)
- [Testing Your Setup](#testing-your-setup)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

---

## Quick Start

Run the interactive setup script:

```bash
./scripts/setup-github-app.sh
```

Or choose a specific method:

```bash
# OAuth App setup
./scripts/setup-github-app.sh --oauth

# GitHub App setup
./scripts/setup-github-app.sh --app
```

---

## Option 1: GitHub OAuth App

OAuth Apps are the simpler option and work well for personal projects or small teams.

### Step 1: Create the OAuth App

1. Go to [GitHub Developer Settings](https://github.com/settings/developers)
2. Click **"New OAuth App"**
3. Fill in the details:

   | Field | Value |
   |-------|-------|
   | Application name | `Woodpecker CI` |
   | Homepage URL | `http://localhost:8000` (or your public URL) |
   | Authorization callback URL | `http://localhost:8000/authorize` |

4. Click **"Register application"**

### Step 2: Get Credentials

After creating the app:

1. Copy the **Client ID** (shown immediately)
2. Click **"Generate a new client secret"**
3. Copy the **Client Secret** (you won't see it again!)

### Step 3: Configure Woodpecker

Add to your `.env` file:

```bash
WOODPECKER_GITHUB=true
WOODPECKER_GITHUB_CLIENT=your-client-id
WOODPECKER_GITHUB_SECRET=your-client-secret
```

### Step 4: Verify Configuration

```bash
# Check your configuration
grep -E "WOODPECKER_GITHUB" .env
```

---

## Option 2: GitHub App

GitHub Apps provide finer-grained permissions and are recommended for:
- Organizations with multiple repositories
- Private repositories
- Automated workflows (issues, PRs)

### Step 1: Create the GitHub App

1. Go to [GitHub Apps Settings](https://github.com/settings/apps)
2. Click **"New GitHub App"**
3. Fill in the basic information:

   | Field | Value |
   |-------|-------|
   | GitHub App name | `Woodpecker CI` (must be globally unique) |
   | Homepage URL | `http://localhost:8000` |
   | Callback URL | `http://localhost:8000/authorize` |
   | Setup URL (optional) | Leave blank |
   | Webhook URL | `https://your-public-url.com/hook` |
   | Webhook secret | Generate a secure random string |

### Step 2: Set Permissions

Configure the following permissions:

#### Repository Permissions

| Permission | Access Level | Purpose |
|------------|--------------|---------|
| Contents | Read & Write | Clone repos, read code, push fixes |
| Metadata | Read-only | Basic repository info |
| Pull requests | Read & Write | Create/update PRs for auto-fixes |
| Commit statuses | Read & Write | Report build status |
| Checks | Read & Write | Create check runs |
| Issues | Read & Write | Create issues on failures |

#### Organization Permissions (if applicable)

| Permission | Access Level | Purpose |
|------------|--------------|---------|
| Members | Read-only | List org members for access control |

### Step 3: Subscribe to Events

Check the following events:

- [x] Push
- [x] Pull request
- [x] Pull request review
- [x] Create
- [x] Delete
- [x] Check run
- [x] Check suite

### Step 4: Create the App

1. Set **"Where can this GitHub App be installed?"** to:
   - **Only on this account** (for personal use)
   - **Any account** (for public distribution)

2. Click **"Create GitHub App"**

### Step 5: Generate Private Key

1. On the app page, scroll to **"Private keys"**
2. Click **"Generate a private key"**
3. Download the `.pem` file
4. Move it to your config directory:

```bash
mv ~/Downloads/your-app-name.*.private-key.pem config/github-app-private-key.pem
chmod 600 config/github-app-private-key.pem
```

### Step 6: Note the App ID

The **App ID** is shown at the top of the app settings page (e.g., `123456`).

### Step 7: Configure Woodpecker

Add to your `.env` file:

```bash
WOODPECKER_GITHUB=true
WOODPECKER_GITHUB_APP_ID=123456
WOODPECKER_GITHUB_APP_PRIVATE_KEY=/config/github-app-private-key.pem
```

### Step 8: Install the App

1. Go to your app's settings
2. Click **"Install App"** in the sidebar
3. Select the account/organization
4. Choose repositories to enable
5. Click **"Install"**

---

## Personal Access Token

A Personal Access Token (PAT) is required for certain automation features:

- Creating issues on pipeline failures
- Creating pull requests with auto-fixes
- API calls beyond the GitHub App scope

### Creating a PAT

1. Go to [GitHub Token Settings](https://github.com/settings/tokens)
2. Click **"Generate new token (classic)"** or **"Fine-grained tokens"**

### Classic Token Scopes

| Scope | Purpose |
|-------|---------|
| `repo` | Full repository access |
| `workflow` | Workflow/Actions access |
| `admin:org` | Organization access (if needed) |

### Fine-Grained Token Permissions

For fine-grained tokens, grant access to:
- **Contents**: Read and write
- **Issues**: Read and write
- **Pull requests**: Read and write
- **Workflows**: Read and write

### Configure the Token

Add to your `.env` file:

```bash
GITHUB_TOKEN=ghp_your-personal-access-token
```

---

## Testing Your Setup

### 1. Start Woodpecker

```bash
docker compose up -d
```

### 2. Check Logs

```bash
docker compose logs -f woodpecker-server
```

### 3. Access the UI

Open http://localhost:8000 in your browser.

### 4. Login with GitHub

Click "Login" and authorize the application.

### 5. Activate a Repository

1. Go to "Repositories"
2. Find your repository
3. Click "Activate"

### 6. Trigger a Build

Push a commit or create a `.woodpecker.yml` file:

```yaml
steps:
  test:
    image: alpine
    commands:
      - echo "Hello from Woodpecker!"
```

---

## Troubleshooting

### "Unauthorized" Error on Login

**Cause**: Invalid OAuth credentials

**Fix**:
1. Verify Client ID and Secret in `.env`
2. Check callback URL matches exactly
3. Regenerate client secret if needed

### "Webhook Not Received" Error

**Cause**: GitHub can't reach your Woodpecker server

**Fix**:
1. Ensure `WOODPECKER_HOST` is publicly accessible
2. Check firewall rules
3. Verify webhook URL in GitHub App settings
4. Use ngrok for local testing: `ngrok http 8000`

### "Permission Denied" for Private Repos

**Cause**: Insufficient permissions

**Fix**:
1. For OAuth: Ensure user has access to the repo
2. For GitHub App: Check app is installed on the repository
3. For PAT: Verify `repo` scope is enabled

### "Agent Not Connected" Error

**Cause**: Agent can't reach server

**Fix**:
1. Check `WOODPECKER_AGENT_SECRET` matches in both containers
2. Verify network connectivity
3. Check server health: `docker compose ps`

### Private Key Issues

**Cause**: Invalid or inaccessible private key

**Fix**:
```bash
# Check key file exists
ls -la config/github-app-private-key.pem

# Verify permissions
chmod 600 config/github-app-private-key.pem

# Validate key format
openssl rsa -in config/github-app-private-key.pem -check
```

---

## Security Best Practices

### Protect Your Secrets

1. **Never commit secrets** to version control
2. Use `.gitignore` to exclude:
   - `.env`
   - `*.pem`
   - `*.key`

3. Use environment variables or secret managers in production

### Rotate Credentials Regularly

| Credential | Rotation Frequency |
|------------|-------------------|
| OAuth Client Secret | Every 90 days |
| GitHub App Private Key | Every 6 months |
| Personal Access Token | Every 30-90 days |
| Agent Secret | When agents are added/removed |

### Limit Permissions

- Only grant necessary permissions to the GitHub App
- Use fine-grained PATs when possible
- Limit repository access to what's needed

### Audit Access

Regularly review:
- GitHub App installations
- OAuth App authorizations
- Token usage in GitHub security settings

### Secure Webhooks

1. Always use webhook secrets
2. Use HTTPS for webhook URLs
3. Validate webhook signatures in your code

---

## Environment Variables Reference

### OAuth App

| Variable | Required | Description |
|----------|----------|-------------|
| `WOODPECKER_GITHUB` | Yes | Set to `true` |
| `WOODPECKER_GITHUB_CLIENT` | Yes | OAuth Client ID |
| `WOODPECKER_GITHUB_SECRET` | Yes | OAuth Client Secret |

### GitHub App

| Variable | Required | Description |
|----------|----------|-------------|
| `WOODPECKER_GITHUB` | Yes | Set to `true` |
| `WOODPECKER_GITHUB_APP_ID` | Yes | GitHub App ID |
| `WOODPECKER_GITHUB_APP_PRIVATE_KEY` | Yes | Path to private key PEM file |

### Common

| Variable | Required | Description |
|----------|----------|-------------|
| `WOODPECKER_HOST` | Yes | Public URL of your Woodpecker server |
| `WOODPECKER_ADMIN` | Recommended | GitHub username(s) with admin access |
| `GITHUB_TOKEN` | Optional | PAT for issue/PR automation |

---

## Need Help?

- [Woodpecker Documentation](https://woodpecker-ci.org/docs)
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [GitHub OAuth Apps Documentation](https://docs.github.com/en/apps/oauth-apps)

Report issues at: [Your Issue Tracker]
