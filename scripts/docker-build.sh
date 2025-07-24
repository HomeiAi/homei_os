#!/bin/bash

# Docker-based Homie OS Build Script
# This script builds Homie OS images using Docker for ARM64 Jetson targets

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT/docker"
BUILD_DIR="$PROJECT_ROOT/build"

# Default values
HOMIE_VERSION="${HOMIE_VERSION:-$(date +%Y%m%d_%H%M%S)}"
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

setup_build_environment() {
    print_info "Setting up build environment..."

    # Create build directories
    mkdir -p "$BUILD_DIR"/{certs,rootfs,bundle,logs}

    # Generate RAUC certificates if they don't exist
    if [[ ! -f "$BUILD_DIR/certs/rauc-key.pem" || ! -f "$BUILD_DIR/certs/rauc-cert.pem" ]]; then
        print_info "Generating RAUC certificates..."
        openssl req -x509 -newkey rsa:4096 -keyout "$BUILD_DIR/certs/rauc-key.pem" \
            -out "$BUILD_DIR/certs/rauc-cert.pem" -days 365 -nodes \
            -subj "/C=US/ST=CA/L=San Francisco/O=Homie/CN=Homie OS Update"
        print_success "RAUC certificates generated"
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
        rm -rf "$BUILD_DIR"/{rootfs,bundle}/*
        docker system prune -f
        print_success "Build artifacts cleaned"
    fi
}

build_image() {
    print_info "Building Homie OS image for ARM64/Jetson..."

    cd "$DOCKER_DIR"

    # Build the image using Docker Compose
    if ! docker compose build --no-cache jetson-builder; then
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

    cd "$DOCKER_DIR"

    # Create a container from the image
    local container_id
    container_id=$(docker create --platform linux/arm64 "homie-os:jetson-$HOMIE_VERSION")

    # Export the container filesystem
    docker export "$container_id" | tar -C "$BUILD_DIR/rootfs" -xf -

    # Clean up the container
    docker rm "$container_id"

    # Create ext4 filesystem image
    print_info "Creating ext4 filesystem..."
    local rootfs_size="2G"
    local rootfs_img="$BUILD_DIR/rootfs.ext4"

    # Create empty image file
    dd if=/dev/zero of="$rootfs_img" bs=1M count=2048

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

    # Create manifest
    cat > "$BUILD_DIR/bundle/manifest.raucm" << EOF
[update]
compatible=homie-jetson-orin-nano
version=$HOMIE_VERSION

[image.rootfs]
filename=rootfs.ext4
size=$(stat -c%s "$BUILD_DIR/rootfs.ext4")
sha256=$(sha256sum "$BUILD_DIR/rootfs.ext4" | cut -d' ' -f1)

[hooks]
filename=hook.sh
EOF

    # Copy rootfs to bundle directory
    cp "$BUILD_DIR/rootfs.ext4" "$BUILD_DIR/bundle/"

    # Create simple hook script
    cat > "$BUILD_DIR/bundle/hook.sh" << 'EOF'
#!/bin/bash
case "$1" in
    slot-post-install)
        echo "Post-install hook executed"
        ;;
esac
EOF
    chmod +x "$BUILD_DIR/bundle/hook.sh"

    # Create the bundle
    local bundle_name="homie-os-jetson-$HOMIE_VERSION.raucb"
    rauc bundle "$BUILD_DIR/bundle" "$BUILD_DIR/$bundle_name" \
        --cert="$BUILD_DIR/certs/rauc-cert.pem" \
        --key="$BUILD_DIR/certs/rauc-key.pem"

    print_success "RAUC bundle created: $BUILD_DIR/$bundle_name"
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

    local report_file="$BUILD_DIR/build-report-$HOMIE_VERSION.json"
    cat > "$report_file" << EOF
{
  "version": "$HOMIE_VERSION",
  "build_date": "$BUILD_DATE",
  "branch": "$HOMIE_BRANCH",
  "target": "jetson-orin-nano",
  "architecture": "arm64",
  "base_image": "nvcr.io/nvidia/l4t-base:r35.4.1",
  "artifacts": {
    "image": "homie-os:jetson-$HOMIE_VERSION",
    "rootfs": "rootfs.ext4",
    "bundle": "homie-os-jetson-$HOMIE_VERSION.raucb"
  },
  "sizes": {
    "rootfs_mb": $(($(stat -c%s "$BUILD_DIR/rootfs.ext4" 2>/dev/null || echo 0) / 1024 / 1024)),
    "bundle_mb": $(($(stat -c%s "$BUILD_DIR/homie-os-jetson-$HOMIE_VERSION.raucb" 2>/dev/null || echo 0) / 1024 / 1024))
  }
}
EOF

    print_success "Build report saved to $report_file"
}

main() {
    print_info "Starting Homie OS Docker build process..."
    print_info "Version: $HOMIE_VERSION"
    print_info "Branch: $HOMIE_BRANCH"
    print_info "Target: ARM64/Jetson Orin Nano"

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
    
    # List created artifacts
    echo
    print_info "Created artifacts:"
    ls -lh "$BUILD_DIR"/*.{ext4,raucb,json} 2>/dev/null || true
}

# Run main function with all arguments
main "$@"
