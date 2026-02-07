#!/usr/bin/env bash
# =============================================================================
# GitHub Issue Creation Script
# =============================================================================
# Creates GitHub issues automatically when pipelines fail.
# Designed to be called from Woodpecker CI pipelines.
#
# Usage:
#   ./scripts/create-issue.sh [options]
#
# Options:
#   --title TITLE       Issue title (required)
#   --body BODY         Issue body text
#   --body-file FILE    Read body from file (overrides --body)
#   --template NAME     Use template from config/issue-templates/
#   --labels LABELS     Comma-separated labels (default: ci-failure,automated)
#   --assignees USERS   Comma-separated assignees
#   --repo OWNER/REPO   Repository (default: from CI environment)
#   --duplicate-check   Check for existing similar issues
#   --dry-run           Print issue without creating
#   --help              Show this help message
#
# Environment Variables:
#   GITHUB_TOKEN        GitHub API token (required)
#   CI_REPO             Repository name (from Woodpecker)
#   CI_COMMIT_SHA       Commit SHA (from Woodpecker)
#   CI_COMMIT_BRANCH    Branch name (from Woodpecker)
#   CI_PIPELINE_NUMBER  Pipeline number (from Woodpecker)
#   CI_PIPELINE_URL     Pipeline URL (from Woodpecker)
#
# Templates:
#   Templates are Markdown files with variable substitution:
#   ${VAR_NAME} - Environment variable
#   ${CI_*}     - Woodpecker CI variables
#
# Examples:
#   ./scripts/create-issue.sh --title "Build failed" --template pipeline-failure
#   ./scripts/create-issue.sh --title "Security issue" --labels "security,urgent"
#
# Version: 0.0.6
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration Defaults
# -----------------------------------------------------------------------------
TITLE=""
BODY=""
BODY_FILE=""
TEMPLATE=""
LABELS="ci-failure,automated"
ASSIGNEES=""
REPO="${CI_REPO:-}"
DUPLICATE_CHECK="false"
DRY_RUN="false"
TEMPLATE_DIR="config/issue-templates"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    head -50 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

check_dependencies() {
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found - JSON parsing may be limited"
    fi
}

check_github_token() {
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_error "GITHUB_TOKEN environment variable is required"
        echo ""
        echo "Create a token at: https://github.com/settings/tokens"
        echo "Required scopes: repo (for private repos) or public_repo (for public)"
        exit 1
    fi
}

# Substitute environment variables in template
substitute_variables() {
    local content="$1"
    
    # Replace ${VAR} patterns with environment variable values
    while [[ "$content" =~ \$\{([A-Za-z_][A-Za-z_0-9]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        content="${content//\$\{$var_name\}/$var_value}"
    done
    
    echo "$content"
}

load_template() {
    local template_name="$1"
    local template_path="${TEMPLATE_DIR}/${template_name}.md"
    
    if [[ ! -f "$template_path" ]]; then
        log_error "Template not found: $template_path"
        log_info "Available templates:"
        ls -1 "${TEMPLATE_DIR}"/*.md 2>/dev/null | sed 's/.*\//  - /' | sed 's/\.md$//' || echo "  (none)"
        exit 1
    fi
    
    cat "$template_path"
}

check_duplicate_issue() {
    local search_query="$1"
    local repo="$2"
    
    log_info "Checking for duplicate issues..."
    
    # Search for open issues with similar title
    local response
    response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/search/issues?q=${search_query}+repo:${repo}+is:issue+is:open")
    
    if command -v jq &> /dev/null; then
        local count
        count=$(echo "$response" | jq -r '.total_count // 0')
        
        if [[ "$count" -gt 0 ]]; then
            local existing_url
            existing_url=$(echo "$response" | jq -r '.items[0].html_url')
            log_warning "Found $count similar open issue(s)"
            log_warning "Existing issue: $existing_url"
            return 1
        fi
    fi
    
    return 0
}

create_github_issue() {
    local title="$1"
    local body="$2"
    local labels="$3"
    local assignees="$4"
    local repo="$5"
    
    # Build JSON payload
    local payload
    payload=$(cat <<EOF
{
    "title": $(echo "$title" | jq -Rs .),
    "body": $(echo "$body" | jq -Rs .),
    "labels": $(echo "$labels" | tr ',' '\n' | jq -R . | jq -s .),
    "assignees": $(echo "$assignees" | tr ',' '\n' | grep -v '^$' | jq -R . | jq -s .)
}
EOF
)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Would create issue:"
        echo ""
        echo "Repository: $repo"
        echo "Title: $title"
        echo "Labels: $labels"
        echo "Assignees: $assignees"
        echo ""
        echo "Body:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$body"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return 0
    fi
    
    log_info "Creating GitHub issue..."
    
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "https://api.github.com/repos/${repo}/issues")
    
    http_code=$(echo "$response" | tail -1)
    response=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "201" ]]; then
        if command -v jq &> /dev/null; then
            local issue_url
            local issue_number
            issue_url=$(echo "$response" | jq -r '.html_url')
            issue_number=$(echo "$response" | jq -r '.number')
            log_success "Issue #${issue_number} created successfully!"
            log_info "URL: $issue_url"
            echo "$issue_url"
        else
            log_success "Issue created successfully!"
            echo "$response"
        fi
        return 0
    else
        log_error "Failed to create issue (HTTP $http_code)"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        --title)
            TITLE="$2"
            shift 2
            ;;
        --body)
            BODY="$2"
            shift 2
            ;;
        --body-file)
            BODY_FILE="$2"
            shift 2
            ;;
        --template)
            TEMPLATE="$2"
            shift 2
            ;;
        --labels)
            LABELS="$2"
            shift 2
            ;;
        --assignees)
            ASSIGNEES="$2"
            shift 2
            ;;
        --repo)
            REPO="$2"
            shift 2
            ;;
        --duplicate-check)
            DUPLICATE_CHECK="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Main Script
# -----------------------------------------------------------------------------

main() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "📋 GitHub Issue Creator"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check dependencies
    check_dependencies
    
    # Check GitHub token (skip in dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        check_github_token
    fi
    
    # Validate required parameters
    if [[ -z "$TITLE" ]]; then
        log_error "Issue title is required (--title)"
        exit 1
    fi
    
    if [[ -z "$REPO" ]]; then
        log_error "Repository is required (--repo or CI_REPO env var)"
        exit 1
    fi
    
    # Load body content
    if [[ -n "$TEMPLATE" ]]; then
        log_info "Loading template: $TEMPLATE"
        BODY=$(load_template "$TEMPLATE")
    elif [[ -n "$BODY_FILE" ]]; then
        if [[ ! -f "$BODY_FILE" ]]; then
            log_error "Body file not found: $BODY_FILE"
            exit 1
        fi
        BODY=$(cat "$BODY_FILE")
    elif [[ -z "$BODY" ]]; then
        # Default body if none provided
        BODY="This issue was automatically created by the CI/CD pipeline.

## Details

- **Repository:** ${CI_REPO:-N/A}
- **Branch:** ${CI_COMMIT_BRANCH:-N/A}
- **Commit:** ${CI_COMMIT_SHA:-N/A}
- **Pipeline:** #${CI_PIPELINE_NUMBER:-N/A}

## Action Required

Please investigate and resolve this issue.
"
    fi
    
    # Substitute variables in body
    BODY=$(substitute_variables "$BODY")
    TITLE=$(substitute_variables "$TITLE")
    
    # Check for duplicates
    if [[ "$DUPLICATE_CHECK" == "true" ]]; then
        local search_term
        search_term=$(echo "$TITLE" | head -c 50 | sed 's/ /%20/g')
        if ! check_duplicate_issue "$search_term" "$REPO"; then
            log_warning "Skipping issue creation due to existing similar issue"
            exit 0
        fi
    fi
    
    # Create the issue
    create_github_issue "$TITLE" "$BODY" "$LABELS" "$ASSIGNEES" "$REPO"
    
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run main function
main
