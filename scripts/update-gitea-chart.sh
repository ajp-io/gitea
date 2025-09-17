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

# Get current SDK version from Chart.yaml
get_current_sdk_version() {
    if [[ ! -f "$GITEA_CHART_DIR/Chart.yaml" ]]; then
        echo ""
        return
    fi
    yq eval '.dependencies[] | select(.name == "replicated") | .version' "$GITEA_CHART_DIR/Chart.yaml" 2>/dev/null || echo ""
}

# Get latest SDK version from GitHub releases
get_latest_sdk_version() {
    local api_url="https://api.github.com/repos/replicatedhq/replicated-sdk/releases/latest"
    local version

    if command -v curl &> /dev/null; then
        version=$(curl -s "$api_url" | jq -r '.tag_name' 2>/dev/null)
    elif command -v wget &> /dev/null; then
        version=$(wget -qO- "$api_url" | jq -r '.tag_name' 2>/dev/null)
    else
        error "Neither curl nor wget is available to fetch SDK version"
        return 1
    fi

    # Remove 'v' prefix if present
    version=${version#v}

    if [[ "$version" == "null" || -z "$version" ]]; then
        error "Failed to fetch latest SDK version"
        return 1
    fi

    echo "$version"
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

# Inject Replicated SDK dependency into Chart.yaml
inject_sdk_dependency() {
    local new_chart_dir="$TEMP_DIR/gitea"
    local sdk_version="$1"

    if [[ -z "$sdk_version" ]]; then
        error "SDK version not provided to inject_sdk_dependency"
        return 1
    fi

    log "Injecting Replicated SDK dependency (version $sdk_version)..."

    # Check if the dependency already exists
    local existing_sdk
    existing_sdk=$(yq eval '.dependencies[] | select(.name == "replicated") | .version' "$new_chart_dir/Chart.yaml" 2>/dev/null || echo "")

    if [[ -n "$existing_sdk" ]]; then
        # Update existing dependency
        log "Updating existing SDK dependency from $existing_sdk to $sdk_version"
        yq eval '.dependencies[] |= (select(.name == "replicated").version = "'$sdk_version'")' -i "$new_chart_dir/Chart.yaml"
    else
        # Add new dependency
        log "Adding new SDK dependency with version $sdk_version"
        yq eval '.dependencies += [{"name": "replicated", "repository": "oci://registry.replicated.com/library", "version": "'$sdk_version'"}]' -i "$new_chart_dir/Chart.yaml"
    fi

    # Verify the dependency was added/updated correctly
    local injected_version
    injected_version=$(yq eval '.dependencies[] | select(.name == "replicated") | .version' "$new_chart_dir/Chart.yaml" 2>/dev/null)

    if [[ "$injected_version" == "$sdk_version" ]]; then
        success "SDK dependency injected successfully (version $sdk_version)"
    else
        error "Failed to inject SDK dependency. Expected $sdk_version, got $injected_version"
        return 1
    fi
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
    local old_gitea_version="$1"
    local new_gitea_version="$2"
    local old_sdk_version="$3"
    local new_sdk_version="$4"

    echo
    echo "================================================================"
    echo "Gitea Helm Chart Update Summary"
    echo "================================================================"
    echo "Gitea Chart:"
    echo "  Previous version: $old_gitea_version"
    echo "  New version:      $new_gitea_version"
    echo
    echo "Replicated SDK:"
    echo "  Previous version: ${old_sdk_version:-"not present"}"
    echo "  New version:      $new_sdk_version"
    echo

    # Show file changes
    log "Modified files:"
    if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
        git -C "$PROJECT_ROOT" status --porcelain gitea/ manifests/ || true
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

    # Get current and latest Gitea versions
    local current_gitea_version
    current_gitea_version=$(get_current_version)
    log "Current Gitea version: $current_gitea_version"

    local latest_gitea_version
    latest_gitea_version=$(get_latest_version)
    log "Latest Gitea version: $latest_gitea_version"

    # Get current and latest SDK versions
    local current_sdk_version
    current_sdk_version=$(get_current_sdk_version)
    log "Current SDK version: ${current_sdk_version:-"not present"}"

    local latest_sdk_version
    latest_sdk_version=$(get_latest_sdk_version)
    if [[ $? -eq 0 ]]; then
        log "Latest SDK version: $latest_sdk_version"
    else
        error "Failed to fetch latest SDK version"
        exit 1
    fi

    # Check if any update is needed
    local gitea_needs_update=false
    local sdk_needs_update=false

    if [[ "$current_gitea_version" != "$latest_gitea_version" ]]; then
        gitea_needs_update=true
        log "Gitea update available: $current_gitea_version -> $latest_gitea_version"
    fi

    if [[ "$current_sdk_version" != "$latest_sdk_version" ]]; then
        sdk_needs_update=true
        log "SDK update available: ${current_sdk_version:-"not present"} -> $latest_sdk_version"
    fi

    if [[ "$gitea_needs_update" == false && "$sdk_needs_update" == false ]]; then
        success "Both Gitea chart and SDK are up to date"
        success "Gitea: $current_gitea_version, SDK: $current_sdk_version"
        exit 0
    fi

    # Set up cleanup trap
    trap cleanup EXIT

    # Download latest chart (always download to get fresh base)
    download_latest_chart "$latest_gitea_version"

    # Always inject SDK dependency with latest version
    inject_sdk_dependency "$latest_sdk_version"

    # Preserve custom configurations
    preserve_custom_configs

    # Update the chart
    update_chart

    # Update manifest references
    update_manifest_version "$latest_gitea_version"

    # Show summary
    show_changes "$current_gitea_version" "$latest_gitea_version" "$current_sdk_version" "$latest_sdk_version"

    success "Gitea Helm chart updated successfully!"
    if [[ "$gitea_needs_update" == true && "$sdk_needs_update" == true ]]; then
        success "Updated both Gitea ($current_gitea_version -> $latest_gitea_version) and SDK ($current_sdk_version -> $latest_sdk_version)"
    elif [[ "$gitea_needs_update" == true ]]; then
        success "Updated Gitea ($current_gitea_version -> $latest_gitea_version) and ensured SDK is latest ($latest_sdk_version)"
    else
        success "Updated SDK ($current_sdk_version -> $latest_sdk_version)"
    fi
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