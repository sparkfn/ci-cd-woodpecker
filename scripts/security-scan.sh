#!/usr/bin/env bash
# =============================================================================
# Security Scan Wrapper Script
# =============================================================================
# Wrapper script for running Trivy security scans with configurable options.
# Can be used locally or in CI pipelines.
#
# Usage:
#   ./scripts/security-scan.sh [options]
#
# Options:
#   --type TYPE       Scan type: fs, image, config, repo (default: fs)
#   --target TARGET   Target to scan (default: current directory)
#   --severity SEV    Severity threshold (default: HIGH,CRITICAL)
#   --format FORMAT   Output format: table, json, sarif (default: table)
#   --output FILE     Output file (optional)
#   --exit-code CODE  Exit code on vulnerabilities (default: 0)
#   --ignore-unfixed  Ignore unfixed vulnerabilities
#   --config FILE     Path to trivy config file
#   --sbom            Generate SBOM instead of vulnerability scan
#   --quiet           Suppress progress output
#   --help            Show this help message
#
# Examples:
#   ./scripts/security-scan.sh                          # Basic scan
#   ./scripts/security-scan.sh --severity CRITICAL      # Only critical
#   ./scripts/security-scan.sh --type image myapp:latest # Scan image
#   ./scripts/security-scan.sh --sbom --output sbom.json # Generate SBOM
#
# Version: 0.0.5
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration Defaults
# -----------------------------------------------------------------------------
SCAN_TYPE="fs"
TARGET="."
SEVERITY="HIGH,CRITICAL"
FORMAT="table"
OUTPUT=""
EXIT_CODE="0"
IGNORE_UNFIXED="false"
CONFIG_FILE="config/trivy.yaml"
GENERATE_SBOM="false"
QUIET="false"

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
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
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
    head -40 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

check_trivy() {
    if ! command -v trivy &> /dev/null; then
        log_error "Trivy is not installed!"
        echo ""
        echo "Install Trivy:"
        echo "  brew install trivy              # macOS"
        echo "  apt-get install trivy           # Debian/Ubuntu"
        echo "  docker pull aquasec/trivy       # Docker"
        echo ""
        echo "Or visit: https://github.com/aquasecurity/trivy#installation"
        exit 1
    fi
    log_info "Trivy version: $(trivy --version | head -1)"
}

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            SCAN_TYPE="$2"
            shift 2
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --exit-code)
            EXIT_CODE="$2"
            shift 2
            ;;
        --ignore-unfixed)
            IGNORE_UNFIXED="true"
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --sbom)
            GENERATE_SBOM="true"
            shift
            ;;
        --quiet|-q)
            QUIET="true"
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            # Positional argument as target
            TARGET="$1"
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Main Script
# -----------------------------------------------------------------------------

main() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "🔒 Security Scan Starting"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check Trivy installation
    check_trivy

    # Build Trivy command
    local cmd="trivy"
    local args=()

    # Add scan type
    case "$SCAN_TYPE" in
        fs|filesystem)
            args+=("fs")
            ;;
        image|docker)
            args+=("image")
            ;;
        config|iac)
            args+=("config")
            ;;
        repo|repository)
            args+=("repo")
            ;;
        sbom)
            args+=("sbom")
            GENERATE_SBOM="true"
            ;;
        *)
            log_error "Unknown scan type: $SCAN_TYPE"
            log_info "Valid types: fs, image, config, repo, sbom"
            exit 1
            ;;
    esac

    # Generate SBOM instead of vulnerability scan
    if [[ "$GENERATE_SBOM" == "true" ]]; then
        log_info "Generating Software Bill of Materials (SBOM)..."
        args=("fs" "--format" "cyclonedx")
        if [[ -n "$OUTPUT" ]]; then
            args+=("--output" "$OUTPUT")
        fi
        args+=("$TARGET")
        
        log_info "Running: trivy ${args[*]}"
        trivy "${args[@]}"
        
        if [[ -n "$OUTPUT" ]]; then
            log_success "SBOM saved to: $OUTPUT"
        fi
        return 0
    fi

    # Add configuration file if exists
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Using config file: $CONFIG_FILE"
        args+=("--config" "$CONFIG_FILE")
    fi

    # Add severity filter
    args+=("--severity" "$SEVERITY")

    # Add exit code
    args+=("--exit-code" "$EXIT_CODE")

    # Add format
    args+=("--format" "$FORMAT")

    # Add output file if specified
    if [[ -n "$OUTPUT" ]]; then
        args+=("--output" "$OUTPUT")
    fi

    # Ignore unfixed vulnerabilities
    if [[ "$IGNORE_UNFIXED" == "true" ]]; then
        args+=("--ignore-unfixed")
    fi

    # Check for .trivyignore file
    if [[ -f ".trivyignore" ]]; then
        log_info "Using .trivyignore file"
        args+=("--ignorefile" ".trivyignore")
    fi

    # Add target
    args+=("$TARGET")

    # Print configuration
    log_info "Scan type:     $SCAN_TYPE"
    log_info "Target:        $TARGET"
    log_info "Severity:      $SEVERITY"
    log_info "Format:        $FORMAT"
    log_info "Exit code:     $EXIT_CODE"
    log_info "Ignore unfixed: $IGNORE_UNFIXED"
    echo ""

    # Run Trivy
    log_info "Running: trivy ${args[*]}"
    echo ""

    local scan_exit_code=0
    trivy "${args[@]}" || scan_exit_code=$?

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ $scan_exit_code -eq 0 ]]; then
        log_success "Security scan completed - no blocking vulnerabilities found"
    else
        log_warning "Security scan completed - vulnerabilities found (exit code: $scan_exit_code)"
    fi

    if [[ -n "$OUTPUT" ]]; then
        log_info "Report saved to: $OUTPUT"
    fi

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    return $scan_exit_code
}

# Run main function
main
