#!/usr/bin/env bash
# =============================================================================
# Rollback Script
# Version: 0.0.9
#
# Rolls back a deployment to the previous version or a specific version.
# Supports Docker, Kubernetes, and SSH rollback methods.
#
# Usage:
#   ./rollback.sh --env production --app myapp                    # Rollback to previous version
#   ./rollback.sh --env production --app myapp --to-version 1.0.0  # Rollback to specific version
#   ./rollback.sh --env production --app myapp --list-backups      # List available backups
#
# Environment Variables:
#   DEPLOY_METHOD     - docker|docker-compose|ssh|kubernetes|helm
#   STATE_DIR         - Directory for deployment state files
#   BACKUP_DIR        - Directory for backups
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
DEPLOY_ENV="${DEPLOY_ENV:-staging}"
DEPLOY_METHOD="${DEPLOY_METHOD:-docker}"
APP_NAME="${APP_NAME:-myapp}"
TARGET_VERSION=""
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
LIST_BACKUPS="${LIST_BACKUPS:-false}"
FORCE="${FORCE:-false}"

# State directories
STATE_DIR="${STATE_DIR:-/var/lib/deploy-state}"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/deploy-backups}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Logging Functions
# =============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Rollback script for reverting deployments to previous versions.

OPTIONS:
    -e, --env ENV           Target environment (staging|production) [default: staging]
    -a, --app APP          Application name [default: myapp]
    -t, --to-version VER   Target version to rollback to (optional)
    -m, --method METHOD    Deployment method (docker|docker-compose|ssh|kubernetes|helm)
    --list-backups         List available backups and exit
    --force                Skip confirmation prompts
    --dry-run              Show what would be done without executing
    --verbose              Enable verbose output
    -h, --help             Show this help message

EXAMPLES:
    # Rollback to previous version
    $(basename "$0") --env production --app myapp

    # Rollback to specific version
    $(basename "$0") --env production --app myapp --to-version 1.0.0

    # List available backups
    $(basename "$0") --env production --app myapp --list-backups

    # Rollback with Kubernetes
    $(basename "$0") --env production --method kubernetes --app myapp

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--env)
                DEPLOY_ENV="$2"
                shift 2
                ;;
            -a|--app)
                APP_NAME="$2"
                shift 2
                ;;
            -t|--to-version)
                TARGET_VERSION="$2"
                shift 2
                ;;
            -m|--method)
                DEPLOY_METHOD="$2"
                shift 2
                ;;
            --list-backups)
                LIST_BACKUPS="true"
                shift
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
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

# Get current deployment state
get_current_state() {
    local state_file="${STATE_DIR}/${APP_NAME}-${DEPLOY_ENV}.state"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "{}"
    fi
}

# Get previous version from backup
get_previous_version() {
    # Look for the most recent backup version file
    local version_file
    version_file=$(ls -t "${BACKUP_DIR}/${APP_NAME}-${DEPLOY_ENV}-"*.version 2>/dev/null | head -1)
    
    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    else
        # Try to get from state files
        local state_files
        state_files=$(ls -t "${BACKUP_DIR}/${APP_NAME}-${DEPLOY_ENV}-"*.state 2>/dev/null | head -1)
        if [[ -f "$state_files" ]]; then
            grep -o '"version": "[^"]*"' "$state_files" | head -1 | cut -d'"' -f4
        fi
    fi
}

# List available backups
list_backups() {
    log_info "Available backups for $APP_NAME in $DEPLOY_ENV:"
    echo ""
    
    local found=false
    
    # List version files
    for version_file in "${BACKUP_DIR}/${APP_NAME}-${DEPLOY_ENV}-"*.version 2>/dev/null; do
        if [[ -f "$version_file" ]]; then
            found=true
            local timestamp
            timestamp=$(basename "$version_file" | sed "s/${APP_NAME}-${DEPLOY_ENV}-//" | sed 's/\.version$//')
            local version
            version=$(cat "$version_file")
            local backup_file="${version_file%.version}.tar.gz"
            local size=""
            if [[ -f "$backup_file" ]]; then
                size=$(du -h "$backup_file" | cut -f1)
            fi
            printf "  %s  -  Version: %s  %s\n" "$timestamp" "$version" "${size:+(Size: $size)}"
        fi
    done
    
    # List state files
    for state_file in "${BACKUP_DIR}/${APP_NAME}-${DEPLOY_ENV}-"*.state 2>/dev/null; do
        if [[ -f "$state_file" ]]; then
            found=true
            local timestamp
            timestamp=$(basename "$state_file" | sed "s/${APP_NAME}-${DEPLOY_ENV}-//" | sed 's/\.state$//')
            local version
            version=$(grep -o '"version": "[^"]*"' "$state_file" | cut -d'"' -f4)
            printf "  %s  -  Version: %s  (state file)\n" "$timestamp" "${version:-unknown}"
        fi
    done
    
    if [[ "$found" == "false" ]]; then
        log_warn "No backups found in $BACKUP_DIR"
    fi
    
    echo ""
}

# Confirm rollback with user
confirm_rollback() {
    local current_version="$1"
    local target_version="$2"
    
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "=== ROLLBACK CONFIRMATION ==="
    echo "Application: $APP_NAME"
    echo "Environment: $DEPLOY_ENV"
    echo "Current Version: ${current_version:-unknown}"
    echo "Target Version: ${target_version:-previous}"
    echo ""
    
    read -rp "Are you sure you want to rollback? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi
}

# =============================================================================
# Rollback Methods
# =============================================================================

# Docker rollback
rollback_docker() {
    local target_version="$1"
    local container_name="${APP_NAME}-${DEPLOY_ENV}"
    local image="${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}${APP_NAME}:${target_version}"
    
    log_info "Rolling back Docker container to version: $target_version"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would rollback to image: $image"
        return 0
    fi
    
    # Stop current container
    log_debug "Stopping current container..."
    docker stop "$container_name" 2>/dev/null || true
    docker rm "$container_name" 2>/dev/null || true
    
    # Check if we have a backup to restore from
    local backup_file="${BACKUP_DIR}/${APP_NAME}-${DEPLOY_ENV}-"*.tar.gz
    # shellcheck disable=SC2086
    backup_file=$(ls -t $backup_file 2>/dev/null | head -1)
    
    if [[ -f "$backup_file" && -z "$target_version" ]]; then
        log_info "Restoring from backup: $backup_file"
        # Import backup image
        local temp_image="${APP_NAME}-restore-temp"
        zcat "$backup_file" | docker import - "$temp_image"
        image="$temp_image"
    fi
    
    # Start container with target version
    log_info "Starting container with version: $target_version"
    docker run -d \
        --name "$container_name" \
        --restart unless-stopped \
        -e APP_ENV="$DEPLOY_ENV" \
        -e APP_VERSION="$target_version" \
        --label "app=$APP_NAME" \
        --label "env=$DEPLOY_ENV" \
        --label "version=$target_version" \
        --label "rollback=true" \
        "$image"
    
    log_success "Docker rollback complete"
}

# Docker Compose rollback
rollback_docker_compose() {
    local target_version="$1"
    
    log_info "Rolling back Docker Compose deployment to version: $target_version"
    
    local compose_file="docker-compose.${DEPLOY_ENV}.yml"
    if [[ ! -f "$compose_file" ]]; then
        compose_file="docker-compose.yml"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would rollback docker-compose with version: $target_version"
        return 0
    fi
    
    export APP_VERSION="$target_version"
    export DEPLOY_ENV
    
    # Stop current deployment
    docker compose -f "$compose_file" down
    
    # Start with target version
    docker compose -f "$compose_file" up -d --remove-orphans
    
    log_success "Docker Compose rollback complete"
}

# SSH rollback
rollback_ssh() {
    local target_version="$1"
    
    log_info "Rolling back via SSH to version: $target_version"
    
    if [[ -z "$SSH_HOST" || -z "$SSH_USER" ]]; then
        log_error "SSH_HOST and SSH_USER must be set for SSH rollback"
        exit 1
    fi
    
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    if [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]; then
        ssh_opts="$ssh_opts -i $SSH_KEY"
    fi
    
    local remote_cmd="
        cd /opt/${APP_NAME} && \
        docker pull ${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}${APP_NAME}:${target_version} && \
        docker stop ${APP_NAME} 2>/dev/null || true && \
        docker rm ${APP_NAME} 2>/dev/null || true && \
        docker run -d --name ${APP_NAME} --restart unless-stopped \
            -e APP_ENV=${DEPLOY_ENV} \
            -e ROLLBACK=true \
            ${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}${APP_NAME}:${target_version}
    "
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would SSH to $SSH_USER@$SSH_HOST and rollback to $target_version"
        return 0
    fi
    
    # shellcheck disable=SC2086
    ssh $ssh_opts "${SSH_USER}@${SSH_HOST}" "$remote_cmd"
    
    log_success "SSH rollback complete"
}

# Kubernetes rollback
rollback_kubernetes() {
    local target_version="$1"
    local namespace="${K8S_NAMESPACE:-default}"
    
    log_info "Rolling back Kubernetes deployment..."
    
    if [[ -n "${KUBECONFIG:-}" ]]; then
        export KUBECONFIG
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would rollback Kubernetes deployment in namespace: $namespace"
        return 0
    fi
    
    if [[ -z "$target_version" ]]; then
        # Rollback to previous revision
        log_info "Rolling back to previous revision..."
        kubectl rollout undo deployment/"$APP_NAME" -n "$namespace"
    else
        # Rollback to specific version by setting image
        local image="${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}${APP_NAME}:${target_version}"
        log_info "Rolling back to version: $target_version"
        kubectl set image deployment/"$APP_NAME" "$APP_NAME"="$image" -n "$namespace"
    fi
    
    # Wait for rollback to complete
    log_info "Waiting for rollback to complete..."
    kubectl rollout status deployment/"$APP_NAME" -n "$namespace" --timeout=300s
    
    log_success "Kubernetes rollback complete"
}

# Helm rollback
rollback_helm() {
    local target_version="$1"
    local release_name="${HELM_RELEASE:-$APP_NAME}"
    local namespace="${K8S_NAMESPACE:-default}"
    
    log_info "Rolling back Helm release: $release_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would rollback Helm release in namespace: $namespace"
        return 0
    fi
    
    if [[ -z "$target_version" ]]; then
        # Rollback to previous release
        log_info "Rolling back to previous Helm revision..."
        helm rollback "$release_name" -n "$namespace" --wait --timeout 5m
    else
        # Get revision number for target version
        log_info "Looking for revision with version: $target_version"
        local revision
        revision=$(helm history "$release_name" -n "$namespace" -o json | \
            python3 -c "import json,sys; h=json.load(sys.stdin); print(next((r['revision'] for r in h if '$target_version' in r.get('description','')), ''))" 2>/dev/null)
        
        if [[ -n "$revision" ]]; then
            log_info "Rolling back to revision: $revision"
            helm rollback "$release_name" "$revision" -n "$namespace" --wait --timeout 5m
        else
            log_warn "Could not find revision for version $target_version, rolling back to previous"
            helm rollback "$release_name" -n "$namespace" --wait --timeout 5m
        fi
    fi
    
    log_success "Helm rollback complete"
}

# =============================================================================
# Main Rollback Logic
# =============================================================================
perform_rollback() {
    local current_state
    current_state=$(get_current_state)
    local current_version
    current_version=$(echo "$current_state" | grep -o '"version": "[^"]*"' | cut -d'"' -f4)
    
    # Determine target version
    local target="$TARGET_VERSION"
    if [[ -z "$target" ]]; then
        target=$(get_previous_version)
        if [[ -z "$target" ]]; then
            log_error "No previous version found. Please specify --to-version"
            exit 1
        fi
        log_info "Found previous version: $target"
    fi
    
    # Confirm rollback
    confirm_rollback "$current_version" "$target"
    
    log_info "Starting rollback: $APP_NAME in $DEPLOY_ENV"
    log_info "From version: ${current_version:-unknown}"
    log_info "To version: $target"
    log_info "Method: $DEPLOY_METHOD"
    
    # Execute rollback based on method
    case "$DEPLOY_METHOD" in
        docker)
            rollback_docker "$target"
            ;;
        docker-compose)
            rollback_docker_compose "$target"
            ;;
        ssh)
            rollback_ssh "$target"
            ;;
        kubernetes)
            rollback_kubernetes "$target"
            ;;
        helm)
            rollback_helm "$target"
            ;;
        *)
            log_error "Unknown deployment method: $DEPLOY_METHOD"
            exit 1
            ;;
    esac
    
    # Update state file
    local state_file="${STATE_DIR}/${APP_NAME}-${DEPLOY_ENV}.state"
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$state_file" <<EOF
{
  "app": "$APP_NAME",
  "version": "$target",
  "environment": "$DEPLOY_ENV",
  "method": "$DEPLOY_METHOD",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployed_by": "${USER:-unknown}",
  "rollback_from": "${current_version:-unknown}",
  "rollback": true
}
EOF
    fi
    
    log_success "Rollback completed successfully!"
    log_info "Rolled back from: ${current_version:-unknown}"
    log_info "Rolled back to: $target"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    parse_args "$@"
    
    log_debug "Configuration:"
    log_debug "  DEPLOY_ENV: $DEPLOY_ENV"
    log_debug "  DEPLOY_METHOD: $DEPLOY_METHOD"
    log_debug "  APP_NAME: $APP_NAME"
    log_debug "  TARGET_VERSION: $TARGET_VERSION"
    log_debug "  DRY_RUN: $DRY_RUN"
    
    # Handle list-backups action
    if [[ "$LIST_BACKUPS" == "true" ]]; then
        list_backups
        exit 0
    fi
    
    # Perform rollback
    perform_rollback
}

# Run main function
main "$@"
