#!/usr/bin/env bash
# =============================================================================
# Polling Service Script
# Version: 0.0.10
#
# A polling service that checks for new merges, commits, and events when
# webhooks are not available or unreliable. Useful for:
# - Firewall-restricted environments
# - Self-hosted Git servers without webhook support
# - Backup mechanism when webhooks fail
#
# Usage:
#   ./poll-service.sh --start                    # Start polling daemon
#   ./poll-service.sh --once                     # Single poll cycle
#   ./poll-service.sh --check-repo owner/repo    # Check specific repo
#   ./poll-service.sh --status                   # Show service status
#
# Environment Variables:
#   POLL_INTERVAL       - Seconds between polls (default: 60)
#   GITHUB_TOKEN        - GitHub API token
#   GITLAB_TOKEN        - GitLab API token
#   GITEA_TOKEN         - Gitea API token
#   WOODPECKER_SERVER   - Woodpecker server URL
#   WOODPECKER_TOKEN    - Woodpecker API token
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Polling settings
POLL_INTERVAL="${POLL_INTERVAL:-60}"
STATE_FILE="${STATE_FILE:-/var/lib/poll-service/state.json}"
PID_FILE="${PID_FILE:-/var/run/poll-service.pid}"
LOG_FILE="${LOG_FILE:-/var/log/poll-service.log}"

# Git provider settings
GITHUB_API="${GITHUB_API:-https://api.github.com}"
GITLAB_API="${GITLAB_API:-https://gitlab.com/api/v4}"
GITEA_API="${GITEA_API:-}"

# Config file
CONFIG_FILE="${CONFIG_FILE:-${PROJECT_ROOT}/config/webhook.yaml}"

# Action mode
ACTION=""
TARGET_REPO=""
VERBOSE="${VERBOSE:-false}"
DAEMON="${DAEMON:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Logging Functions
# =============================================================================
log_info() {
    local msg="[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${BLUE}${msg}${NC}"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    local msg="[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${GREEN}${msg}${NC}"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_warn() {
    local msg="[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${YELLOW}${msg}${NC}"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    local msg="[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${RED}${msg}${NC}" >&2
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        local msg="[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $*"
        echo -e "$msg"
        [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Polling service for detecting Git repository changes.

OPTIONS:
    --start             Start the polling service (background daemon)
    --once              Run a single poll cycle and exit
    --check-repo REPO   Check a specific repository (owner/repo format)
    --status            Show service status
    --stop              Stop the running service
    --interval SEC      Poll interval in seconds (default: 60)
    --config FILE       Path to config file
    --verbose           Enable verbose output
    -h, --help          Show this help message

EXAMPLES:
    # Start as daemon
    $(basename "$0") --start

    # Single poll cycle
    $(basename "$0") --once

    # Check specific repo
    $(basename "$0") --check-repo myorg/myrepo

    # Start with custom interval
    $(basename "$0") --start --interval 120

ENVIRONMENT:
    POLL_INTERVAL       Poll interval in seconds
    GITHUB_TOKEN        GitHub API token
    GITLAB_TOKEN        GitLab API token
    WOODPECKER_SERVER   Woodpecker server URL
    WOODPECKER_TOKEN    Woodpecker API token

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --start)
                ACTION="start"
                shift
                ;;
            --once)
                ACTION="once"
                shift
                ;;
            --check-repo)
                ACTION="check"
                TARGET_REPO="$2"
                shift 2
                ;;
            --status)
                ACTION="status"
                shift
                ;;
            --stop)
                ACTION="stop"
                shift
                ;;
            --interval)
                POLL_INTERVAL="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --daemon)
                DAEMON="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Initialize state directory
init_state() {
    local state_dir
    state_dir=$(dirname "$STATE_FILE")
    mkdir -p "$state_dir" 2>/dev/null || true
    
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"repos": {}, "last_poll": null}' > "$STATE_FILE"
    fi
    
    # Ensure log directory exists
    if [[ -n "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    fi
}

# Load state from file
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"repos": {}, "last_poll": null}'
    fi
}

# Save state to file
save_state() {
    local state="$1"
    echo "$state" > "$STATE_FILE"
}

# Get repo state
get_repo_state() {
    local repo="$1"
    local state
    state=$(load_state)
    
    if command -v jq &> /dev/null; then
        echo "$state" | jq -r ".repos[\"$repo\"] // {}" 2>/dev/null || echo "{}"
    else
        echo "{}"
    fi
}

# Update repo state
update_repo_state() {
    local repo="$1"
    local key="$2"
    local value="$3"
    
    local state
    state=$(load_state)
    
    if command -v jq &> /dev/null; then
        state=$(echo "$state" | jq ".repos[\"$repo\"].$key = \"$value\"" 2>/dev/null)
        state=$(echo "$state" | jq ".last_poll = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"")
        save_state "$state"
    fi
}

# =============================================================================
# Git Provider APIs
# =============================================================================

# Detect provider from repo format
detect_provider() {
    local repo="$1"
    
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "github"
    elif [[ -n "${GITLAB_TOKEN:-}" ]]; then
        echo "gitlab"
    elif [[ -n "${GITEA_TOKEN:-}" && -n "${GITEA_API:-}" ]]; then
        echo "gitea"
    else
        # Default to GitHub
        echo "github"
    fi
}

# Get the latest commit for a branch
get_latest_commit_github() {
    local repo="$1"
    local branch="${2:-main}"
    
    local url="${GITHUB_API}/repos/${repo}/commits/${branch}"
    local response
    
    response=$(curl -sf \
        -H "Accept: application/vnd.github.v3+json" \
        ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "$url" 2>/dev/null) || return 1
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq -r '.sha'
    else
        echo "$response" | grep -o '"sha":"[^"]*"' | head -1 | cut -d'"' -f4
    fi
}

# Get recently merged PRs (GitHub)
get_merged_prs_github() {
    local repo="$1"
    local since="${2:-}"
    
    local url="${GITHUB_API}/repos/${repo}/pulls?state=closed&sort=updated&direction=desc&per_page=10"
    
    curl -sf \
        -H "Accept: application/vnd.github.v3+json" \
        ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "$url" 2>/dev/null
}

# Get the latest commit (GitLab)
get_latest_commit_gitlab() {
    local repo="$1"
    local branch="${2:-main}"
    
    # URL-encode the repo path
    local encoded_repo
    encoded_repo=$(echo "$repo" | sed 's/\//%2F/g')
    
    local url="${GITLAB_API}/projects/${encoded_repo}/repository/branches/${branch}"
    local response
    
    response=$(curl -sf \
        ${GITLAB_TOKEN:+-H "PRIVATE-TOKEN: $GITLAB_TOKEN"} \
        "$url" 2>/dev/null) || return 1
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq -r '.commit.id'
    else
        echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
    fi
}

# Get merged merge requests (GitLab)
get_merged_mrs_gitlab() {
    local repo="$1"
    local since="${2:-}"
    
    local encoded_repo
    encoded_repo=$(echo "$repo" | sed 's/\//%2F/g')
    
    local url="${GITLAB_API}/projects/${encoded_repo}/merge_requests?state=merged&order_by=updated_at&per_page=10"
    
    curl -sf \
        ${GITLAB_TOKEN:+-H "PRIVATE-TOKEN: $GITLAB_TOKEN"} \
        "$url" 2>/dev/null
}

# =============================================================================
# Poll Functions
# =============================================================================

# Check a single repository for changes
check_repo() {
    local repo="$1"
    local provider
    provider=$(detect_provider "$repo")
    
    log_debug "Checking repo: $repo (provider: $provider)"
    
    local repo_state
    repo_state=$(get_repo_state "$repo")
    
    local last_commit last_merge_check
    if command -v jq &> /dev/null; then
        last_commit=$(echo "$repo_state" | jq -r '.last_commit // ""' 2>/dev/null)
        last_merge_check=$(echo "$repo_state" | jq -r '.last_merge_check // ""' 2>/dev/null)
    fi
    
    # Check for new commits on main branch
    local current_commit
    case "$provider" in
        github)
            current_commit=$(get_latest_commit_github "$repo" "main")
            if [[ -z "$current_commit" ]]; then
                current_commit=$(get_latest_commit_github "$repo" "master")
            fi
            ;;
        gitlab)
            current_commit=$(get_latest_commit_gitlab "$repo" "main")
            if [[ -z "$current_commit" ]]; then
                current_commit=$(get_latest_commit_gitlab "$repo" "master")
            fi
            ;;
    esac
    
    if [[ -z "$current_commit" ]]; then
        log_warn "Could not fetch latest commit for $repo"
        return 1
    fi
    
    log_debug "Current commit: $current_commit, Last known: $last_commit"
    
    # Check if commit has changed
    if [[ "$current_commit" != "$last_commit" && -n "$last_commit" ]]; then
        log_success "New commit detected on $repo: $current_commit"
        on_new_commit "$repo" "$current_commit" "$last_commit"
    fi
    
    # Update state
    update_repo_state "$repo" "last_commit" "$current_commit"
    
    # Check for recently merged PRs/MRs
    check_merged_prs "$repo" "$provider" "$last_merge_check"
    update_repo_state "$repo" "last_merge_check" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Check for recently merged PRs
check_merged_prs() {
    local repo="$1"
    local provider="$2"
    local since="$3"
    
    local prs=""
    case "$provider" in
        github)
            prs=$(get_merged_prs_github "$repo" "$since")
            ;;
        gitlab)
            prs=$(get_merged_mrs_gitlab "$repo" "$since")
            ;;
    esac
    
    if [[ -z "$prs" || "$prs" == "[]" ]]; then
        return 0
    fi
    
    # Parse merged PRs
    if command -v jq &> /dev/null; then
        local count
        count=$(echo "$prs" | jq 'length')
        
        for i in $(seq 0 $((count - 1))); do
            local pr_data
            pr_data=$(echo "$prs" | jq ".[$i]")
            
            local merged_at pr_number title
            
            case "$provider" in
                github)
                    merged_at=$(echo "$pr_data" | jq -r '.merged_at // ""')
                    pr_number=$(echo "$pr_data" | jq -r '.number')
                    title=$(echo "$pr_data" | jq -r '.title')
                    ;;
                gitlab)
                    merged_at=$(echo "$pr_data" | jq -r '.merged_at // ""')
                    pr_number=$(echo "$pr_data" | jq -r '.iid')
                    title=$(echo "$pr_data" | jq -r '.title')
                    ;;
            esac
            
            # Skip if not merged or already processed
            if [[ -z "$merged_at" || "$merged_at" == "null" ]]; then
                continue
            fi
            
            # Check if this merge is newer than our last check
            if [[ -n "$since" ]]; then
                if [[ "$merged_at" < "$since" ]]; then
                    continue
                fi
            fi
            
            log_success "Detected merged PR: #$pr_number - $title"
            on_pr_merged "$repo" "$pr_number" "$title" "$merged_at"
        done
    fi
}

# =============================================================================
# Event Handlers
# =============================================================================

# Handle new commit detection
on_new_commit() {
    local repo="$1"
    local new_commit="$2"
    local old_commit="$3"
    
    log_info "New commit on $repo: $old_commit → $new_commit"
    
    # Trigger pipeline
    trigger_pipeline "$repo" "main" "$new_commit" "push"
}

# Handle PR merge detection
on_pr_merged() {
    local repo="$1"
    local pr_number="$2"
    local title="$3"
    local merged_at="$4"
    
    log_info "PR #$pr_number merged: $title (at $merged_at)"
    
    # Trigger on-merge pipeline
    export MERGE_PR_NUMBER="$pr_number"
    export MERGE_TITLE="$title"
    export MERGE_TIMESTAMP="$merged_at"
    
    trigger_pipeline "$repo" "main" "" "merge"
    
    # Execute on-merge script if exists
    local on_merge_script="${SCRIPT_DIR}/on-merge.sh"
    if [[ -x "$on_merge_script" ]]; then
        log_info "Executing on-merge script..."
        "$on_merge_script" "$repo" "main" "$pr_number"
    fi
}

# Trigger Woodpecker pipeline
trigger_pipeline() {
    local repo="$1"
    local branch="$2"
    local commit="${3:-}"
    local event="${4:-push}"
    
    log_info "Triggering pipeline: $repo@$branch (event: $event)"
    
    if [[ -z "${WOODPECKER_TOKEN:-}" ]]; then
        log_warn "WOODPECKER_TOKEN not set, skipping pipeline trigger"
        return 0
    fi
    
    local api_url="${WOODPECKER_SERVER:-http://localhost:8000}/api/repos/${repo}/builds"
    
    local response
    response=$(curl -sf -X POST \
        -H "Authorization: Bearer $WOODPECKER_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"branch\": \"$branch\", \"event\": \"$event\"}" \
        "$api_url" 2>&1) || {
        log_error "Failed to trigger pipeline: $response"
        return 1
    }
    
    if command -v jq &> /dev/null; then
        local build_number
        build_number=$(echo "$response" | jq -r '.number')
        log_success "Triggered build #$build_number"
    fi
}

# =============================================================================
# Service Control
# =============================================================================

# Load repos from config
load_repos_from_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        if command -v yq &> /dev/null; then
            yq -r '.polling.repositories[]' "$CONFIG_FILE" 2>/dev/null || true
        elif command -v python3 &> /dev/null; then
            python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
repos = config.get('polling', {}).get('repositories', [])
for repo in repos:
    print(repo)
" 2>/dev/null || true
        fi
    fi
}

# Main polling loop
poll_loop() {
    log_info "Starting poll service (interval: ${POLL_INTERVAL}s)"
    
    # Load repos to monitor
    local repos
    repos=$(load_repos_from_config)
    
    if [[ -z "$repos" ]]; then
        log_warn "No repositories configured for polling"
        log_info "Configure repos in $CONFIG_FILE under polling.repositories"
        return 1
    fi
    
    log_info "Monitoring repositories:"
    echo "$repos" | while read -r repo; do
        [[ -n "$repo" ]] && log_info "  - $repo"
    done
    
    while true; do
        log_debug "Starting poll cycle..."
        
        echo "$repos" | while read -r repo; do
            if [[ -n "$repo" ]]; then
                check_repo "$repo" || true
            fi
        done
        
        log_debug "Poll cycle complete, sleeping for ${POLL_INTERVAL}s"
        sleep "$POLL_INTERVAL"
    done
}

# Single poll cycle
single_poll() {
    log_info "Running single poll cycle..."
    
    local repos
    repos=$(load_repos_from_config)
    
    if [[ -z "$repos" ]]; then
        log_warn "No repositories configured for polling"
        return 1
    fi
    
    echo "$repos" | while read -r repo; do
        if [[ -n "$repo" ]]; then
            check_repo "$repo" || true
        fi
    done
    
    log_success "Poll cycle complete"
}

# Start as daemon
start_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_error "Service already running (PID: $pid)"
            exit 1
        fi
    fi
    
    log_info "Starting poll service daemon..."
    
    # Fork to background
    if [[ "$DAEMON" == "true" ]]; then
        poll_loop &
        echo $! > "$PID_FILE"
        log_success "Poll service started (PID: $!)"
    else
        # Run in foreground but save PID
        echo $$ > "$PID_FILE"
        trap 'rm -f "$PID_FILE"; exit' EXIT INT TERM
        poll_loop
    fi
}

# Stop daemon
stop_daemon() {
    if [[ ! -f "$PID_FILE" ]]; then
        log_warn "PID file not found, service may not be running"
        return 0
    fi
    
    local pid
    pid=$(cat "$PID_FILE")
    
    if kill -0 "$pid" 2>/dev/null; then
        log_info "Stopping poll service (PID: $pid)..."
        kill "$pid"
        rm -f "$PID_FILE"
        log_success "Service stopped"
    else
        log_warn "Process $pid not found"
        rm -f "$PID_FILE"
    fi
}

# Show status
show_status() {
    echo "=== Poll Service Status ==="
    echo ""
    
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Status: Running (PID: $pid)"
        else
            echo "Status: Stopped (stale PID file)"
        fi
    else
        echo "Status: Stopped"
    fi
    
    echo ""
    echo "Configuration:"
    echo "  Poll Interval: ${POLL_INTERVAL}s"
    echo "  State File: $STATE_FILE"
    echo "  Config File: $CONFIG_FILE"
    echo ""
    
    if [[ -f "$STATE_FILE" ]]; then
        echo "Last Poll State:"
        cat "$STATE_FILE" | python3 -m json.tool 2>/dev/null || cat "$STATE_FILE"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    parse_args "$@"
    init_state
    
    case "$ACTION" in
        start)
            start_daemon
            ;;
        once)
            single_poll
            ;;
        check)
            if [[ -z "$TARGET_REPO" ]]; then
                log_error "No repository specified"
                exit 1
            fi
            check_repo "$TARGET_REPO"
            ;;
        status)
            show_status
            ;;
        stop)
            stop_daemon
            ;;
        *)
            usage
            ;;
    esac
}

# Run main function
main "$@"
