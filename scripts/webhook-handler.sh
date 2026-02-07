#!/usr/bin/env bash
# =============================================================================
# Webhook Handler Script
# Version: 0.0.10
#
# A lightweight webhook receiver that can be used standalone or as part of a
# larger webhook handling system. Supports GitHub, GitLab, and Gitea webhooks.
#
# This script can:
# 1. Run as a simple HTTP server (using netcat or Python)
# 2. Process webhook payloads and trigger appropriate actions
# 3. Validate webhook signatures for security
# 4. Route events to different handlers
#
# Usage:
#   ./webhook-handler.sh --serve              # Start HTTP server
#   ./webhook-handler.sh --process <file>     # Process a payload file
#   echo '{"action":"opened"}' | ./webhook-handler.sh --stdin
#
# Environment Variables:
#   WEBHOOK_PORT        - Port to listen on (default: 9000)
#   WEBHOOK_SECRET      - Secret for signature validation
#   WOODPECKER_SERVER   - Woodpecker server URL
#   WOODPECKER_TOKEN    - Woodpecker API token
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Server settings
WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-}"
WEBHOOK_LOG="${WEBHOOK_LOG:-/var/log/webhook-handler.log}"

# Woodpecker settings
WOODPECKER_SERVER="${WOODPECKER_SERVER:-http://localhost:8000}"
WOODPECKER_TOKEN="${WOODPECKER_TOKEN:-}"

# Config file
CONFIG_FILE="${CONFIG_FILE:-${PROJECT_ROOT}/config/webhook.yaml}"

# Action mode
ACTION=""
PAYLOAD_FILE=""
VERBOSE="${VERBOSE:-false}"

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
    [[ -n "$WEBHOOK_LOG" ]] && echo "$msg" >> "$WEBHOOK_LOG" 2>/dev/null || true
}

log_success() {
    local msg="[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${GREEN}${msg}${NC}"
    [[ -n "$WEBHOOK_LOG" ]] && echo "$msg" >> "$WEBHOOK_LOG" 2>/dev/null || true
}

log_warn() {
    local msg="[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${YELLOW}${msg}${NC}"
    [[ -n "$WEBHOOK_LOG" ]] && echo "$msg" >> "$WEBHOOK_LOG" 2>/dev/null || true
}

log_error() {
    local msg="[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${RED}${msg}${NC}" >&2
    [[ -n "$WEBHOOK_LOG" ]] && echo "$msg" >> "$WEBHOOK_LOG" 2>/dev/null || true
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        local msg="[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $*"
        echo -e "$msg"
        [[ -n "$WEBHOOK_LOG" ]] && echo "$msg" >> "$WEBHOOK_LOG" 2>/dev/null || true
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Webhook receiver and handler for CI/CD pipelines.

OPTIONS:
    --serve             Start HTTP server to receive webhooks
    --process FILE      Process a webhook payload from file
    --stdin             Process webhook payload from stdin
    --test              Run in test mode (don't trigger pipelines)
    --port PORT         Server port (default: 9000)
    --config FILE       Path to config file
    --verbose           Enable verbose output
    -h, --help          Show this help message

EXAMPLES:
    # Start webhook server
    $(basename "$0") --serve --port 9000

    # Process a saved payload
    $(basename "$0") --process /tmp/webhook-payload.json

    # Process from stdin
    cat payload.json | $(basename "$0") --stdin

ENVIRONMENT:
    WEBHOOK_PORT        Server port (default: 9000)
    WEBHOOK_SECRET      Secret for signature validation
    WOODPECKER_SERVER   Woodpecker server URL
    WOODPECKER_TOKEN    Woodpecker API token

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --serve)
                ACTION="serve"
                shift
                ;;
            --process)
                ACTION="process"
                PAYLOAD_FILE="$2"
                shift 2
                ;;
            --stdin)
                ACTION="stdin"
                shift
                ;;
            --test)
                TEST_MODE="true"
                shift
                ;;
            --port)
                WEBHOOK_PORT="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
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

# Validate webhook signature (GitHub style)
validate_signature() {
    local payload="$1"
    local signature="$2"
    
    if [[ -z "$WEBHOOK_SECRET" ]]; then
        log_warn "No webhook secret configured, skipping validation"
        return 0
    fi
    
    if [[ -z "$signature" ]]; then
        log_error "No signature provided"
        return 1
    fi
    
    # Calculate expected signature
    local expected
    expected=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/SHA2-256(stdin)= /sha256=/')
    
    if [[ "$signature" == "$expected" ]]; then
        log_debug "Signature validation passed"
        return 0
    else
        log_error "Signature validation failed"
        log_debug "Expected: $expected"
        log_debug "Got: $signature"
        return 1
    fi
}

# Parse JSON using jq or Python
parse_json() {
    local json="$1"
    local path="$2"
    
    if command -v jq &> /dev/null; then
        echo "$json" | jq -r "$path" 2>/dev/null || echo ""
    elif command -v python3 &> /dev/null; then
        echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
path = '$path'.strip('.')
result = data
for key in path.split('.'):
    if isinstance(result, dict):
        result = result.get(key, '')
    else:
        result = ''
print(result if result else '')
" 2>/dev/null || echo ""
    else
        log_error "No JSON parser available (install jq or python3)"
        return 1
    fi
}

# Detect webhook source (GitHub, GitLab, Gitea)
detect_source() {
    local headers="$1"
    local payload="$2"
    
    # Check headers for source hints
    if echo "$headers" | grep -qi "X-GitHub-Event"; then
        echo "github"
    elif echo "$headers" | grep -qi "X-Gitlab-Event"; then
        echo "gitlab"
    elif echo "$headers" | grep -qi "X-Gitea-Event"; then
        echo "gitea"
    # Check payload structure
    elif parse_json "$payload" ".repository.full_name" | grep -q "."; then
        echo "github"
    elif parse_json "$payload" ".project.path_with_namespace" | grep -q "."; then
        echo "gitlab"
    else
        echo "unknown"
    fi
}

# =============================================================================
# Event Handlers
# =============================================================================

# Handle push events
handle_push() {
    local payload="$1"
    local source="$2"
    
    local ref branch repo commit author
    
    case "$source" in
        github|gitea)
            ref=$(parse_json "$payload" ".ref")
            repo=$(parse_json "$payload" ".repository.full_name")
            commit=$(parse_json "$payload" ".after")
            author=$(parse_json "$payload" ".pusher.name")
            ;;
        gitlab)
            ref=$(parse_json "$payload" ".ref")
            repo=$(parse_json "$payload" ".project.path_with_namespace")
            commit=$(parse_json "$payload" ".after")
            author=$(parse_json "$payload" ".user_name")
            ;;
    esac
    
    branch="${ref#refs/heads/}"
    
    log_info "Push event: $repo@$branch ($commit) by $author"
    
    # Trigger pipeline if on main/master branch
    if [[ "$branch" == "main" || "$branch" == "master" ]]; then
        trigger_pipeline "$repo" "$branch" "$commit" "push"
    fi
}

# Handle pull request / merge request events
handle_pr() {
    local payload="$1"
    local source="$2"
    
    local action pr_number title repo base_branch head_branch merged
    
    case "$source" in
        github)
            action=$(parse_json "$payload" ".action")
            pr_number=$(parse_json "$payload" ".pull_request.number")
            title=$(parse_json "$payload" ".pull_request.title")
            repo=$(parse_json "$payload" ".repository.full_name")
            base_branch=$(parse_json "$payload" ".pull_request.base.ref")
            head_branch=$(parse_json "$payload" ".pull_request.head.ref")
            merged=$(parse_json "$payload" ".pull_request.merged")
            ;;
        gitlab)
            action=$(parse_json "$payload" ".object_attributes.action")
            pr_number=$(parse_json "$payload" ".object_attributes.iid")
            title=$(parse_json "$payload" ".object_attributes.title")
            repo=$(parse_json "$payload" ".project.path_with_namespace")
            base_branch=$(parse_json "$payload" ".object_attributes.target_branch")
            head_branch=$(parse_json "$payload" ".object_attributes.source_branch")
            merged=$(parse_json "$payload" ".object_attributes.state")
            [[ "$merged" == "merged" ]] && merged="true" || merged="false"
            ;;
        gitea)
            action=$(parse_json "$payload" ".action")
            pr_number=$(parse_json "$payload" ".pull_request.number")
            title=$(parse_json "$payload" ".pull_request.title")
            repo=$(parse_json "$payload" ".repository.full_name")
            base_branch=$(parse_json "$payload" ".pull_request.base.ref")
            head_branch=$(parse_json "$payload" ".pull_request.head.ref")
            merged=$(parse_json "$payload" ".pull_request.merged")
            ;;
    esac
    
    log_info "PR event: #$pr_number '$title' ($action) - $head_branch → $base_branch"
    
    # Handle different PR actions
    case "$action" in
        opened|reopened)
            log_info "PR opened/reopened - triggering CI"
            trigger_pipeline "$repo" "$head_branch" "" "pull_request"
            ;;
        synchronize|update)
            log_info "PR updated - triggering CI"
            trigger_pipeline "$repo" "$head_branch" "" "pull_request"
            ;;
        closed)
            if [[ "$merged" == "true" ]]; then
                log_success "PR merged! Triggering on-merge pipeline"
                trigger_on_merge "$repo" "$base_branch" "$head_branch" "$pr_number"
            else
                log_info "PR closed without merge"
            fi
            ;;
    esac
}

# Handle tag events
handle_tag() {
    local payload="$1"
    local source="$2"
    
    local ref tag repo
    
    case "$source" in
        github|gitea)
            ref=$(parse_json "$payload" ".ref")
            repo=$(parse_json "$payload" ".repository.full_name")
            ;;
        gitlab)
            ref=$(parse_json "$payload" ".ref")
            repo=$(parse_json "$payload" ".project.path_with_namespace")
            ;;
    esac
    
    tag="${ref#refs/tags/}"
    
    log_info "Tag event: $repo@$tag"
    trigger_pipeline "$repo" "$tag" "" "tag"
}

# =============================================================================
# Pipeline Triggers
# =============================================================================

# Trigger a Woodpecker pipeline
trigger_pipeline() {
    local repo="$1"
    local branch="$2"
    local commit="${3:-}"
    local event="${4:-push}"
    
    log_info "Triggering pipeline: $repo on $branch (event: $event)"
    
    if [[ "${TEST_MODE:-false}" == "true" ]]; then
        log_info "[TEST MODE] Would trigger: $repo@$branch"
        return 0
    fi
    
    if [[ -z "$WOODPECKER_TOKEN" ]]; then
        log_error "WOODPECKER_TOKEN not set, cannot trigger pipeline"
        return 1
    fi
    
    # Woodpecker API call to trigger build
    local api_url="${WOODPECKER_SERVER}/api/repos/${repo}/builds"
    
    local response
    response=$(curl -sf -X POST \
        -H "Authorization: Bearer $WOODPECKER_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"branch\": \"$branch\", \"event\": \"$event\"}" \
        "$api_url" 2>&1) || {
        log_error "Failed to trigger pipeline: $response"
        return 1
    }
    
    local build_number
    build_number=$(parse_json "$response" ".number")
    log_success "Triggered build #$build_number"
}

# Trigger on-merge pipeline
trigger_on_merge() {
    local repo="$1"
    local base_branch="$2"
    local head_branch="$3"
    local pr_number="$4"
    
    log_info "Triggering on-merge pipeline for PR #$pr_number"
    
    # Set environment variables for the pipeline
    export MERGE_PR_NUMBER="$pr_number"
    export MERGE_BASE_BRANCH="$base_branch"
    export MERGE_HEAD_BRANCH="$head_branch"
    
    trigger_pipeline "$repo" "$base_branch" "" "merge"
    
    # Execute on-merge script if it exists
    local on_merge_script="${SCRIPT_DIR}/on-merge.sh"
    if [[ -x "$on_merge_script" ]]; then
        log_info "Executing on-merge script..."
        "$on_merge_script" "$repo" "$base_branch" "$pr_number"
    fi
}

# =============================================================================
# Main Event Processing
# =============================================================================

# Process a webhook payload
process_payload() {
    local payload="$1"
    local headers="${2:-}"
    
    log_debug "Processing payload (${#payload} bytes)"
    
    # Detect source
    local source
    source=$(detect_source "$headers" "$payload")
    log_debug "Detected source: $source"
    
    # Determine event type
    local event_type=""
    
    # Check GitHub/Gitea event header
    if [[ -n "$headers" ]]; then
        event_type=$(echo "$headers" | grep -i "X-GitHub-Event\|X-Gitea-Event" | cut -d: -f2 | tr -d ' ')
    fi
    
    # Fallback: detect from payload
    if [[ -z "$event_type" ]]; then
        if parse_json "$payload" ".pull_request" | grep -q "number\|id"; then
            event_type="pull_request"
        elif parse_json "$payload" ".ref" | grep -q "refs/tags/"; then
            event_type="create"  # tag
        elif parse_json "$payload" ".ref" | grep -q "refs/heads/"; then
            event_type="push"
        elif parse_json "$payload" ".object_attributes.action" | grep -q "."; then
            event_type="merge_request"  # GitLab
        fi
    fi
    
    log_info "Event type: $event_type (source: $source)"
    
    # Route to appropriate handler
    case "$event_type" in
        push)
            handle_push "$payload" "$source"
            ;;
        pull_request|merge_request)
            handle_pr "$payload" "$source"
            ;;
        create)
            # Check if it's a tag
            local ref_type
            ref_type=$(parse_json "$payload" ".ref_type")
            if [[ "$ref_type" == "tag" ]] || parse_json "$payload" ".ref" | grep -q "refs/tags/"; then
                handle_tag "$payload" "$source"
            fi
            ;;
        release)
            log_info "Release event received"
            local tag
            tag=$(parse_json "$payload" ".release.tag_name")
            local repo
            repo=$(parse_json "$payload" ".repository.full_name")
            trigger_pipeline "$repo" "$tag" "" "release"
            ;;
        ping)
            log_info "Ping event received - webhook is configured correctly"
            ;;
        *)
            log_warn "Unhandled event type: $event_type"
            ;;
    esac
}

# =============================================================================
# HTTP Server
# =============================================================================

# Simple HTTP server using Python
start_python_server() {
    log_info "Starting Python HTTP server on port $WEBHOOK_PORT..."
    
    python3 -c "
import http.server
import socketserver
import json
import subprocess
import os
import sys

PORT = int(os.environ.get('WEBHOOK_PORT', 9000))
SCRIPT = '${BASH_SOURCE[0]}'

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        payload = self.rfile.read(content_length).decode('utf-8')
        
        # Get headers
        headers = '\\n'.join([f'{k}: {v}' for k, v in self.headers.items()])
        
        # Process webhook
        try:
            result = subprocess.run(
                [SCRIPT, '--stdin'],
                input=payload,
                capture_output=True,
                text=True,
                env={**os.environ, 'WEBHOOK_HEADERS': headers}
            )
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ok', 'output': result.stdout}).encode())
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'error', 'message': str(e)}).encode())
    
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'healthy'}).encode())
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Webhook Handler Ready\\n')
    
    def log_message(self, format, *args):
        print(f'[HTTP] {self.address_string()} - {format % args}')

with socketserver.TCPServer(('', PORT), WebhookHandler) as httpd:
    print(f'Webhook server listening on port {PORT}')
    httpd.serve_forever()
"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    parse_args "$@"
    
    # Create log directory if needed
    if [[ -n "$WEBHOOK_LOG" ]]; then
        mkdir -p "$(dirname "$WEBHOOK_LOG")" 2>/dev/null || true
    fi
    
    case "$ACTION" in
        serve)
            log_info "Starting webhook server..."
            if command -v python3 &> /dev/null; then
                start_python_server
            else
                log_error "Python3 is required to run the HTTP server"
                exit 1
            fi
            ;;
        process)
            if [[ ! -f "$PAYLOAD_FILE" ]]; then
                log_error "Payload file not found: $PAYLOAD_FILE"
                exit 1
            fi
            payload=$(cat "$PAYLOAD_FILE")
            process_payload "$payload"
            ;;
        stdin)
            payload=$(cat)
            headers="${WEBHOOK_HEADERS:-}"
            process_payload "$payload" "$headers"
            ;;
        *)
            usage
            ;;
    esac
}

# Run main function
main "$@"
