#!/usr/bin/env bash
# =============================================================================
# Deployment Script
# Version: 0.0.9
#
# A comprehensive deployment script supporting multiple deployment methods:
# - Docker (standalone containers)
# - Docker Compose
# - SSH (remote server deployment)
# - Kubernetes (kubectl / Helm)
#
# Usage:
#   ./deploy.sh --env staging --version 1.0.0 --app myapp --config ./config/deploy.yaml
#   ./deploy.sh --env production --action backup --app myapp
#   ./deploy.sh --env staging --method docker-compose --app myapp
#
# Environment Variables (can be set or passed via --config):
#   DEPLOY_METHOD     - docker|docker-compose|ssh|kubernetes|helm
#   DOCKER_REGISTRY   - Docker registry URL
#   SSH_HOST          - Remote host for SSH deployment
#   SSH_USER          - SSH username
#   SSH_KEY           - Path to SSH private key
#   KUBECONFIG        - Path to kubeconfig file
#   K8S_NAMESPACE     - Kubernetes namespace
#   HELM_RELEASE      - Helm release name
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration Defaults
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
DEPLOY_ENV="${DEPLOY_ENV:-staging}"
DEPLOY_METHOD="${DEPLOY_METHOD:-docker}"
APP_NAME="${APP_NAME:-myapp}"
APP_VERSION="${APP_VERSION:-latest}"
CONFIG_FILE=""
ACTION="${ACTION:-deploy}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# State directories
STATE_DIR="${STATE_DIR:-/var/lib/deploy-state}"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/deploy-backups}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

Deployment script supporting Docker, SSH, and Kubernetes deployments.

OPTIONS:
    -e, --env ENV           Target environment (staging|production) [default: staging]
    -v, --version VERSION   Application version to deploy [default: latest]
    -a, --app APP          Application name [default: myapp]
    -m, --method METHOD    Deployment method (docker|docker-compose|ssh|kubernetes|helm)
    -c, --config FILE      Path to deployment config file (YAML)
    --action ACTION        Action to perform (deploy|backup|status|logs) [default: deploy]
    --dry-run              Show what would be done without executing
    --verbose              Enable verbose output
    -h, --help             Show this help message

EXAMPLES:
    # Deploy to staging using Docker
    $(basename "$0") --env staging --version 1.0.0 --app myapp

    # Deploy to production using Kubernetes
    $(basename "$0") --env production --method kubernetes --app myapp --config ./config/deploy.yaml

    # Create a backup before deployment
    $(basename "$0") --env production --action backup --app myapp

    # Check deployment status
    $(basename "$0") --env staging --action status --app myapp

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
            -v|--version)
                APP_VERSION="$2"
                shift 2
                ;;
            -a|--app)
                APP_NAME="$2"
                shift 2
                ;;
            -m|--method)
                DEPLOY_METHOD="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --action)
                ACTION="$2"
                shift 2
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

# Load configuration from YAML file
load_config() {
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        
        # Parse YAML using native tools (requires yq or python)
        if command -v yq &> /dev/null; then
            # Extract environment-specific config
            DEPLOY_METHOD="${DEPLOY_METHOD:-$(yq -r ".environments.${DEPLOY_ENV}.method // \"docker\"" "$CONFIG_FILE")}"
            DOCKER_REGISTRY="${DOCKER_REGISTRY:-$(yq -r ".environments.${DEPLOY_ENV}.registry // \"\"" "$CONFIG_FILE")}"
            SSH_HOST="${SSH_HOST:-$(yq -r ".environments.${DEPLOY_ENV}.ssh.host // \"\"" "$CONFIG_FILE")}"
            SSH_USER="${SSH_USER:-$(yq -r ".environments.${DEPLOY_ENV}.ssh.user // \"\"" "$CONFIG_FILE")}"
            K8S_NAMESPACE="${K8S_NAMESPACE:-$(yq -r ".environments.${DEPLOY_ENV}.kubernetes.namespace // \"default\"" "$CONFIG_FILE")}"
        elif command -v python3 &> /dev/null; then
            # Fallback to Python for YAML parsing
            eval "$(python3 -c "
import yaml
import sys

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

env_config = config.get('environments', {}).get('$DEPLOY_ENV', {})
print(f'DEPLOY_METHOD=\"{env_config.get(\"method\", \"docker\")}\"')
print(f'DOCKER_REGISTRY=\"{env_config.get(\"registry\", \"\")}\"')

ssh = env_config.get('ssh', {})
print(f'SSH_HOST=\"{ssh.get(\"host\", \"\")}\"')
print(f'SSH_USER=\"{ssh.get(\"user\", \"\")}\"')

k8s = env_config.get('kubernetes', {})
print(f'K8S_NAMESPACE=\"{k8s.get(\"namespace\", \"default\")}\"')
")"
        else
            log_warn "No YAML parser found (yq or python3). Using defaults."
        fi
        
        log_debug "Config loaded: method=$DEPLOY_METHOD, env=$DEPLOY_ENV"
    fi
}

# Ensure state directories exist
init_state_dirs() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
}

# Save deployment state
save_state() {
    local state_file="${STATE_DIR}/${APP_NAME}-${DEPLOY_ENV}.state"
    
    cat > "$state_file" <<EOF
{
  "app": "$APP_NAME",
  "version": "$APP_VERSION",
  "environment": "$DEPLOY_ENV",
  "method": "$DEPLOY_METHOD",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployed_by": "${USER:-unknown}",
  "commit": "${CI_COMMIT_SHA:-unknown}"
}
EOF
    log_debug "State saved to $state_file"
}

# Get previous deployment state
get_previous_state() {
    local state_file="${STATE_DIR}/${APP_NAME}-${DEPLOY_ENV}.state"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "{}"
    fi
}

# =============================================================================
# Deployment Methods
# =============================================================================

# Docker deployment (standalone container)
deploy_docker() {
    log_info "Deploying with Docker..."
    
    local image="${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}${APP_NAME}:${APP_VERSION}"
    local container_name="${APP_NAME}-${DEPLOY_ENV}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy Docker image: $image"
        return 0
    fi
    
    # Stop existing container
    log_debug "Stopping existing container: $container_name"
    docker stop "$container_name" 2>/dev/null || true
    docker rm "$container_name" 2>/dev/null || true
    
    # Pull latest image
    log_info "Pulling image: $image"
    docker pull "$image"
    
    # Run new container
    log_info "Starting container: $container_name"
    docker run -d \
        --name "$container_name" \
        --restart unless-stopped \
        -e APP_ENV="$DEPLOY_ENV" \
        -e APP_VERSION="$APP_VERSION" \
        --label "app=$APP_NAME" \
        --label "env=$DEPLOY_ENV" \
        --label "version=$APP_VERSION" \
        "$image"
    
    log_success "Docker deployment complete"
}

# Docker Compose deployment
deploy_docker_compose() {
    log_info "Deploying with Docker Compose..."
    
    local compose_file="docker-compose.${DEPLOY_ENV}.yml"
    if [[ ! -f "$compose_file" ]]; then
        compose_file="docker-compose.yml"
    fi
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "Docker Compose file not found: $compose_file"
        exit 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy using: $compose_file"
        return 0
    fi
    
    # Export environment variables for compose
    export APP_VERSION
    export DEPLOY_ENV
    
    # Pull and recreate
    log_info "Pulling images..."
    docker compose -f "$compose_file" pull
    
    log_info "Starting services..."
    docker compose -f "$compose_file" up -d --remove-orphans
    
    log_success "Docker Compose deployment complete"
}

# SSH deployment (remote server)
deploy_ssh() {
    log_info "Deploying via SSH to $SSH_HOST..."
    
    # Validate SSH configuration
    if [[ -z "$SSH_HOST" || -z "$SSH_USER" ]]; then
        log_error "SSH_HOST and SSH_USER must be set for SSH deployment"
        exit 1
    fi
    
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    if [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]; then
        ssh_opts="$ssh_opts -i $SSH_KEY"
    fi
    
    local remote_cmd="
        cd /opt/${APP_NAME} && \
        docker pull ${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}${APP_NAME}:${APP_VERSION} && \
        docker stop ${APP_NAME} 2>/dev/null || true && \
        docker rm ${APP_NAME} 2>/dev/null || true && \
        docker run -d --name ${APP_NAME} --restart unless-stopped \
            -e APP_ENV=${DEPLOY_ENV} \
            ${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}${APP_NAME}:${APP_VERSION}
    "
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would SSH to $SSH_USER@$SSH_HOST and run deployment"
        log_debug "Command: $remote_cmd"
        return 0
    fi
    
    log_debug "Executing remote command..."
    # shellcheck disable=SC2086
    ssh $ssh_opts "${SSH_USER}@${SSH_HOST}" "$remote_cmd"
    
    log_success "SSH deployment complete"
}

# Kubernetes deployment
deploy_kubernetes() {
    log_info "Deploying to Kubernetes..."
    
    local namespace="${K8S_NAMESPACE:-default}"
    local image="${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}${APP_NAME}:${APP_VERSION}"
    
    # Check for kubeconfig
    if [[ -n "${KUBECONFIG:-}" ]]; then
        export KUBECONFIG
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy to Kubernetes namespace: $namespace"
        return 0
    fi
    
    # Apply manifests if they exist
    local manifests_dir="k8s/${DEPLOY_ENV}"
    if [[ -d "$manifests_dir" ]]; then
        log_info "Applying Kubernetes manifests from $manifests_dir"
        
        # Substitute environment variables in manifests
        for manifest in "$manifests_dir"/*.yaml "$manifests_dir"/*.yml; do
            if [[ -f "$manifest" ]]; then
                log_debug "Applying: $manifest"
                envsubst < "$manifest" | kubectl apply -n "$namespace" -f -
            fi
        done
    else
        # Use kubectl set image for simple deployment
        log_info "Updating deployment image..."
        kubectl set image deployment/"$APP_NAME" \
            "$APP_NAME"="$image" \
            -n "$namespace"
    fi
    
    # Wait for rollout
    log_info "Waiting for rollout to complete..."
    kubectl rollout status deployment/"$APP_NAME" -n "$namespace" --timeout=300s
    
    log_success "Kubernetes deployment complete"
}

# Helm deployment
deploy_helm() {
    log_info "Deploying with Helm..."
    
    local release_name="${HELM_RELEASE:-$APP_NAME}"
    local namespace="${K8S_NAMESPACE:-default}"
    local chart_path="${HELM_CHART:-./charts/$APP_NAME}"
    local values_file="values-${DEPLOY_ENV}.yaml"
    
    if [[ ! -d "$chart_path" ]]; then
        log_error "Helm chart not found: $chart_path"
        exit 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would Helm upgrade $release_name in namespace $namespace"
        return 0
    fi
    
    # Build helm upgrade command
    local helm_cmd="helm upgrade --install $release_name $chart_path"
    helm_cmd="$helm_cmd --namespace $namespace --create-namespace"
    helm_cmd="$helm_cmd --set image.tag=$APP_VERSION"
    helm_cmd="$helm_cmd --set image.repository=${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}$APP_NAME"
    
    if [[ -f "$chart_path/$values_file" ]]; then
        helm_cmd="$helm_cmd -f $chart_path/$values_file"
    fi
    
    log_debug "Executing: $helm_cmd"
    eval "$helm_cmd" --wait --timeout 5m
    
    log_success "Helm deployment complete"
}

# =============================================================================
# Actions
# =============================================================================

# Create backup of current deployment
action_backup() {
    log_info "Creating backup for $APP_NAME in $DEPLOY_ENV..."
    
    local backup_file="${BACKUP_DIR}/${APP_NAME}-${DEPLOY_ENV}-$(date +%Y%m%d%H%M%S).tar.gz"
    local state_file="${STATE_DIR}/${APP_NAME}-${DEPLOY_ENV}.state"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create backup at: $backup_file"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    
    # Get current state
    local previous_version=""
    if [[ -f "$state_file" ]]; then
        previous_version=$(grep -o '"version": "[^"]*"' "$state_file" | cut -d'"' -f4)
    fi
    
    if [[ -n "$previous_version" && "$previous_version" != "unknown" ]]; then
        log_info "Backing up version: $previous_version"
        
        # Create backup based on deployment method
        case "$DEPLOY_METHOD" in
            docker|docker-compose)
                local container_name="${APP_NAME}-${DEPLOY_ENV}"
                if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                    # Export container filesystem
                    docker export "$container_name" | gzip > "$backup_file"
                    # Save current image tag
                    echo "$previous_version" > "${backup_file%.tar.gz}.version"
                fi
                ;;
            kubernetes)
                # Export current deployment spec
                kubectl get deployment "$APP_NAME" -n "${K8S_NAMESPACE:-default}" -o yaml | gzip > "$backup_file"
                ;;
            *)
                log_warn "Backup not implemented for method: $DEPLOY_METHOD"
                ;;
        esac
        
        if [[ -f "$backup_file" ]]; then
            log_success "Backup created: $backup_file"
        fi
    else
        log_warn "No previous deployment found to backup"
    fi
    
    # Copy current state file
    if [[ -f "$state_file" ]]; then
        cp "$state_file" "${BACKUP_DIR}/${APP_NAME}-${DEPLOY_ENV}-$(date +%Y%m%d%H%M%S).state"
    fi
}

# Show deployment status
action_status() {
    log_info "Checking status for $APP_NAME in $DEPLOY_ENV..."
    
    echo ""
    echo "=== Deployment Status ==="
    echo "App: $APP_NAME"
    echo "Environment: $DEPLOY_ENV"
    echo "Method: $DEPLOY_METHOD"
    echo ""
    
    # Show previous state
    local state=$(get_previous_state)
    if [[ "$state" != "{}" ]]; then
        echo "=== Last Deployment ==="
        echo "$state" | python3 -m json.tool 2>/dev/null || echo "$state"
        echo ""
    fi
    
    # Show current status based on method
    case "$DEPLOY_METHOD" in
        docker)
            echo "=== Container Status ==="
            docker ps -a --filter "label=app=$APP_NAME" --filter "label=env=$DEPLOY_ENV" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
            ;;
        docker-compose)
            echo "=== Docker Compose Status ==="
            docker compose ps 2>/dev/null || echo "No compose project found"
            ;;
        kubernetes)
            echo "=== Kubernetes Status ==="
            kubectl get deployment,pods,svc -l "app=$APP_NAME" -n "${K8S_NAMESPACE:-default}" 2>/dev/null || echo "No Kubernetes resources found"
            ;;
        *)
            log_warn "Status check not implemented for method: $DEPLOY_METHOD"
            ;;
    esac
}

# Show deployment logs
action_logs() {
    log_info "Fetching logs for $APP_NAME in $DEPLOY_ENV..."
    
    case "$DEPLOY_METHOD" in
        docker)
            local container_name="${APP_NAME}-${DEPLOY_ENV}"
            docker logs --tail 100 "$container_name" 2>&1 || log_error "Container not found"
            ;;
        docker-compose)
            docker compose logs --tail 100 2>&1 || log_error "No compose project found"
            ;;
        kubernetes)
            kubectl logs -l "app=$APP_NAME" -n "${K8S_NAMESPACE:-default}" --tail 100 2>&1 || log_error "No pods found"
            ;;
        *)
            log_warn "Logs not implemented for method: $DEPLOY_METHOD"
            ;;
    esac
}

# Main deployment action
action_deploy() {
    log_info "Starting deployment: $APP_NAME v$APP_VERSION to $DEPLOY_ENV"
    log_info "Deployment method: $DEPLOY_METHOD"
    
    # Create backup first (if not already doing backup action)
    if [[ "$DEPLOY_ENV" == "production" ]]; then
        log_info "Production deployment - creating backup first..."
        action_backup
    fi
    
    # Execute deployment based on method
    case "$DEPLOY_METHOD" in
        docker)
            deploy_docker
            ;;
        docker-compose)
            deploy_docker_compose
            ;;
        ssh)
            deploy_ssh
            ;;
        kubernetes)
            deploy_kubernetes
            ;;
        helm)
            deploy_helm
            ;;
        *)
            log_error "Unknown deployment method: $DEPLOY_METHOD"
            exit 1
            ;;
    esac
    
    # Save state after successful deployment
    save_state
    
    log_success "Deployment completed successfully!"
    log_info "App: $APP_NAME"
    log_info "Version: $APP_VERSION"
    log_info "Environment: $DEPLOY_ENV"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    parse_args "$@"
    load_config
    init_state_dirs
    
    log_debug "Configuration:"
    log_debug "  DEPLOY_ENV: $DEPLOY_ENV"
    log_debug "  DEPLOY_METHOD: $DEPLOY_METHOD"
    log_debug "  APP_NAME: $APP_NAME"
    log_debug "  APP_VERSION: $APP_VERSION"
    log_debug "  ACTION: $ACTION"
    log_debug "  DRY_RUN: $DRY_RUN"
    
    case "$ACTION" in
        deploy)
            action_deploy
            ;;
        backup)
            action_backup
            ;;
        status)
            action_status
            ;;
        logs)
            action_logs
            ;;
        *)
            log_error "Unknown action: $ACTION"
            usage
            ;;
    esac
}

# Run main function
main "$@"
