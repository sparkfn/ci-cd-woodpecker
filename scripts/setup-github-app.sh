#!/usr/bin/env bash
# =============================================================================
# GitHub Integration Setup Script for Woodpecker CI
# =============================================================================
# Version: 0.0.3
#
# This script helps you set up GitHub integration for Woodpecker CI.
# It supports both GitHub OAuth App and GitHub App authentication methods.
#
# Usage:
#   ./scripts/setup-github-app.sh [--oauth|--app]
#
# Options:
#   --oauth    Configure GitHub OAuth App (simpler, good for public repos)
#   --app      Configure GitHub App (recommended for private repos)
#   --help     Show this help message
#
# Prerequisites:
#   - GitHub account with admin access to target repositories
#   - .env file created from .env.example
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
CONFIG_DIR="$PROJECT_DIR/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}→${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    
    if [[ -n "$default" ]]; then
        read -rp "$(echo -e "${BLUE}?${NC} $prompt [${default}]: ")" value
        eval "$var_name=\"${value:-$default}\""
    else
        read -rp "$(echo -e "${BLUE}?${NC} $prompt: ")" value
        eval "$var_name=\"$value\""
    fi
}

prompt_secret() {
    local prompt="$1"
    local var_name="$2"
    
    read -rsp "$(echo -e "${BLUE}?${NC} $prompt: ")" value
    echo ""
    eval "$var_name=\"$value\""
}

prompt_confirm() {
    local prompt="$1"
    read -rp "$(echo -e "${BLUE}?${NC} $prompt (y/N): ")" response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

check_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        print_warning ".env file not found"
        print_step "Creating .env from .env.example..."
        if [[ -f "$PROJECT_DIR/.env.example" ]]; then
            cp "$PROJECT_DIR/.env.example" "$ENV_FILE"
            print_success "Created .env file"
        else
            print_error ".env.example not found. Please create .env manually."
            exit 1
        fi
    fi
}

update_env_var() {
    local key="$1"
    local value="$2"
    local file="$ENV_FILE"
    
    # Escape special characters in value for sed
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')
    
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        # Update existing value
        sed -i.bak "s/^${key}=.*/${key}=${escaped_value}/" "$file"
        rm -f "${file}.bak"
    elif grep -q "^# *${key}=" "$file" 2>/dev/null; then
        # Uncomment and set value
        sed -i.bak "s/^# *${key}=.*/${key}=${escaped_value}/" "$file"
        rm -f "${file}.bak"
    else
        # Append new variable
        echo "${key}=${value}" >> "$file"
    fi
}

generate_secret() {
    openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p
}

# -----------------------------------------------------------------------------
# OAuth App Setup
# -----------------------------------------------------------------------------

setup_oauth_app() {
    print_header "GitHub OAuth App Setup"
    
    print_info "GitHub OAuth Apps are simpler to set up and work well for most use cases."
    print_info "They authenticate users via OAuth 2.0 flow."
    echo ""
    
    print_step "Please follow these steps to create a GitHub OAuth App:"
    echo ""
    echo "   1. Go to: https://github.com/settings/developers"
    echo "   2. Click 'New OAuth App'"
    echo "   3. Fill in the application details:"
    echo ""
    echo "      Application name: Woodpecker CI"
    echo "      Homepage URL: http://localhost:8000"
    echo "      Authorization callback URL: http://localhost:8000/authorize"
    echo ""
    echo "   4. Click 'Register application'"
    echo "   5. Copy the Client ID and generate a Client Secret"
    echo ""
    
    if ! prompt_confirm "Have you created the OAuth App?"; then
        print_info "Come back when you've created the OAuth App."
        exit 0
    fi
    
    echo ""
    prompt_input "Enter GitHub OAuth Client ID" GITHUB_CLIENT_ID
    prompt_secret "Enter GitHub OAuth Client Secret" GITHUB_CLIENT_SECRET
    
    if [[ -z "$GITHUB_CLIENT_ID" || -z "$GITHUB_CLIENT_SECRET" ]]; then
        print_error "Client ID and Secret are required"
        exit 1
    fi
    
    print_step "Updating .env file..."
    update_env_var "WOODPECKER_GITHUB" "true"
    update_env_var "WOODPECKER_GITHUB_CLIENT" "$GITHUB_CLIENT_ID"
    update_env_var "WOODPECKER_GITHUB_SECRET" "$GITHUB_CLIENT_SECRET"
    
    # Ensure GitHub App vars are commented out
    sed -i.bak 's/^WOODPECKER_GITHUB_APP_ID=/# WOODPECKER_GITHUB_APP_ID=/' "$ENV_FILE" 2>/dev/null || true
    rm -f "${ENV_FILE}.bak"
    
    print_success "OAuth App configuration saved!"
    
    setup_admin_user
    setup_agent_secret
    
    print_summary "OAuth App"
}

# -----------------------------------------------------------------------------
# GitHub App Setup
# -----------------------------------------------------------------------------

setup_github_app() {
    print_header "GitHub App Setup"
    
    print_info "GitHub Apps provide finer-grained permissions and are recommended"
    print_info "for private repositories and organization-level access."
    echo ""
    
    print_step "Please follow these steps to create a GitHub App:"
    echo ""
    echo "   1. Go to: https://github.com/settings/apps"
    echo "   2. Click 'New GitHub App'"
    echo "   3. Fill in the application details:"
    echo ""
    echo "      GitHub App name: Woodpecker CI (must be unique)"
    echo "      Homepage URL: http://localhost:8000"
    echo "      Callback URL: http://localhost:8000/authorize"
    echo "      Webhook URL: http://your-public-url:8000/hook"
    echo "      Webhook secret: (generate a secure random string)"
    echo ""
    echo "   4. Set the required permissions:"
    echo "      Repository permissions:"
    echo "        - Contents: Read & Write"
    echo "        - Metadata: Read-only"
    echo "        - Pull requests: Read & Write"
    echo "        - Commit statuses: Read & Write"
    echo "      Subscribe to events:"
    echo "        - Push"
    echo "        - Pull request"
    echo "        - Create"
    echo "        - Delete"
    echo ""
    echo "   5. Click 'Create GitHub App'"
    echo "   6. Note the App ID shown at the top"
    echo "   7. Generate a private key (scroll down to 'Private keys')"
    echo "   8. Download the .pem file"
    echo ""
    
    if ! prompt_confirm "Have you created the GitHub App?"; then
        print_info "Come back when you've created the GitHub App."
        exit 0
    fi
    
    echo ""
    prompt_input "Enter GitHub App ID" GITHUB_APP_ID
    prompt_input "Enter path to private key .pem file" PRIVATE_KEY_PATH
    
    if [[ -z "$GITHUB_APP_ID" ]]; then
        print_error "App ID is required"
        exit 1
    fi
    
    if [[ ! -f "$PRIVATE_KEY_PATH" ]]; then
        print_error "Private key file not found: $PRIVATE_KEY_PATH"
        exit 1
    fi
    
    # Copy private key to config directory
    print_step "Copying private key to config directory..."
    mkdir -p "$CONFIG_DIR"
    cp "$PRIVATE_KEY_PATH" "$CONFIG_DIR/github-app-private-key.pem"
    chmod 600 "$CONFIG_DIR/github-app-private-key.pem"
    print_success "Private key copied to config/github-app-private-key.pem"
    
    print_step "Updating .env file..."
    update_env_var "WOODPECKER_GITHUB" "true"
    update_env_var "WOODPECKER_GITHUB_APP_ID" "$GITHUB_APP_ID"
    update_env_var "WOODPECKER_GITHUB_APP_PRIVATE_KEY" "/config/github-app-private-key.pem"
    
    # Comment out OAuth vars
    sed -i.bak 's/^WOODPECKER_GITHUB_CLIENT=/# WOODPECKER_GITHUB_CLIENT=/' "$ENV_FILE" 2>/dev/null || true
    sed -i.bak 's/^WOODPECKER_GITHUB_SECRET=/# WOODPECKER_GITHUB_SECRET=/' "$ENV_FILE" 2>/dev/null || true
    rm -f "${ENV_FILE}.bak"
    
    # Create GitHub App config JSON
    print_step "Creating GitHub App configuration..."
    cat > "$CONFIG_DIR/github-app.json" << EOF
{
  "app_id": "${GITHUB_APP_ID}",
  "private_key_path": "/config/github-app-private-key.pem",
  "webhook_secret": "",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    print_success "GitHub App configuration saved!"
    
    setup_admin_user
    setup_agent_secret
    
    print_summary "GitHub App"
}

# -----------------------------------------------------------------------------
# Common Setup Functions
# -----------------------------------------------------------------------------

setup_admin_user() {
    print_header "Admin User Setup"
    
    prompt_input "Enter your GitHub username (for admin access)" ADMIN_USER
    
    if [[ -n "$ADMIN_USER" ]]; then
        update_env_var "WOODPECKER_ADMIN" "$ADMIN_USER"
        print_success "Admin user set to: $ADMIN_USER"
    fi
}

setup_agent_secret() {
    print_header "Agent Secret Setup"
    
    # Check if secret already exists
    current_secret=$(grep "^WOODPECKER_AGENT_SECRET=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
    
    if [[ -n "$current_secret" && "$current_secret" != "your-agent-secret-here" ]]; then
        print_info "Agent secret already configured."
        if ! prompt_confirm "Generate a new agent secret?"; then
            return
        fi
    fi
    
    print_step "Generating secure agent secret..."
    agent_secret=$(generate_secret)
    update_env_var "WOODPECKER_AGENT_SECRET" "$agent_secret"
    print_success "Agent secret generated and saved!"
}

setup_github_token() {
    print_header "GitHub Personal Access Token (Optional)"
    
    print_info "A Personal Access Token is needed for:"
    echo "   - Creating issues on pipeline failures"
    echo "   - Creating pull requests with auto-fixes"
    echo "   - Accessing private repositories"
    echo ""
    
    if prompt_confirm "Do you want to configure a GitHub PAT now?"; then
        echo ""
        print_step "Create a token at: https://github.com/settings/tokens/new"
        echo "   Required scopes:"
        echo "   - repo (full access)"
        echo "   - workflow (for Actions integration)"
        echo ""
        
        prompt_secret "Enter GitHub Personal Access Token" GITHUB_TOKEN
        
        if [[ -n "$GITHUB_TOKEN" ]]; then
            update_env_var "GITHUB_TOKEN" "$GITHUB_TOKEN"
            print_success "GitHub token saved!"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

print_summary() {
    local auth_type="$1"
    
    print_header "Setup Complete!"
    
    echo "Configuration saved to: $ENV_FILE"
    echo ""
    echo "Next steps:"
    echo "   1. Review your .env file: cat .env"
    echo "   2. Start Woodpecker: docker compose up -d"
    echo "   3. Access the UI: http://localhost:8000"
    echo "   4. Log in with GitHub to activate repositories"
    echo ""
    
    if [[ "$auth_type" == "GitHub App" ]]; then
        echo "Additional steps for GitHub App:"
        echo "   5. Install the app on your repositories:"
        echo "      https://github.com/settings/apps → Your App → Install App"
        echo ""
    fi
    
    print_info "For detailed instructions, see docs/GITHUB_SETUP.md"
}

# -----------------------------------------------------------------------------
# Main Menu
# -----------------------------------------------------------------------------

show_menu() {
    print_header "Woodpecker CI - GitHub Integration Setup"
    
    echo "Choose your authentication method:"
    echo ""
    echo "   1) GitHub OAuth App"
    echo "      → Simpler setup"
    echo "      → User-level authentication"
    echo "      → Good for personal projects"
    echo ""
    echo "   2) GitHub App"
    echo "      → More granular permissions"
    echo "      → App-level authentication"
    echo "      → Recommended for organizations"
    echo ""
    echo "   3) Exit"
    echo ""
    
    read -rp "$(echo -e "${BLUE}?${NC} Select option [1-3]: ")" choice
    
    case "$choice" in
        1)
            check_env_file
            setup_oauth_app
            setup_github_token
            ;;
        2)
            check_env_file
            setup_github_app
            setup_github_token
            ;;
        3)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --oauth    Configure GitHub OAuth App directly"
    echo "  --app      Configure GitHub App directly"
    echo "  --help     Show this help message"
    echo ""
    echo "If no option is provided, an interactive menu will be shown."
}

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------

main() {
    case "${1:-}" in
        --oauth)
            check_env_file
            setup_oauth_app
            setup_github_token
            ;;
        --app)
            check_env_file
            setup_github_app
            setup_github_token
            ;;
        --help|-h)
            show_help
            ;;
        "")
            show_menu
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
