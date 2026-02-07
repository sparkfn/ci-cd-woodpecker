#!/usr/bin/env bash
# =============================================================================
# Auto-PR Creation Script
# =============================================================================
# Automatically creates a GitHub Pull Request from a fix branch.
#
# Features:
#   - Create PR with customizable templates
#   - Link to related issues
#   - Add labels and reviewers
#   - Support for draft PRs
#
# Usage:
#   ./create-pr.sh --source <branch> --target <branch> --title <title>
#
# Environment Variables:
#   GITHUB_TOKEN        - GitHub personal access token (required)
#   GITHUB_API_URL      - GitHub API URL (default: https://api.github.com)
#   PR_DEFAULT_REVIEWERS - Comma-separated list of default reviewers
#   PR_DEFAULT_LABELS   - Comma-separated list of default labels
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants & Defaults
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
TEMPLATES_DIR="${CONFIG_DIR}/pr-templates"

# GitHub API
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
DRAFT=false
VERBOSE=false
DRY_RUN=false
TEMPLATE_NAME="default"
AUTO_MERGE=false
DELETE_BRANCH_ON_MERGE=true

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "[DEBUG] $*"
    fi
}

# -----------------------------------------------------------------------------
# Usage & Help
# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
Auto-PR Creation Script - Create GitHub Pull Requests automatically

USAGE:
    $(basename "$0") [OPTIONS]

REQUIRED:
    --source <branch>       Source branch (the branch with changes)
    --target <branch>       Target branch (usually main/master)
    --title <title>         PR title

OPTIONS:
    --repo <owner/repo>     Repository (default: auto-detected from git remote)
    --body <text>           PR body/description
    --template <name>       PR template to use (default, ai-fix, security-fix, etc.)
    --issue <number>        Related issue number to link
    --labels <labels>       Comma-separated labels to add
    --reviewers <users>     Comma-separated reviewers to request
    --team-reviewers <teams> Comma-separated team reviewers
    --draft                 Create as draft PR
    --auto-merge            Enable auto-merge when checks pass
    --no-delete-branch      Don't delete source branch after merge
    --dry-run               Show what would be done without executing
    --verbose               Enable verbose output
    --help                  Show this help message

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN            GitHub personal access token (required)
    GITHUB_API_URL          GitHub API URL (default: https://api.github.com)
    PR_DEFAULT_REVIEWERS    Default reviewers (comma-separated)
    PR_DEFAULT_LABELS       Default labels (comma-separated)

EXAMPLES:
    # Basic PR creation
    $(basename "$0") --source ai-fix/123 --target main --title "Fix: Resolve test failure"

    # PR with issue link and reviewers
    $(basename "$0") --source fix/auth --target main --title "Fix auth bug" \\
        --issue 42 --reviewers "alice,bob" --labels "bug,priority:high"

    # Draft PR with custom template
    $(basename "$0") --source feature/new --target develop \\
        --title "WIP: New feature" --template feature --draft

    # AI fix PR with auto-merge
    $(basename "$0") --source ai-fix/456 --target main \\
        --title "AI Fix: Test failure" --template ai-fix --auto-merge

EXIT CODES:
    0   PR created successfully
    1   PR creation failed
    2   Invalid arguments or configuration
    3   GitHub API error
    4   Repository/branch not found
EOF
}

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source)
                SOURCE_BRANCH="$2"
                shift 2
                ;;
            --target)
                TARGET_BRANCH="$2"
                shift 2
                ;;
            --title)
                PR_TITLE="$2"
                shift 2
                ;;
            --repo)
                REPO="$2"
                shift 2
                ;;
            --body)
                PR_BODY="$2"
                shift 2
                ;;
            --template)
                TEMPLATE_NAME="$2"
                shift 2
                ;;
            --issue)
                ISSUE_NUMBER="$2"
                shift 2
                ;;
            --labels)
                LABELS="$2"
                shift 2
                ;;
            --reviewers)
                REVIEWERS="$2"
                shift 2
                ;;
            --team-reviewers)
                TEAM_REVIEWERS="$2"
                shift 2
                ;;
            --draft)
                DRAFT=true
                shift
                ;;
            --auto-merge)
                AUTO_MERGE=true
                shift
                ;;
            --no-delete-branch)
                DELETE_BRANCH_ON_MERGE=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 2
                ;;
        esac
    done

    # Validate required args
    if [[ -z "${SOURCE_BRANCH:-}" ]]; then
        log_error "Missing required argument: --source"
        usage
        exit 2
    fi

    if [[ -z "${TARGET_BRANCH:-}" ]]; then
        log_error "Missing required argument: --target"
        usage
        exit 2
    fi

    if [[ -z "${PR_TITLE:-}" ]]; then
        log_error "Missing required argument: --title"
        usage
        exit 2
    fi
}

# -----------------------------------------------------------------------------
# Validation Functions
# -----------------------------------------------------------------------------
validate_environment() {
    log_info "Validating environment..."

    # Check GitHub token
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_error "GITHUB_TOKEN environment variable is required"
        exit 2
    fi

    # Auto-detect repo from git remote if not provided
    if [[ -z "${REPO:-}" ]]; then
        local remote_url
        remote_url=$(git config --get remote.origin.url 2>/dev/null || true)

        if [[ -z "$remote_url" ]]; then
            log_error "Could not detect repository. Use --repo to specify."
            exit 2
        fi

        # Extract owner/repo from URL
        if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
            REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        else
            log_error "Could not parse repository from remote URL: $remote_url"
            exit 2
        fi
    fi

    log_debug "Repository: $REPO"

    # Validate repo exists and is accessible
    local repo_check
    repo_check=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${GITHUB_API_URL}/repos/${REPO}")

    if [[ "$repo_check" != "200" ]]; then
        log_error "Repository not found or not accessible: $REPO (HTTP $repo_check)"
        exit 4
    fi

    # Split repo into owner and name
    REPO_OWNER="${REPO%%/*}"
    REPO_NAME="${REPO##*/}"

    log_success "Environment validated"
}

# -----------------------------------------------------------------------------
# Template Functions
# -----------------------------------------------------------------------------
load_template() {
    local template_file="${TEMPLATES_DIR}/${TEMPLATE_NAME}.md"

    if [[ -f "$template_file" ]]; then
        log_debug "Loading template: $template_file"
        cat "$template_file"
    else
        log_debug "Template not found, using default"
        cat <<'EOF'
## Description

<!-- Describe the changes in this PR -->

## Type of Change

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing

- [ ] Tests pass locally
- [ ] New tests added (if applicable)

## Checklist

- [ ] Code follows the project's style guidelines
- [ ] Self-review completed
- [ ] Documentation updated (if applicable)
EOF
    fi
}

render_template() {
    local template="$1"

    # Replace placeholders
    template="${template//\{\{source_branch\}\}/${SOURCE_BRANCH}}"
    template="${template//\{\{target_branch\}\}/${TARGET_BRANCH}}"
    template="${template//\{\{issue_number\}\}/${ISSUE_NUMBER:-}}"
    template="${template//\{\{repo\}\}/${REPO}}"
    template="${template//\{\{timestamp\}\}/$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

    # Add issue closing keyword if issue number provided
    if [[ -n "${ISSUE_NUMBER:-}" ]]; then
        template="${template}"$'\n\n'"Closes #${ISSUE_NUMBER}"
    fi

    echo "$template"
}

# -----------------------------------------------------------------------------
# GitHub API Functions
# -----------------------------------------------------------------------------
create_pull_request() {
    log_info "Creating pull request..."

    # Build PR body
    local body
    if [[ -n "${PR_BODY:-}" ]]; then
        body="$PR_BODY"
    else
        local template
        template=$(load_template)
        body=$(render_template "$template")
    fi

    # Build JSON payload
    local payload
    payload=$(jq -n \
        --arg title "$PR_TITLE" \
        --arg body "$body" \
        --arg head "$SOURCE_BRANCH" \
        --arg base "$TARGET_BRANCH" \
        --argjson draft "$DRAFT" \
        '{
            title: $title,
            body: $body,
            head: $head,
            base: $base,
            draft: $draft
        }')

    log_debug "Payload: $payload"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create PR:"
        echo "$payload" | jq .
        echo "PR_NUMBER=0"
        return 0
    fi

    # Create the PR
    local response
    response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${GITHUB_API_URL}/repos/${REPO}/pulls")

    # Check for errors
    if echo "$response" | jq -e '.message' &>/dev/null; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.message')
        
        # Check if PR already exists
        if [[ "$error_msg" == *"A pull request already exists"* ]]; then
            log_warn "Pull request already exists"
            
            # Try to find existing PR
            local existing_pr
            existing_pr=$(curl -s \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "${GITHUB_API_URL}/repos/${REPO}/pulls?head=${REPO_OWNER}:${SOURCE_BRANCH}&state=open" \
                | jq -r '.[0].number // empty')
            
            if [[ -n "$existing_pr" ]]; then
                PR_NUMBER="$existing_pr"
                PR_URL="${GITHUB_API_URL}/repos/${REPO}/pulls/${PR_NUMBER}"
                log_info "Found existing PR #${PR_NUMBER}"
                return 0
            fi
        fi
        
        log_error "GitHub API error: $error_msg"
        log_debug "Full response: $response"
        return 3
    fi

    # Extract PR number and URL
    PR_NUMBER=$(echo "$response" | jq -r '.number')
    PR_URL=$(echo "$response" | jq -r '.html_url')

    if [[ -z "$PR_NUMBER" ]] || [[ "$PR_NUMBER" == "null" ]]; then
        log_error "Failed to get PR number from response"
        log_debug "Response: $response"
        return 3
    fi

    log_success "Created PR #${PR_NUMBER}: ${PR_URL}"
}

add_labels() {
    local labels_to_add="${LABELS:-}"

    # Add default labels
    if [[ -n "${PR_DEFAULT_LABELS:-}" ]]; then
        if [[ -n "$labels_to_add" ]]; then
            labels_to_add="${labels_to_add},${PR_DEFAULT_LABELS}"
        else
            labels_to_add="$PR_DEFAULT_LABELS"
        fi
    fi

    if [[ -z "$labels_to_add" ]]; then
        log_debug "No labels to add"
        return 0
    fi

    log_info "Adding labels: $labels_to_add"

    # Convert comma-separated to JSON array
    local labels_json
    labels_json=$(echo "$labels_to_add" | tr ',' '\n' | jq -R . | jq -s .)

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would add labels: $labels_json"
        return 0
    fi

    local response
    response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "{\"labels\": ${labels_json}}" \
        "${GITHUB_API_URL}/repos/${REPO}/issues/${PR_NUMBER}/labels")

    if echo "$response" | jq -e '.message' &>/dev/null; then
        log_warn "Failed to add labels: $(echo "$response" | jq -r '.message')"
    else
        log_success "Labels added"
    fi
}

request_reviewers() {
    local reviewers_to_add="${REVIEWERS:-}"
    local teams_to_add="${TEAM_REVIEWERS:-}"

    # Add default reviewers
    if [[ -n "${PR_DEFAULT_REVIEWERS:-}" ]]; then
        if [[ -n "$reviewers_to_add" ]]; then
            reviewers_to_add="${reviewers_to_add},${PR_DEFAULT_REVIEWERS}"
        else
            reviewers_to_add="$PR_DEFAULT_REVIEWERS"
        fi
    fi

    if [[ -z "$reviewers_to_add" ]] && [[ -z "$teams_to_add" ]]; then
        log_debug "No reviewers to request"
        return 0
    fi

    log_info "Requesting reviewers..."

    # Build payload
    local payload="{}"

    if [[ -n "$reviewers_to_add" ]]; then
        local reviewers_json
        reviewers_json=$(echo "$reviewers_to_add" | tr ',' '\n' | jq -R . | jq -s .)
        payload=$(echo "$payload" | jq --argjson r "$reviewers_json" '. + {reviewers: $r}')
    fi

    if [[ -n "$teams_to_add" ]]; then
        local teams_json
        teams_json=$(echo "$teams_to_add" | tr ',' '\n' | jq -R . | jq -s .)
        payload=$(echo "$payload" | jq --argjson t "$teams_json" '. + {team_reviewers: $t}')
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would request reviewers: $payload"
        return 0
    fi

    local response
    response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${GITHUB_API_URL}/repos/${REPO}/pulls/${PR_NUMBER}/requested_reviewers")

    if echo "$response" | jq -e '.message' &>/dev/null; then
        log_warn "Failed to request reviewers: $(echo "$response" | jq -r '.message')"
    else
        log_success "Reviewers requested"
    fi
}

link_issue() {
    if [[ -z "${ISSUE_NUMBER:-}" ]]; then
        return 0
    fi

    log_info "Linking to issue #${ISSUE_NUMBER}..."

    # Add a comment to the issue
    local comment="🔀 Pull Request #${PR_NUMBER} has been created to address this issue.\n\n[View PR](${PR_URL:-https://github.com/${REPO}/pull/${PR_NUMBER}})"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would comment on issue #${ISSUE_NUMBER}"
        return 0
    fi

    local response
    response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "{\"body\": \"${comment}\"}" \
        "${GITHUB_API_URL}/repos/${REPO}/issues/${ISSUE_NUMBER}/comments")

    if echo "$response" | jq -e '.message' &>/dev/null; then
        log_warn "Failed to comment on issue: $(echo "$response" | jq -r '.message')"
    else
        log_success "Issue linked"
    fi
}

enable_auto_merge() {
    if [[ "$AUTO_MERGE" != "true" ]]; then
        return 0
    fi

    log_info "Enabling auto-merge..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable auto-merge"
        return 0
    fi

    # Enable auto-merge via GraphQL API
    # First, get the PR node ID
    local pr_data
    pr_data=$(curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${GITHUB_API_URL}/repos/${REPO}/pulls/${PR_NUMBER}")

    local node_id
    node_id=$(echo "$pr_data" | jq -r '.node_id')

    if [[ -z "$node_id" ]] || [[ "$node_id" == "null" ]]; then
        log_warn "Could not get PR node ID for auto-merge"
        return 0
    fi

    # Enable auto-merge via GraphQL
    local graphql_query='mutation($pullRequestId: ID!) {
        enablePullRequestAutoMerge(input: {
            pullRequestId: $pullRequestId,
            mergeMethod: SQUASH
        }) {
            pullRequest {
                autoMergeRequest {
                    enabledAt
                }
            }
        }
    }'

    local response
    response=$(curl -s -X POST \
        -H "Authorization: bearer ${GITHUB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"query\": $(echo "$graphql_query" | jq -Rs .), \"variables\": {\"pullRequestId\": \"${node_id}\"}}" \
        "https://api.github.com/graphql")

    if echo "$response" | jq -e '.errors' &>/dev/null; then
        log_warn "Failed to enable auto-merge: $(echo "$response" | jq -r '.errors[0].message // "Unknown error"')"
        log_debug "This may be because auto-merge is not enabled for this repository"
    else
        log_success "Auto-merge enabled"
    fi
}

# -----------------------------------------------------------------------------
# Output Functions
# -----------------------------------------------------------------------------
save_result() {
    local output_file="${1:-/tmp/create-pr-result.json}"

    cat > "$output_file" <<EOF
{
    "pr_number": ${PR_NUMBER:-0},
    "pr_url": "${PR_URL:-}",
    "source_branch": "${SOURCE_BRANCH}",
    "target_branch": "${TARGET_BRANCH}",
    "title": "${PR_TITLE}",
    "repo": "${REPO}",
    "draft": ${DRAFT},
    "auto_merge": ${AUTO_MERGE},
    "issue_number": ${ISSUE_NUMBER:-null},
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    log_debug "Result saved to: $output_file"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    log_info "=========================================="
    log_info "Auto-PR Creation Script"
    log_info "=========================================="
    log_info "Source: $SOURCE_BRANCH"
    log_info "Target: $TARGET_BRANCH"
    log_info "Title: $PR_TITLE"
    log_info "Draft: $DRAFT"
    log_info "Dry run: $DRY_RUN"
    log_info "=========================================="

    validate_environment

    # Create the PR
    if ! create_pull_request; then
        log_error "Failed to create pull request"
        exit 1
    fi

    # Add labels
    add_labels

    # Request reviewers
    request_reviewers

    # Link to issue
    link_issue

    # Enable auto-merge
    enable_auto_merge

    # Save result
    save_result

    log_success "=========================================="
    log_success "Pull request created successfully!"
    log_success "PR #${PR_NUMBER}: ${PR_URL:-https://github.com/${REPO}/pull/${PR_NUMBER}}"
    log_success "=========================================="

    # Output for CI pipelines
    echo "PR_NUMBER=${PR_NUMBER}"
    echo "PR_URL=${PR_URL:-https://github.com/${REPO}/pull/${PR_NUMBER}}"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
