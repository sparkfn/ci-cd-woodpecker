#!/usr/bin/env bash
# =============================================================================
# AI Auto-fix Script
# =============================================================================
# Triggers an AI coding agent to fix issues from failed tests or security scans.
#
# Supported AI Agents:
#   - claude-code   : Claude Code (Anthropic)
#   - codex         : OpenAI Codex / GPT-4
#   - openhands     : OpenHands (formerly OpenDevin)
#   - opencode      : OpenCode (local CLI agent)
#
# Usage:
#   ./ai-fix.sh --error-file <path> --repo <path> [--provider <agent>]
#
# Environment Variables:
#   AI_FIX_PROVIDER      - Default AI provider
#   AI_FIX_MAX_ATTEMPTS  - Max fix attempts (default: 3)
#   AI_FIX_TIMEOUT       - Timeout per attempt in seconds (default: 300)
#   ANTHROPIC_API_KEY    - API key for Claude
#   OPENAI_API_KEY       - API key for OpenAI/Codex
#   GITHUB_TOKEN         - For creating branches/commits
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants & Defaults
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
DEFAULT_CONFIG="${CONFIG_DIR}/ai-fix.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults (can be overridden by env or args)
PROVIDER="${AI_FIX_PROVIDER:-claude-code}"
MAX_ATTEMPTS="${AI_FIX_MAX_ATTEMPTS:-3}"
TIMEOUT="${AI_FIX_TIMEOUT:-300}"
DRY_RUN=false
VERBOSE=false

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
AI Auto-fix Script - Automatically fix code issues using AI agents

USAGE:
    $(basename "$0") [OPTIONS]

REQUIRED:
    --error-file <path>     Path to file containing error output
    --repo <path>           Path to the repository to fix

OPTIONS:
    --provider <agent>      AI provider: claude-code, codex, openhands, opencode
                            (default: ${PROVIDER})
    --config <path>         Path to config file (default: ${DEFAULT_CONFIG})
    --branch <name>         Branch name for fix (default: ai-fix/<timestamp>)
    --max-attempts <n>      Maximum fix attempts (default: ${MAX_ATTEMPTS})
    --timeout <seconds>     Timeout per attempt (default: ${TIMEOUT})
    --issue-number <n>      Related GitHub issue number (optional)
    --dry-run               Show what would be done without executing
    --verbose               Enable verbose output
    --help                  Show this help message

ENVIRONMENT VARIABLES:
    AI_FIX_PROVIDER         Default AI provider
    AI_FIX_MAX_ATTEMPTS     Max fix attempts
    AI_FIX_TIMEOUT          Timeout in seconds
    ANTHROPIC_API_KEY       API key for Claude Code
    OPENAI_API_KEY          API key for OpenAI/Codex
    GITHUB_TOKEN            GitHub token for branch/commit operations

EXAMPLES:
    # Fix using Claude Code
    $(basename "$0") --error-file ./test-output.log --repo /path/to/repo

    # Fix using Codex with custom branch
    $(basename "$0") --error-file ./errors.txt --repo . --provider codex --branch fix/test-errors

    # Dry run to see what would happen
    $(basename "$0") --error-file ./scan.log --repo . --dry-run --verbose

EXIT CODES:
    0   Fix applied successfully
    1   Fix failed after all attempts
    2   Invalid arguments or configuration
    3   AI provider error
    4   Git operation error
EOF
}

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --error-file)
                ERROR_FILE="$2"
                shift 2
                ;;
            --repo)
                REPO_PATH="$2"
                shift 2
                ;;
            --provider)
                PROVIDER="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --branch)
                FIX_BRANCH="$2"
                shift 2
                ;;
            --max-attempts)
                MAX_ATTEMPTS="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --issue-number)
                ISSUE_NUMBER="$2"
                shift 2
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
    if [[ -z "${ERROR_FILE:-}" ]]; then
        log_error "Missing required argument: --error-file"
        usage
        exit 2
    fi

    if [[ -z "${REPO_PATH:-}" ]]; then
        log_error "Missing required argument: --repo"
        usage
        exit 2
    fi

    # Set defaults
    CONFIG_FILE="${CONFIG_FILE:-$DEFAULT_CONFIG}"
    FIX_BRANCH="${FIX_BRANCH:-ai-fix/$(date +%Y%m%d-%H%M%S)}"
}

# -----------------------------------------------------------------------------
# Validation Functions
# -----------------------------------------------------------------------------
validate_environment() {
    log_info "Validating environment..."

    # Check error file exists
    if [[ ! -f "$ERROR_FILE" ]]; then
        log_error "Error file not found: $ERROR_FILE"
        exit 2
    fi

    # Check repo exists
    if [[ ! -d "$REPO_PATH" ]]; then
        log_error "Repository path not found: $REPO_PATH"
        exit 2
    fi

    # Check repo is a git repository
    if [[ ! -d "$REPO_PATH/.git" ]]; then
        log_error "Not a git repository: $REPO_PATH"
        exit 2
    fi

    # Validate provider and API keys
    case "$PROVIDER" in
        claude-code)
            if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
                log_error "ANTHROPIC_API_KEY is required for claude-code provider"
                exit 2
            fi
            # Check if claude command exists
            if ! command -v claude &>/dev/null; then
                log_warn "claude CLI not found, will attempt to use API directly"
            fi
            ;;
        codex)
            if [[ -z "${OPENAI_API_KEY:-}" ]]; then
                log_error "OPENAI_API_KEY is required for codex provider"
                exit 2
            fi
            ;;
        openhands)
            # OpenHands may use local models or API
            log_debug "OpenHands provider selected"
            ;;
        opencode)
            if ! command -v opencode &>/dev/null; then
                log_error "opencode CLI not found"
                exit 2
            fi
            ;;
        *)
            log_error "Unknown provider: $PROVIDER"
            log_error "Supported providers: claude-code, codex, openhands, opencode"
            exit 2
            ;;
    esac

    log_success "Environment validated"
}

# -----------------------------------------------------------------------------
# Git Operations
# -----------------------------------------------------------------------------
create_fix_branch() {
    log_info "Creating fix branch: $FIX_BRANCH"

    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create branch: $FIX_BRANCH"
        return 0
    fi

    # Ensure we're on the latest main/master
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

    git fetch origin "$default_branch" 2>/dev/null || true
    git checkout "$default_branch" 2>/dev/null || git checkout main 2>/dev/null || git checkout master
    git pull origin "$default_branch" 2>/dev/null || true

    # Create and checkout fix branch
    git checkout -b "$FIX_BRANCH"

    log_success "Created branch: $FIX_BRANCH"
}

commit_fix() {
    local message="$1"

    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would commit with message: $message"
        return 0
    fi

    # Stage all changes
    git add -A

    # Check if there are changes to commit
    if git diff --staged --quiet; then
        log_warn "No changes to commit"
        return 1
    fi

    # Commit with message
    git commit -m "$message"

    log_success "Committed changes"
}

push_fix_branch() {
    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would push branch: $FIX_BRANCH"
        return 0
    fi

    git push -u origin "$FIX_BRANCH"

    log_success "Pushed branch: $FIX_BRANCH"
}

rollback_changes() {
    log_warn "Rolling back changes..."

    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would rollback changes"
        return 0
    fi

    # Discard all uncommitted changes
    git checkout -- .
    git clean -fd

    log_info "Changes rolled back"
}

# -----------------------------------------------------------------------------
# AI Provider Functions
# -----------------------------------------------------------------------------
build_prompt() {
    local error_content
    error_content=$(cat "$ERROR_FILE")

    cat <<EOF
You are an expert software engineer fixing a CI/CD failure.

## Error Output
\`\`\`
${error_content}
\`\`\`

## Instructions
1. Analyze the error output above
2. Identify the root cause of the failure
3. Make the minimal changes necessary to fix the issue
4. Do NOT introduce new features or refactoring
5. Ensure tests will pass after your fix
6. If you cannot fix the issue, explain why

## Repository Context
- Working directory: ${REPO_PATH}
- Fix branch: ${FIX_BRANCH}
${ISSUE_NUMBER:+"- Related issue: #${ISSUE_NUMBER}"}

Please fix the code to resolve this CI failure.
EOF
}

run_claude_code() {
    log_info "Running Claude Code fix..."

    local prompt
    prompt=$(build_prompt)

    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run Claude Code with prompt"
        log_debug "Prompt:\n$prompt"
        return 0
    fi

    # Check if claude CLI is available
    if command -v claude &>/dev/null; then
        # Use Claude Code CLI (interactive mode)
        echo "$prompt" | timeout "$TIMEOUT" claude --dangerously-skip-permissions \
            2>&1 | tee /tmp/ai-fix-output.log

        return ${PIPESTATUS[0]}
    else
        # Fallback to API call
        log_info "Using Claude API directly..."

        local response
        response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${ANTHROPIC_API_KEY}" \
            -H "anthropic-version: 2023-06-01" \
            -d @- <<EOF
{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 4096,
    "messages": [
        {
            "role": "user",
            "content": $(echo "$prompt" | jq -Rs .)
        }
    ]
}
EOF
        )

        # Extract and apply the fix from response
        echo "$response" | jq -r '.content[0].text' | tee /tmp/ai-fix-response.txt

        log_warn "API response saved to /tmp/ai-fix-response.txt"
        log_warn "Manual review required - API mode cannot directly modify files"
        return 1
    fi
}

run_codex() {
    log_info "Running OpenAI Codex fix..."

    local prompt
    prompt=$(build_prompt)

    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run Codex with prompt"
        return 0
    fi

    # Use OpenAI API with code-focused model
    local response
    response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -d @- <<EOF
{
    "model": "gpt-4-turbo-preview",
    "messages": [
        {
            "role": "system",
            "content": "You are an expert software engineer. Respond with code fixes only."
        },
        {
            "role": "user",
            "content": $(echo "$prompt" | jq -Rs .)
        }
    ],
    "max_tokens": 4096,
    "temperature": 0.1
}
EOF
    )

    echo "$response" | jq -r '.choices[0].message.content' | tee /tmp/ai-fix-response.txt

    log_warn "Codex response saved to /tmp/ai-fix-response.txt"
    log_warn "Manual application may be required"
    return 0
}

run_openhands() {
    log_info "Running OpenHands fix..."

    local prompt
    prompt=$(build_prompt)

    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run OpenHands with prompt"
        return 0
    fi

    # Check if openhands CLI is available
    if command -v openhands &>/dev/null; then
        echo "$prompt" | timeout "$TIMEOUT" openhands \
            --workspace "$REPO_PATH" \
            2>&1 | tee /tmp/ai-fix-output.log

        return ${PIPESTATUS[0]}
    else
        # Try Docker-based OpenHands
        if command -v docker &>/dev/null; then
            log_info "Running OpenHands via Docker..."

            docker run --rm -it \
                -v "$REPO_PATH:/workspace" \
                -e "PROMPT=$prompt" \
                ghcr.io/all-hands-ai/openhands:latest \
                2>&1 | tee /tmp/ai-fix-output.log

            return ${PIPESTATUS[0]}
        else
            log_error "OpenHands CLI not found and Docker not available"
            return 1
        fi
    fi
}

run_opencode() {
    log_info "Running OpenCode fix..."

    local prompt
    prompt=$(build_prompt)

    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run OpenCode with prompt"
        return 0
    fi

    # Run opencode CLI
    echo "$prompt" | timeout "$TIMEOUT" opencode \
        2>&1 | tee /tmp/ai-fix-output.log

    return ${PIPESTATUS[0]}
}

run_ai_fix() {
    case "$PROVIDER" in
        claude-code)
            run_claude_code
            ;;
        codex)
            run_codex
            ;;
        openhands)
            run_openhands
            ;;
        opencode)
            run_opencode
            ;;
        *)
            log_error "Unknown provider: $PROVIDER"
            return 3
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Test Verification
# -----------------------------------------------------------------------------
verify_fix() {
    log_info "Verifying fix..."

    cd "$REPO_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify fix by running tests"
        return 0
    fi

    # Try to detect and run project tests
    if [[ -f "package.json" ]]; then
        # Node.js project
        if grep -q '"test"' package.json; then
            npm test 2>&1 | tee /tmp/test-output.log
            return ${PIPESTATUS[0]}
        fi
    elif [[ -f "Cargo.toml" ]]; then
        # Rust project
        cargo test 2>&1 | tee /tmp/test-output.log
        return ${PIPESTATUS[0]}
    elif [[ -f "go.mod" ]]; then
        # Go project
        go test ./... 2>&1 | tee /tmp/test-output.log
        return ${PIPESTATUS[0]}
    elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
        # Python project
        if command -v pytest &>/dev/null; then
            pytest 2>&1 | tee /tmp/test-output.log
            return ${PIPESTATUS[0]}
        elif command -v python &>/dev/null; then
            python -m pytest 2>&1 | tee /tmp/test-output.log
            return ${PIPESTATUS[0]}
        fi
    elif [[ -f "Makefile" ]]; then
        # Makefile project
        if grep -q '^test:' Makefile; then
            make test 2>&1 | tee /tmp/test-output.log
            return ${PIPESTATUS[0]}
        fi
    fi

    log_warn "Could not detect test framework, skipping verification"
    return 0
}

# -----------------------------------------------------------------------------
# Output Functions
# -----------------------------------------------------------------------------
save_result() {
    local status="$1"
    local message="$2"
    local output_file="${3:-/tmp/ai-fix-result.json}"

    cat > "$output_file" <<EOF
{
    "status": "${status}",
    "message": "${message}",
    "provider": "${PROVIDER}",
    "branch": "${FIX_BRANCH}",
    "repo": "${REPO_PATH}",
    "error_file": "${ERROR_FILE}",
    "issue_number": "${ISSUE_NUMBER:-null}",
    "attempts": ${ATTEMPT:-0},
    "max_attempts": ${MAX_ATTEMPTS},
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
    log_info "AI Auto-fix Script"
    log_info "=========================================="
    log_info "Provider: $PROVIDER"
    log_info "Error file: $ERROR_FILE"
    log_info "Repository: $REPO_PATH"
    log_info "Max attempts: $MAX_ATTEMPTS"
    log_info "Timeout: ${TIMEOUT}s"
    log_info "Dry run: $DRY_RUN"
    log_info "=========================================="

    validate_environment

    # Create fix branch
    create_fix_branch

    # Attempt fixes
    local ATTEMPT=0
    local fix_success=false

    while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
        ATTEMPT=$((ATTEMPT + 1))
        log_info "Attempt $ATTEMPT of $MAX_ATTEMPTS"

        # Run AI fix
        if run_ai_fix; then
            log_success "AI fix completed"

            # Verify the fix
            if verify_fix; then
                log_success "Fix verified successfully!"
                fix_success=true

                # Commit the fix
                local commit_msg="fix: AI auto-fix attempt #${ATTEMPT}"
                if [[ -n "${ISSUE_NUMBER:-}" ]]; then
                    commit_msg="fix: AI auto-fix for issue #${ISSUE_NUMBER} (attempt #${ATTEMPT})"
                fi

                if commit_fix "$commit_msg"; then
                    push_fix_branch
                    break
                fi
            else
                log_warn "Fix verification failed, rolling back..."
                rollback_changes
            fi
        else
            log_warn "AI fix failed, attempt $ATTEMPT of $MAX_ATTEMPTS"
            rollback_changes
        fi

        # Brief pause before retry
        if [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; then
            sleep 5
        fi
    done

    if [[ "$fix_success" == "true" ]]; then
        log_success "=========================================="
        log_success "AI Auto-fix completed successfully!"
        log_success "Branch: $FIX_BRANCH"
        log_success "=========================================="
        save_result "success" "Fix applied successfully"
        exit 0
    else
        log_error "=========================================="
        log_error "AI Auto-fix failed after $MAX_ATTEMPTS attempts"
        log_error "=========================================="
        save_result "failed" "Fix failed after $MAX_ATTEMPTS attempts"
        exit 1
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
