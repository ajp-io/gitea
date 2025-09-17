#!/bin/bash

# Update Gitea Helm Chart Script
# This script downloads the latest Gitea chart and carefully updates the local copy
# while preserving any custom configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GITEA_CHART_DIR="$PROJECT_ROOT/gitea"
TEMP_DIR="/tmp/gitea-chart-update"

# Configuration
GITEA_CHART_REPO="https://dl.gitea.com/charts/"
GITEA_CHART_NAME="gitea"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if required tools are installed
check_dependencies() {
    local deps=("helm" "jq" "yq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "$dep is required but not installed. Please install it first."
            exit 1
        fi
    done
}

# Get current chart version
get_current_version() {
    if [[ ! -f "$GITEA_CHART_DIR/Chart.yaml" ]]; then
        error "Chart.yaml not found in $GITEA_CHART_DIR"
        exit 1
    fi
    yq eval '.version' "$GITEA_CHART_DIR/Chart.yaml"
}

# Get latest chart version from repository
get_latest_version() {
    helm repo add gitea-charts "$GITEA_CHART_REPO" --force-update > /dev/null 2>&1
    helm repo update > /dev/null 2>&1
    helm search repo gitea-charts/"$GITEA_CHART_NAME" --version=">=0.0.0" -o json | jq -r '.[0].version'
}

# Download and extract the latest chart
download_latest_chart() {
    local version="$1"

    log "Downloading Gitea chart version $version..."

    # Clean up any existing temp directory
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # Download and extract the chart
    helm pull gitea-charts/"$GITEA_CHART_NAME" --version="$version" --untar --untardir="$TEMP_DIR"

    if [[ ! -d "$TEMP_DIR/gitea" ]]; then
        error "Failed to download or extract chart"
        exit 1
    fi

    success "Chart downloaded to $TEMP_DIR/gitea"
}

# Preserve custom configurations
preserve_custom_configs() {
    local backup_dir="$GITEA_CHART_DIR.backup"
    local new_chart_dir="$TEMP_DIR/gitea"

    log "Preserving custom configurations..."

    # Create backup of current chart
    cp -r "$GITEA_CHART_DIR" "$backup_dir"

    # Files that might contain custom configurations
    local custom_files=(
        "values.yaml"
        ".helmignore"
    )

    # Check if any custom files exist and preserve them
    for file in "${custom_files[@]}"; do
        if [[ -f "$backup_dir/$file" ]] && [[ -f "$new_chart_dir/$file" ]]; then
            # Check if the file has been customized (different from upstream)
            if ! cmp -s "$backup_dir/$file" "$new_chart_dir/$file"; then
                warn "Custom configuration detected in $file"
                warn "You may need to manually merge changes after the update"
                # Keep a copy of the custom file for reference
                cp "$backup_dir/$file" "$new_chart_dir/$file.custom"
            fi
        elif [[ -f "$backup_dir/$file" ]]; then
            # File exists in backup but not in new chart - preserve it
            log "Preserving custom file: $file"
            cp "$backup_dir/$file" "$new_chart_dir/$file"
        fi
    done

    # Preserve any additional custom templates or files
    if [[ -d "$backup_dir/templates/custom" ]]; then
        log "Preserving custom templates directory"
        mkdir -p "$new_chart_dir/templates/custom"
        cp -r "$backup_dir/templates/custom/"* "$new_chart_dir/templates/custom/"
    fi
}

# Update the chart
update_chart() {
    local new_chart_dir="$TEMP_DIR/gitea"

    log "Updating Gitea chart..."

    # Remove current chart contents
    rm -rf "${GITEA_CHART_DIR:?}"/*

    # Copy new chart files
    cp -r "$new_chart_dir/"* "$GITEA_CHART_DIR/"

    success "Chart files updated"
}

# Update manifest version references
update_manifest_version() {
    local new_version="$1"
    local manifest_file="$PROJECT_ROOT/manifests/gitea.yaml"

    if [[ -f "$manifest_file" ]]; then
        log "Updating manifest chart version to $new_version..."

        # Update the chartVersion in the manifest file
        yq eval ".spec.chart.chartVersion = \"$new_version\"" -i "$manifest_file"

        success "Manifest version updated to $new_version"
    else
        warn "Manifest file not found at $manifest_file"
    fi
}

# Show summary of changes
show_changes() {
    local old_version="$1"
    local new_version="$2"

    echo
    echo "================================================================"
    echo "Gitea Helm Chart Update Summary"
    echo "================================================================"
    echo "Previous version: $old_version"
    echo "New version:      $new_version"
    echo

    # Show file changes
    log "Modified files:"
    if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
        git -C "$PROJECT_ROOT" status --porcelain gitea/ || true
    else
        echo "Git not available - showing directory contents:"
        ls -la "$GITEA_CHART_DIR"
    fi

    echo
    echo "================================================================"
    echo "Next steps:"
    echo "1. Review the changes carefully"
    echo "2. Check for any .custom files that need manual merging"
    echo "3. Test the updated chart in a development environment"
    echo "4. Commit and push the changes"
    echo "================================================================"
}

# Clean up temporary files
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    if [[ -d "$GITEA_CHART_DIR.backup" ]]; then
        rm -rf "$GITEA_CHART_DIR.backup"
    fi
}

# Main execution
main() {
    log "Starting Gitea Helm chart update process..."

    # Check dependencies
    check_dependencies

    # Get current and latest versions
    local current_version
    current_version=$(get_current_version)
    log "Current version: $current_version"

    local latest_version
    latest_version=$(get_latest_version)
    log "Latest version: $latest_version"

    # Check if update is needed
    if [[ "$current_version" == "$latest_version" ]]; then
        success "Chart is already up to date (version $current_version)"
        exit 0
    fi

    log "Update available: $current_version -> $latest_version"

    # Set up cleanup trap
    trap cleanup EXIT

    # Download latest chart
    download_latest_chart "$latest_version"

    # Preserve custom configurations
    preserve_custom_configs

    # Update the chart
    update_chart

    # Update manifest references
    update_manifest_version "$latest_version"

    # Show summary
    show_changes "$current_version" "$latest_version"

    success "Gitea Helm chart updated successfully!"
}

# Handle script arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        --help|-h)
            echo "Usage: $0 [--help]"
            echo
            echo "This script updates the Gitea Helm chart to the latest version"
            echo "while preserving any custom configurations."
            echo
            echo "Options:"
            echo "  --help, -h    Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
fi

# Run main function
main "$@"