#!/bin/bash

# Docker-based Homie OS Build Script
# This script builds Homie OS images using Docker for ARM64 Jetson targets

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT/docker"
BUILD_DIR="$PROJECT_ROOT/build"

# Load configuration variables
source "$SCRIPT_DIR/load-config.sh" load 2>/dev/null || {
    echo "WARNING: Could not load configuration, using defaults"
}

# Default values with fallback to timestamp
DEFAULT_VERSION="$(date +%Y%m%d_%H%M%S)"
HOMIE_VERSION="${HOMIE_VERSION:-${VERSION:-$DEFAULT_VERSION}}"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOMIE_BRANCH="${HOMIE_BRANCH:-main}"
PUSH_IMAGE="${PUSH_IMAGE:-false}"
CREATE_BUNDLE="${CREATE_BUNDLE:-true}"
REGISTRY="${REGISTRY:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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
Usage: $0 [OPTIONS]

Build Homie OS for NVIDIA Jetson using Docker

OPTIONS:
    -v, --version VERSION    Set Homie OS version (default: timestamp)
    -b, --branch BRANCH      Git branch to build (default: main)
    -p, --push              Push image to registry
    -r, --registry REGISTRY Registry to push to
    --no-bundle             Skip bundle creation
    --clean                 Clean build artifacts before building
    -h, --help              Show this help message

ENVIRONMENT VARIABLES:
    HOMIE_VERSION           Version to build
    HOMIE_BRANCH           Branch to checkout
    REGISTRY               Container registry
    PUSH_IMAGE             Whether to push (true/false)
    CREATE_BUNDLE          Whether to create bundle (true/false)

EXAMPLES:
    # Basic build
    $0

    # Build specific version
    $0 --version v1.0.0

    # Build and push to registry
    $0 --version v1.0.0 --push --registry myregistry.com/homie

    # Build without creating bundle
    $0 --no-bundle

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                HOMIE_VERSION="$2"
                shift 2
                ;;
            -b|--branch)
                HOMIE_BRANCH="$2"
                shift 2
                ;;
            -p|--push)
                PUSH_IMAGE="true"
                shift
                ;;
            -r|--registry)
                REGISTRY="$2"
                shift 2
                ;;
            --no-bundle)
                CREATE_BUNDLE="false"
                shift
                ;;
            --clean)
                CLEAN_BUILD="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi

    # Check Docker Buildx
    if ! docker buildx version &> /dev/null; then
        print_error "Docker Buildx is not available"
        exit 1
    fi

    # Set up buildx builder for multi-platform builds
    print_info "Setting up Docker Buildx for multi-platform builds..."
    if ! docker buildx inspect multiarch &> /dev/null; then
        print_info "Creating multiarch builder..."
        docker buildx create --name multiarch --driver docker-container --platform linux/arm64,linux/amd64 --use
    else
        print_info "Using existing multiarch builder..."
        docker buildx use multiarch
    fi

    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not available"
        exit 1
    fi

    # Check if we can run ARM64 containers
    if ! docker run --rm --platform linux/arm64 alpine:latest echo "ARM64 support OK" &> /dev/null; then
        print_warning "ARM64 emulation may not be available. Installing qemu-user-static..."
        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    fi

    print_success "Prerequisites check passed"
}

generate_dockerfile_inline() {
    # Inline Dockerfile generation as fallback
    if [[ -f "$DOCKERFILE_TEMPLATE" ]]; then
        print_info "Generating Dockerfile from template using inline method..."
        
        # Use base image from configuration, with fallback to NVIDIA default
        local base_image="${L4T_BASE_IMAGE:-nvcr.io/nvidia/l4t-base:r36.2.0}"
        
        # Check if we can access the configured base image
        if ! docker manifest inspect "$base_image" &>/dev/null; then
            print_warning "Cannot access $base_image, falling back to Ubuntu ARM64"
            base_image="ubuntu:22.04"
            print_info "Updated base image for this build: $base_image"
        fi
        
        sed \
            -e "s|{{L4T_VERSION}}|${L4T_VERSION:-r36.2.0}|g" \
            -e "s|{{L4T_BASE_IMAGE}}|${base_image}|g" \
            -e "s|{{JETPACK_VERSION}}|${JETPACK_VERSION:-6.0}|g" \
            -e "s|{{CUDA_VERSION}}|${CUDA_VERSION:-12.2}|g" \
            -e "s|{{TENSORRT_VERSION}}|${TENSORRT_VERSION:-10.0}|g" \
            -e "s|{{DEBIAN_FRONTEND}}|${DEBIAN_FRONTEND:-noninteractive}|g" \
            "$DOCKERFILE_TEMPLATE" > "$DOCKERFILE_OUTPUT"
        print_success "Generated Dockerfile inline: $DOCKERFILE_OUTPUT"
        print_info "Using base image: $base_image"
    else
        print_error "No Dockerfile template found at $DOCKERFILE_TEMPLATE"
        return 1
    fi
}

setup_build_environment() {
    print_info "Setting up build environment..."
    
    # Debug: Show current working directory and BUILD_DIR
    print_info "Current working directory: $(pwd)"
    print_info "PROJECT_ROOT: $PROJECT_ROOT"
    print_info "BUILD_DIR: $BUILD_DIR"
    
    # Ensure PROJECT_ROOT exists and we can write to it
    if [[ ! -d "$PROJECT_ROOT" ]]; then
        print_error "Project root directory does not exist: $PROJECT_ROOT"
        exit 1
    fi

    # Create build directories
    mkdir -p "$BUILD_DIR"/{certs,rootfs,bundle,logs}
    
    # Ensure certificate directory exists (critical for GitHub Actions)
    print_info "Ensuring certificate directory exists: $BUILD_DIR/certs"
    mkdir -p "$BUILD_DIR/certs"

    # Generate Dockerfile from template with current configuration
    DOCKERFILE_TEMPLATE="$DOCKER_DIR/Dockerfile.jetson-builder.template"
    DOCKERFILE_OUTPUT="$DOCKER_DIR/Dockerfile.jetson-builder"
    
    if [[ -f "$SCRIPT_DIR/generate-dockerfile.sh" ]]; then
        print_info "Generating Dockerfile from template..."
        chmod +x "$SCRIPT_DIR/generate-dockerfile.sh"
        if ! "$SCRIPT_DIR/generate-dockerfile.sh"; then
            print_warning "Dockerfile generation script failed, generating inline..."
            generate_dockerfile_inline
        fi
    elif [[ -f "$DOCKERFILE_TEMPLATE" ]]; then
        print_info "Generating Dockerfile inline from template..."
        generate_dockerfile_inline
    else
        print_warning "No Dockerfile template found, using existing Dockerfile"
    fi

    # Generate RAUC certificates if they don't exist
    print_info "Checking RAUC certificates..."
    
    # Always ensure certs directory exists first
    mkdir -p "$BUILD_DIR/certs"
    print_info "Certificate directory: $BUILD_DIR/certs"
    ls -la "$BUILD_DIR/certs/" || print_info "Certificate directory is empty"
    
    if [[ ! -f "$BUILD_DIR/certs/rauc-key.pem" || ! -f "$BUILD_DIR/certs/rauc-cert.pem" ]]; then
        print_info "Generating RAUC certificates..."
        
        # Generate certificates with error checking
        if ! openssl req -x509 -newkey rsa:4096 -keyout "$BUILD_DIR/certs/rauc-key.pem" \
            -out "$BUILD_DIR/certs/rauc-cert.pem" -days 365 -nodes \
            -subj "/C=US/ST=CA/L=San Francisco/O=Homie/CN=Homie OS Update"; then
            print_error "Failed to generate RAUC certificates"
            exit 1
        fi
        
        # Verify certificates were created
        if [[ ! -f "$BUILD_DIR/certs/rauc-key.pem" || ! -f "$BUILD_DIR/certs/rauc-cert.pem" ]]; then
            print_error "Certificate generation failed - files not found"
            exit 1
        fi
        
        print_success "RAUC certificates generated"
        print_info "Certificate files:"
        ls -la "$BUILD_DIR/certs/"
    else
        print_info "Using existing RAUC certificates"
        ls -la "$BUILD_DIR/certs/"
    fi

    # Create .env file for Docker Compose
    cat > "$DOCKER_DIR/.env" << EOF
HOMIE_VERSION=$HOMIE_VERSION
BUILD_DATE=$BUILD_DATE
HOMIE_BRANCH=$HOMIE_BRANCH
EOF

    print_success "Build environment ready"
}

clean_build_artifacts() {
    if [[ "${CLEAN_BUILD:-false}" == "true" ]]; then
        print_info "Cleaning build artifacts..."
        # Clean contents but preserve directory structure
        rm -rf "$BUILD_DIR"/rootfs/* "$BUILD_DIR"/bundle/* 2>/dev/null || true
        # Ensure directories exist after cleaning
        mkdir -p "$BUILD_DIR"/{certs,rootfs,bundle,logs}
        docker system prune -f
        print_success "Build artifacts cleaned"
    fi
}

build_image() {
    print_info "Building Homie OS image for ARM64/Jetson..."

    cd "$DOCKER_DIR"

    # Use CI-specific compose file if DOCKERFILE_PATH is set (GitHub Actions)
    local compose_file="docker-compose.yml"
    if [[ -n "${DOCKERFILE_PATH:-}" ]]; then
        compose_file="docker-compose.ci.yml"
        print_info "Using CI-specific compose file: $compose_file"
    fi

    # Build the image using Docker Compose
    if ! docker compose -f "$compose_file" build --no-cache jetson-builder; then
        print_error "Failed to build Homie OS image"
        exit 1
    fi

    # Tag the image with version
    local image_name="homie-os:jetson-$HOMIE_VERSION"
    if [[ -n "$REGISTRY" ]]; then
        docker tag "$image_name" "$REGISTRY/$image_name"
    fi

    print_success "Image built successfully: $image_name"
}

extract_rootfs() {
    print_info "Extracting rootfs from container..."

    # Ensure build directory structure exists
    mkdir -p "$BUILD_DIR/rootfs"

    # Create a container from the image
    local container_id
    container_id=$(docker create --platform linux/arm64 "homie-os:jetson-$HOMIE_VERSION")

    # Export the container filesystem
    docker export "$container_id" | tar -C "$BUILD_DIR/rootfs" -xf -

    # Clean up the container
    docker rm "$container_id"

    # Create ext4 filesystem image
    print_info "Creating ext4 filesystem..."
    
    # Calculate required size dynamically
    local rootfs_size_bytes=$(du -sb "$BUILD_DIR/rootfs" | cut -f1)
    local rootfs_size_mb=$((rootfs_size_bytes / 1024 / 1024))
    local filesystem_size_mb=$((rootfs_size_mb + rootfs_size_mb / 5 + 512)) # Add 20% + 512MB overhead
    
    print_info "Rootfs size: ${rootfs_size_mb}MB, creating filesystem: ${filesystem_size_mb}MB"
    
    local rootfs_img="$BUILD_DIR/rootfs.ext4"

    # Remove existing image if it exists
    rm -f "$rootfs_img"

    # Create empty image file
    dd if=/dev/zero of="$rootfs_img" bs=1M count="$filesystem_size_mb"

    # Format as ext4
    mkfs.ext4 -F "$rootfs_img"

    # Mount and copy files
    local mount_point="/tmp/homie-rootfs-$$"
    mkdir -p "$mount_point"
    sudo mount -o loop "$rootfs_img" "$mount_point"

    # Copy rootfs contents
    sudo cp -a "$BUILD_DIR/rootfs/"* "$mount_point/"

    # Unmount
    sudo umount "$mount_point"
    rmdir "$mount_point"

    print_success "Rootfs extracted to $rootfs_img"
}

create_rauc_bundle() {
    if [[ "$CREATE_BUNDLE" != "true" ]]; then
        print_info "Skipping bundle creation"
        return 0
    fi

    print_info "Creating RAUC bundle..."

    # Ensure we're working with absolute paths and directories exist
    local abs_build_dir="$(realpath "$BUILD_DIR")"
    print_info "Absolute BUILD_DIR: $abs_build_dir"
    
    # Ensure bundle and certificate directories exist
    mkdir -p "$abs_build_dir/bundle"
    mkdir -p "$abs_build_dir/certs"

    # Create manifest
    cat > "$abs_build_dir/bundle/manifest.raucm" << EOF
[update]
compatible=${RAUC_COMPATIBLE:-homie-jetson-orin-nano}
version=$HOMIE_VERSION
description=Homie OS update bundle for ${TARGET_PLATFORM:-Jetson Orin Nano}

[bundle]
format=${BUNDLE_FORMAT:-plain}

[image.rootfs]
filename=rootfs.ext4
size=$(stat -c%s "$abs_build_dir/rootfs.ext4")
sha256=$(sha256sum "$abs_build_dir/rootfs.ext4" | cut -d' ' -f1)

[hooks]
filename=hook.sh
EOF

    # Copy rootfs to bundle directory
    cp "$abs_build_dir/rootfs.ext4" "$abs_build_dir/bundle/"

    # Create simple hook script
    cat > "$abs_build_dir/bundle/hook.sh" << 'EOF'
#!/bin/bash
case "$1" in
    slot-post-install)
        echo "Post-install hook executed"
        ;;
esac
EOF
    chmod +x "$abs_build_dir/bundle/hook.sh"

    # Create the bundle
    local bundle_name="homie-os-jetson-$HOMIE_VERSION.raucb"
    
    # Debug: Show current directory and certificate paths
    print_info "Current working directory: $(pwd)"
    print_info "BUILD_DIR: $BUILD_DIR"
    print_info "Absolute BUILD_DIR: $abs_build_dir"
    print_info "Checking certificate files..."
    ls -la "$abs_build_dir/certs/" || print_error "Certs directory not found"
    
    # Verify certificate files exist - if not, generate them
    if [[ ! -f "$abs_build_dir/certs/rauc-cert.pem" || ! -f "$abs_build_dir/certs/rauc-key.pem" ]]; then
        print_warning "Certificate files not found, generating them now..."
        
        # Generate certificates
        if ! openssl req -x509 -newkey rsa:4096 -keyout "$abs_build_dir/certs/rauc-key.pem" \
            -out "$abs_build_dir/certs/rauc-cert.pem" -days 365 -nodes \
            -subj "/C=US/ST=CA/L=San Francisco/O=Homie/CN=Homie OS Update"; then
            print_error "Failed to generate RAUC certificates"
            exit 1
        fi
        
        print_success "RAUC certificates generated in bundle creation"
        ls -la "$abs_build_dir/certs/"
    fi
    
    # Verify certificate files exist
    if [[ ! -f "$abs_build_dir/certs/rauc-cert.pem" ]]; then
        print_error "Certificate file not found: $abs_build_dir/certs/rauc-cert.pem"
        exit 1
    fi
    
    if [[ ! -f "$abs_build_dir/certs/rauc-key.pem" ]]; then
        print_error "Key file not found: $abs_build_dir/certs/rauc-key.pem"
        exit 1
    fi
    
    # Create the bundle with absolute paths
    print_info "Creating RAUC bundle with certificates..."
    rauc bundle "$abs_build_dir/bundle" "$abs_build_dir/$bundle_name" \
        --cert="$abs_build_dir/certs/rauc-cert.pem" \
        --key="$abs_build_dir/certs/rauc-key.pem"

    print_success "RAUC bundle created: $abs_build_dir/$bundle_name"
}

push_image() {
    if [[ "$PUSH_IMAGE" != "true" || -z "$REGISTRY" ]]; then
        print_info "Skipping image push"
        return 0
    fi

    print_info "Pushing image to registry..."

    local image_name="$REGISTRY/homie-os:jetson-$HOMIE_VERSION"
    docker push "$image_name"

    # Also push as latest if this is a tagged version
    if [[ "$HOMIE_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        docker tag "$image_name" "$REGISTRY/homie-os:jetson-latest"
        docker push "$REGISTRY/homie-os:jetson-latest"
    fi

    print_success "Image pushed to registry"
}

generate_build_report() {
    print_info "Generating build report..."

    local abs_build_dir="$(realpath "$BUILD_DIR")"
    local report_file="$abs_build_dir/build-report-$HOMIE_VERSION.json"
    cat > "$report_file" << EOF
{
  "version": "$HOMIE_VERSION",
  "build_date": "$BUILD_DATE",
  "branch": "$HOMIE_BRANCH",
  "target": "${TARGET_PLATFORM:-jetson-orin-nano}",
  "architecture": "${TARGET_ARCHITECTURE:-arm64}",
  "base_image": "${L4T_BASE_IMAGE:-nvcr.io/nvidia/l4t-base:r36.2.0}",
  "jetpack_version": "${JETPACK_VERSION:-6.0}",
  "jetson_linux": "${L4T_VERSION:-r36.2.0}",
  "artifacts": {
    "image": "homie-os:jetson-$HOMIE_VERSION",
    "rootfs": "rootfs.ext4",
    "bundle": "homie-os-jetson-$HOMIE_VERSION.raucb"
  },
  "sizes": {
    "rootfs_mb": $(($(stat -c%s "$abs_build_dir/rootfs.ext4" 2>/dev/null || echo 0) / 1024 / 1024)),
    "bundle_mb": $(($(stat -c%s "$abs_build_dir/homie-os-jetson-$HOMIE_VERSION.raucb" 2>/dev/null || echo 0) / 1024 / 1024))
  }
}
EOF

    print_success "Build report saved to $report_file"
}

main() {
    print_info "Starting Homie OS Docker build process..."
    print_info "Version: $HOMIE_VERSION"
    print_info "Branch: $HOMIE_BRANCH"
    print_info "Target: ${TARGET_ARCHITECTURE:-ARM64}/${TARGET_PLATFORM:-Jetson Orin Nano}"
    print_info "Base Image: ${L4T_BASE_IMAGE:-nvcr.io/nvidia/l4t-base:r36.2.0}"

    parse_args "$@"
    check_prerequisites
    setup_build_environment
    clean_build_artifacts
    build_image
    extract_rootfs
    create_rauc_bundle
    push_image
    generate_build_report

    print_success "Build process completed successfully!"
    print_info "Artifacts location: $BUILD_DIR"
    
    # List created artifacts using absolute path
    echo
    print_info "Created artifacts:"
    local abs_build_dir="$(realpath "$BUILD_DIR")"
    ls -lh "$abs_build_dir"/*.{ext4,raucb,json} 2>/dev/null || true
}

# Run main function with all arguments
main "$@"
