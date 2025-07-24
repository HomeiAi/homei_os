#!/bin/bash
# Variable Configuration Helper for Homie OS
# This script helps identify and update configuration variables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Homie OS Configuration Variable Helper

COMMANDS:
    list                List all current configuration variables
    check               Check for outdated variables
    update-l4t VERSION  Update L4T base image version
    update-version TYPE Update project version
    validate            Validate configuration consistency
    help                Show this help message

EXAMPLES:
    $0 list                     # Show all variables
    $0 check                    # Check for updates needed
    $0 update-l4t r36.3.0      # Update to L4T r36.3.0
    $0 update-version beta      # Create beta version
    $0 validate                 # Validate all configs

EOF
}

list_variables() {
    print_header "Current Configuration Variables"
    
    echo -e "${YELLOW}Version Information:${NC}"
    if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
        echo "  VERSION: $(cat "$PROJECT_ROOT/VERSION")"
    else
        echo "  VERSION: Not found"
    fi
    
    echo -e "${YELLOW}Docker Configuration:${NC}"
    if [[ -f "$PROJECT_ROOT/docker/Dockerfile.jetson-builder" ]]; then
        FROM_LINE=$(grep "^FROM" "$PROJECT_ROOT/docker/Dockerfile.jetson-builder" | head -1)
        echo "  Base Image: ${FROM_LINE#FROM }"
        
        CUDA_VERSION=$(grep "ENV CUDA_VERSION" "$PROJECT_ROOT/docker/Dockerfile.jetson-builder" | cut -d'=' -f2 || echo "Not found")
        echo "  CUDA Version: $CUDA_VERSION"
        
        TRT_VERSION=$(grep "ENV TRT_VERSION" "$PROJECT_ROOT/docker/Dockerfile.jetson-builder" | cut -d'=' -f2 || echo "Not found")
        echo "  TensorRT Version: $TRT_VERSION"
        
        JETPACK_VERSION=$(grep "ENV JETPACK_VERSION" "$PROJECT_ROOT/docker/Dockerfile.jetson-builder" | cut -d'=' -f2 || echo "Not found")
        echo "  JetPack Version: $JETPACK_VERSION"
    else
        print_error "Dockerfile not found"
    fi
    
    echo -e "${YELLOW}RAUC Configuration:${NC}"
    echo "  Bundle Pattern: homie-os-jetson-{version}.raucb"
    echo "  Compatible: jetson-orin-nano"
    echo "  Format: plain"
    echo "  Verity: true"
    
    echo -e "${YELLOW}CI/CD Configuration:${NC}"
    if [[ -f "$PROJECT_ROOT/.github/workflows/build-bundle.yml" ]]; then
        REGISTRY=$(grep "REGISTRY:" "$PROJECT_ROOT/.github/workflows/build-bundle.yml" | head -1 | cut -d':' -f2 | tr -d ' ')
        echo "  Registry: $REGISTRY"
        echo "  Platforms: linux/arm64"
        echo "  Retention: 30 days"
    else
        print_warning "CI/CD workflow not found"
    fi
}

check_updates() {
    print_header "Checking for Outdated Variables"
    
    print_info "Checking NVIDIA L4T base image..."
    
    # Check current L4T version
    if [[ -f "$PROJECT_ROOT/docker/Dockerfile.jetson-builder" ]]; then
        CURRENT_L4T=$(grep "^FROM.*l4t-base:" "$PROJECT_ROOT/docker/Dockerfile.jetson-builder" | grep -o "r[0-9][0-9]\.[0-9]" || echo "unknown")
        echo "  Current L4T: $CURRENT_L4T"
        
        # Suggest checking for newer versions
        print_info "To check for newer L4T versions:"
        echo "  curl -s https://nvcr.io/v2/nvidia/l4t-base/tags/list | jq '.tags[]' | sort"
        echo ""
    fi
    
    print_info "Checking project version..."
    if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
        CURRENT_VERSION=$(cat "$PROJECT_ROOT/VERSION")
        echo "  Current Version: $CURRENT_VERSION"
        
        if [[ $CURRENT_VERSION == *"alpha"* ]]; then
            print_warning "Using alpha version - consider beta or release for production"
        fi
    fi
    
    print_info "Configuration appears current. Check NVIDIA documentation for latest releases."
}

update_l4t() {
    local NEW_VERSION="$1"
    if [[ -z "$NEW_VERSION" ]]; then
        print_error "L4T version required. Example: r36.3.0"
        return 1
    fi
    
    print_header "Updating L4T Base Image to $NEW_VERSION"
    
    local DOCKERFILE="$PROJECT_ROOT/docker/Dockerfile.jetson-builder"
    if [[ ! -f "$DOCKERFILE" ]]; then
        print_error "Dockerfile not found: $DOCKERFILE"
        return 1
    fi
    
    # Backup original
    cp "$DOCKERFILE" "$DOCKERFILE.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Created backup of Dockerfile"
    
    # Update FROM line
    sed -i "s|FROM nvcr.io/nvidia/l4t-base:r[0-9][0-9]\.[0-9]|FROM nvcr.io/nvidia/l4t-base:$NEW_VERSION|g" "$DOCKERFILE"
    
    # Update build info lines
    sed -i "s|jetson_linux=r[0-9][0-9]\.[0-9]|jetson_linux=$NEW_VERSION|g" "$DOCKERFILE"
    sed -i "s|base_image=nvcr.io/nvidia/l4t-base:r[0-9][0-9]\.[0-9]|base_image=nvcr.io/nvidia/l4t-base:$NEW_VERSION|g" "$DOCKERFILE"
    
    print_success "Updated L4T base image to $NEW_VERSION"
    print_warning "Remember to update CUDA, TensorRT, and JetPack versions if needed"
    print_info "Test the build with: ./scripts/docker-build.sh --version test-l4t-update"
}

update_version() {
    local RELEASE_TYPE="$1"
    if [[ -z "$RELEASE_TYPE" ]]; then
        print_error "Release type required: alpha, beta, rc, release"
        return 1
    fi
    
    print_header "Updating Project Version"
    
    if [[ -f "$PROJECT_ROOT/scripts/manage-version.sh" ]]; then
        print_info "Using version management script..."
        cd "$PROJECT_ROOT"
        ./scripts/manage-version.sh --type "$RELEASE_TYPE" --dry-run
        
        echo ""
        read -p "Proceed with version update? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ./scripts/manage-version.sh --type "$RELEASE_TYPE"
            print_success "Version updated successfully"
        else
            print_info "Version update cancelled"
        fi
    else
        print_error "Version management script not found"
        return 1
    fi
}

validate_config() {
    print_header "Validating Configuration"
    
    local errors=0
    
    # Check VERSION file
    if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
        print_success "VERSION file exists"
    else
        print_error "VERSION file missing"
        ((errors++))
    fi
    
    # Check Dockerfile
    if [[ -f "$PROJECT_ROOT/docker/Dockerfile.jetson-builder" ]]; then
        print_success "Dockerfile exists"
        
        # Check FROM line
        if grep -q "^FROM nvcr.io/nvidia/l4t-base:" "$PROJECT_ROOT/docker/Dockerfile.jetson-builder"; then
            print_success "Valid L4T base image reference"
        else
            print_error "Invalid or missing L4T base image"
            ((errors++))
        fi
        
        # Check required ENV variables
        for var in CUDA_VERSION TRT_VERSION JETPACK_VERSION; do
            if grep -q "ENV $var" "$PROJECT_ROOT/docker/Dockerfile.jetson-builder"; then
                print_success "$var is defined"
            else
                print_warning "$var is not defined"
            fi
        done
    else
        print_error "Dockerfile missing"
        ((errors++))
    fi
    
    # Check CI/CD workflow
    if [[ -f "$PROJECT_ROOT/.github/workflows/build-bundle.yml" ]]; then
        print_success "CI/CD workflow exists"
    else
        print_warning "CI/CD workflow missing"
    fi
    
    # Check scripts
    for script in docker-build.sh create-docker-bundle.sh manage-version.sh; do
        if [[ -f "$PROJECT_ROOT/scripts/$script" ]]; then
            print_success "Script $script exists"
        else
            print_error "Script $script missing"
            ((errors++))
        fi
    done
    
    echo ""
    if [[ $errors -eq 0 ]]; then
        print_success "Configuration validation passed"
        return 0
    else
        print_error "Configuration validation failed with $errors errors"
        return 1
    fi
}

# Parse command line arguments
case "${1:-help}" in
    list)
        list_variables
        ;;
    check)
        check_updates
        ;;
    update-l4t)
        update_l4t "$2"
        ;;
    update-version)
        update_version "$2"
        ;;
    validate)
        validate_config
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        usage
        exit 1
        ;;
esac
