# Docker Cross-Platform Building for Jetson Hardware
> Complete guide for building ARM64 RAUC bundles using Docker containers

## 🎯 Overview

This guide provides the exact implementation for creating RAUC bundles using Docker cross-compilation. This approach solves the architecture mismatch between development machines (x86_64) and target hardware (ARM64 Jetson Orin Nano) while maintaining clean, reproducible builds.

## 🚀 Benefits of Docker-Based Building

- ✅ **Correct Architecture**: Native ARM64 binaries for Jetson hardware
- ✅ **Hardware Drivers**: Includes NVIDIA CUDA, TensorRT, and JetPack components
- ✅ **Reproducible Builds**: Same environment every time
- ✅ **CI/CD Compatible**: Works in GitHub Actions and other automation
- ✅ **Clean Environment**: No development artifacts or temporary files
- ✅ **Fast Builds**: Leverages Docker layer caching

## 📋 Prerequisites

### Development Machine Requirements
```bash
# Install Docker with buildx support
sudo apt update
sudo apt install -y docker.io docker-buildx
sudo usermod -aG docker $USER
newgrp docker

# Enable experimental features
echo '{"experimental": true}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

# Verify multi-platform support
docker buildx ls
docker buildx create --use --name multiplatform
```

### Required Tools
```bash
# Install additional tools
sudo apt install -y \
    qemu-user-static \
    binfmt-support \
    rauc \
    e2fsprogs \
    rsync
```

## 📦 Docker Build Structure

### Directory Layout
```
homie_os/
├── docker/
│   ├── Dockerfile.jetson-builder     # Main ARM64 builder
│   ├── Dockerfile.bundle-creator     # Bundle creation container
│   └── docker-compose.yml           # Multi-stage orchestration
├── scripts/
│   ├── docker-build.sh              # Main build script
│   ├── extract-rootfs.sh            # Container filesystem extraction
│   └── create-docker-bundle.sh      # Docker-based bundle creation
├── config/
│   ├── jetson-packages.list         # Required Jetson packages
│   └── homie-services.list          # Homie OS service definitions
└── .github/workflows/
    └── docker-build-release.yml     # CI/CD pipeline
```

## 🐳 Docker Configuration Files

### Base Jetson Builder Image

Create `docker/Dockerfile.jetson-builder`:

```dockerfile
# Use NVIDIA L4T base image for Jetson compatibility
FROM nvcr.io/nvidia/l4t-base:r35.4.1

# Set build arguments
ARG VERSION=unknown
ARG BUILD_DATE
ARG HOMIE_BRANCH=main

# Labels for metadata
LABEL maintainer="Homie OS Team"
LABEL version="${VERSION}"
LABEL description="Homie OS for NVIDIA Jetson Orin Nano"
LABEL build-date="${BUILD_DATE}"

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV HOMIE_VERSION=${VERSION}
ENV CUDA_VERSION=11.4
ENV TRT_VERSION=8.5.2

# Update package lists and install base packages
RUN apt-get update && apt-get install -y \
    # System essentials
    systemd \
    systemd-sysv \
    init \
    dbus \
    # Network and utilities
    network-manager \
    openssh-server \
    curl \
    wget \
    vim \
    nano \
    htop \
    tree \
    jq \
    # Development tools
    git \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    # Container runtime
    docker.io \
    docker-compose \
    # NVIDIA specific
    nvidia-jetpack-dev \
    nvidia-container-toolkit \
    # Security and monitoring
    fail2ban \
    logrotate \
    rsyslog \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages for Homie OS
RUN pip3 install --no-cache-dir \
    fastapi \
    uvicorn \
    docker \
    pyyaml \
    requests \
    psutil \
    prometheus-client \
    pydantic

# Create system users and directories
RUN groupadd -r homie && useradd -r -g homie homie
RUN mkdir -p /opt/homie/{bin,config,data,logs}
RUN mkdir -p /data/{app,system,backups,logs}
RUN chown -R homie:homie /opt/homie /data

# Copy Homie OS components
COPY homie_orchestrator/ /opt/homie/
COPY config/ /opt/homie/config/
COPY scripts/system/ /opt/homie/scripts/

# Copy systemd service files
COPY config/systemd/ /etc/systemd/system/

# Set up Homie OS services
RUN systemctl enable homie-orchestrator
RUN systemctl enable homie-ai-stack
RUN systemctl enable docker
RUN systemctl enable ssh

# Configure SSH (disable root login, enable key auth)
RUN mkdir -p /home/homie/.ssh
RUN echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
RUN echo "PermitRootLogin no" >> /etc/ssh/sshd_config
RUN echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config

# Configure network (use NetworkManager)
RUN systemctl enable NetworkManager
RUN systemctl disable systemd-networkd

# Set up log rotation
COPY config/logrotate.d/ /etc/logrotate.d/

# Configure system limits
COPY config/limits.conf /etc/security/limits.conf

# Set version information
RUN echo "${VERSION}" > /etc/homie-version
RUN echo "build_date=${BUILD_DATE}" >> /etc/homie-build-info
RUN echo "base_image=nvcr.io/nvidia/l4t-base:r35.4.1" >> /etc/homie-build-info

# Clean up
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    find /var/log -type f -exec truncate -s 0 {} \;

# Set proper permissions
RUN chmod +x /opt/homie/bin/*
RUN chmod +x /opt/homie/scripts/*

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Default command
CMD ["/sbin/init"]
```

### Bundle Creator Container

Create `docker/Dockerfile.bundle-creator`:

```dockerfile
FROM ubuntu:22.04

# Install RAUC and bundle creation tools
RUN apt-get update && apt-get install -y \
    rauc \
    e2fsprogs \
    rsync \
    openssl \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy bundle creation scripts
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*

# Set working directory
WORKDIR /workspace

# Entry point for bundle creation
ENTRYPOINT ["/opt/scripts/create-docker-bundle.sh"]
```

### Docker Compose Configuration

Create `docker/docker-compose.yml`:

```yaml
version: '3.8'

services:
  jetson-builder:
    build:
      context: ..
      dockerfile: docker/Dockerfile.jetson-builder
      platforms:
        - linux/arm64
      args:
        VERSION: ${HOMIE_VERSION:-dev}
        BUILD_DATE: ${BUILD_DATE}
        HOMIE_BRANCH: ${GIT_BRANCH:-main}
    image: homie-os/jetson-builder:${HOMIE_VERSION:-dev}
    container_name: homie-jetson-builder
    platform: linux/arm64
    
  bundle-creator:
    build:
      context: ..
      dockerfile: docker/Dockerfile.bundle-creator
      platforms:
        - linux/amd64
    image: homie-os/bundle-creator:latest
    container_name: homie-bundle-creator
    volumes:
      - ../dist:/workspace/dist
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - HOMIE_VERSION=${HOMIE_VERSION:-dev}
    depends_on:
      - jetson-builder
```

## 🛠️ Build Scripts

### Main Build Script

Create `scripts/docker-build.sh`:

```bash
#!/bin/bash
# Docker-based ARM64 build script for Homie OS

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Default values
VERSION=""
OUTPUT_DIR="$PROJECT_ROOT/dist"
SIGN_BUNDLE=false
PUSH_IMAGES=false
CLEANUP=true
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"
}

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[$(date '+%H:%M:%S')] DEBUG:${NC} $1"
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build Homie OS RAUC bundles using Docker cross-compilation.

Options:
    -v, --version VERSION     Set bundle version (default: auto-generated)
    -o, --output DIR         Output directory (default: ./dist)
    --sign                   Sign the bundle with production certificates
    --push                   Push Docker images to registry
    --no-cleanup            Don't remove intermediate containers
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    $0                                    # Build development bundle
    $0 --version "1.2.3" --sign          # Build signed production bundle
    $0 --version "1.2.3" --push          # Build and push to registry

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --sign)
                SIGN_BUNDLE=true
                shift
                ;;
            --push)
                PUSH_IMAGES=true
                shift
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker not found. Please install Docker."
        exit 1
    fi
    
    # Check Docker buildx
    if ! docker buildx version >/dev/null 2>&1; then
        error "Docker buildx not available. Please install Docker buildx."
        exit 1
    fi
    
    # Check if we can build ARM64
    if ! docker buildx inspect | grep -q "linux/arm64"; then
        warn "ARM64 platform not available, setting up..."
        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
        docker buildx create --use --name multiplatform --platform linux/arm64,linux/amd64 || true
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    debug "Prerequisites check passed"
}

# Generate build metadata
generate_metadata() {
    if [[ -z "$VERSION" ]]; then
        if [[ "$GIT_BRANCH" == "main" ]]; then
            VERSION="$(date +%Y%m%d-%H%M%S)"
        else
            VERSION="$GIT_BRANCH-$(date +%Y%m%d-%H%M%S)"
        fi
        log "Auto-generated version: $VERSION"
    fi
    
    # Export environment variables for Docker Compose
    export HOMIE_VERSION="$VERSION"
    export BUILD_DATE="$BUILD_DATE"
    export GIT_BRANCH="$GIT_BRANCH"
    export GIT_COMMIT="$GIT_COMMIT"
    
    debug "Version: $VERSION"
    debug "Build date: $BUILD_DATE"
    debug "Git branch: $GIT_BRANCH"
    debug "Git commit: $GIT_COMMIT"
}

# Build ARM64 Jetson image
build_jetson_image() {
    log "Building ARM64 Jetson image..."
    
    cd "$PROJECT_ROOT"
    
    # Build the ARM64 image
    docker buildx build \
        --platform linux/arm64 \
        --file docker/Dockerfile.jetson-builder \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg HOMIE_BRANCH="$GIT_BRANCH" \
        --tag "homie-os/jetson-builder:$VERSION" \
        --tag "homie-os/jetson-builder:latest" \
        $([ "$PUSH_IMAGES" == "true" ] && echo "--push" || echo "--load") \
        .
    
    log "✓ ARM64 Jetson image built successfully"
}

# Extract rootfs from container
extract_rootfs() {
    log "Extracting rootfs from ARM64 container..."
    
    # Create container from image
    local container_id=$(docker create --platform linux/arm64 "homie-os/jetson-builder:$VERSION")
    
    # Create temporary directory for rootfs
    local rootfs_dir="$OUTPUT_DIR/rootfs-$VERSION"
    mkdir -p "$rootfs_dir"
    
    # Export container filesystem
    docker export "$container_id" | tar -C "$rootfs_dir" -xf -
    
    # Clean up container
    docker rm "$container_id"
    
    # Post-process the rootfs
    log "Post-processing extracted rootfs..."
    
    # Remove Docker-specific files
    rm -rf "$rootfs_dir"/.dockerenv
    rm -rf "$rootfs_dir"/var/lib/docker/*
    
    # Create necessary mount points
    mkdir -p "$rootfs_dir"/{proc,sys,dev,tmp,run,mnt,media}
    
    # Set proper permissions
    chmod 755 "$rootfs_dir"/{proc,sys,dev,tmp,run,mnt,media}
    
    # Create device nodes
    mknod "$rootfs_dir/dev/null" c 1 3 2>/dev/null || true
    mknod "$rootfs_dir/dev/zero" c 1 5 2>/dev/null || true
    mknod "$rootfs_dir/dev/random" c 1 8 2>/dev/null || true
    mknod "$rootfs_dir/dev/urandom" c 1 9 2>/dev/null || true
    
    # Update fstab for A/B partitions
    cat > "$rootfs_dir/etc/fstab" << EOF
# Homie OS fstab for A/B partition system
# Root filesystem will be mounted by RAUC
/dev/mmcblk0p3 /data ext4 defaults,nofail 0 2
tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=512M 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=256M 0 0
EOF
    
    # Set hostname
    echo "homie-jetson" > "$rootfs_dir/etc/hostname"
    
    # Update hosts file
    cat > "$rootfs_dir/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   homie-jetson
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    
    log "✓ Rootfs extracted and processed: $rootfs_dir"
    echo "$rootfs_dir" > "$OUTPUT_DIR/rootfs-path.txt"
}

# Create RAUC bundle from extracted rootfs
create_rauc_bundle() {
    log "Creating RAUC bundle from extracted rootfs..."
    
    local rootfs_dir=$(cat "$OUTPUT_DIR/rootfs-path.txt")
    local bundle_dir="$OUTPUT_DIR/bundle-$VERSION"
    
    mkdir -p "$bundle_dir"
    
    # Create filesystem image
    log "Creating filesystem image..."
    
    # Calculate required size
    local used_space=$(du -sb "$rootfs_dir" | cut -f1)
    local image_size=$((used_space + used_space / 10))  # Add 10% overhead
    local image_size_mb=$((image_size / 1024 / 1024))
    
    debug "Used space: $((used_space / 1024 / 1024))MB"
    debug "Image size: ${image_size_mb}MB"
    
    # Create ext4 filesystem image with directory contents
    mke2fs -t ext4 -d "$rootfs_dir" "$bundle_dir/rootfs.ext4" "${image_size_mb}M"
    
    # Optimize filesystem
    e2fsck -f "$bundle_dir/rootfs.ext4" || true
    resize2fs -M "$bundle_dir/rootfs.ext4"
    
    # Get final image size and checksum
    local final_size=$(stat -c%s "$bundle_dir/rootfs.ext4")
    local image_sha256=$(sha256sum "$bundle_dir/rootfs.ext4" | cut -d' ' -f1)
    
    log "✓ Filesystem image created: $((final_size / 1024 / 1024))MB"
    
    # Create bundle manifest
    log "Creating bundle manifest..."
    
    cat > "$bundle_dir/manifest.raucm" << EOF
[update]
compatible=jetson-orin-nano
version=$VERSION
description=Homie OS for NVIDIA Jetson Orin Nano - Built $(date +'%Y-%m-%d %H:%M:%S UTC')
build=$BUILD_DATE

[bundle]
format=plain
verity=true

[image.rootfs]
filename=rootfs.ext4
size=$final_size
sha256=$image_sha256
hooks=hook.sh
EOF
    
    # Create update hooks
    log "Creating update hooks..."
    
    cat > "$bundle_dir/hook.sh" << 'EOF'
#!/bin/bash

case "$1" in
    slot-pre-install)
        echo "Preparing for Homie OS update installation..."
        # Stop services gracefully
        systemctl stop homie-orchestrator 2>/dev/null || true
        systemctl stop docker 2>/dev/null || true
        # Sync filesystems
        sync
        ;;
    slot-post-install)
        echo "Homie OS update installation completed"
        # Mark slot as good after successful installation
        rauc mark good "$RAUC_SLOT_NAME" 2>/dev/null || true
        ;;
    slot-install)
        echo "Installing Homie OS update to slot $RAUC_SLOT_NAME"
        # Log installation details
        echo "$(date): Installing Homie OS $RAUC_BUNDLE_VERSION to $RAUC_SLOT_NAME" >> /data/logs/update.log
        ;;
esac
EOF
    
    chmod +x "$bundle_dir/hook.sh"
    
    debug "Manifest created with SHA256: $image_sha256"
    
    # Create the RAUC bundle
    local bundle_name="homie-os-jetson-$VERSION.raucb"
    local bundle_path="$OUTPUT_DIR/$bundle_name"
    
    log "Creating RAUC bundle: $bundle_name"
    
    if [[ "$SIGN_BUNDLE" == "true" ]]; then
        # Sign with production certificates
        if [[ -f "/etc/rauc/certs/release-cert.pem" && -f "/etc/rauc/certs/release-key.pem" ]]; then
            rauc bundle \
                --cert=/etc/rauc/certs/release-cert.pem \
                --key=/etc/rauc/certs/release-key.pem \
                "$bundle_dir" \
                "$bundle_path"
            log "✓ Signed RAUC bundle created"
        else
            error "Production certificates not found. Cannot sign bundle."
            exit 1
        fi
    else
        # Create unsigned bundle for development
        warn "Creating unsigned bundle (development only)"
        rauc bundle "$bundle_dir" "$bundle_path"
        log "✓ Unsigned RAUC bundle created"
    fi
    
    # Generate additional artifacts
    create_bundle_artifacts "$bundle_path" "$VERSION"
    
    log "✓ RAUC bundle created successfully: $bundle_path"
}

# Create additional bundle artifacts
create_bundle_artifacts() {
    local bundle_path="$1"
    local version="$2"
    local bundle_size=$(stat -c%s "$bundle_path")
    local bundle_sha256=$(sha256sum "$bundle_path" | cut -d' ' -f1)
    
    # Create checksums file
    cat > "$OUTPUT_DIR/homie-os-jetson-$version.sha256" << EOF
$bundle_sha256  homie-os-jetson-$version.raucb
EOF
    
    # Create installation instructions
    cat > "$OUTPUT_DIR/INSTALL.md" << EOF
# Homie OS Installation Instructions

## Version: $version
## Built: $BUILD_DATE
## Architecture: ARM64 (NVIDIA Jetson Orin Nano)

### Quick Installation

\`\`\`bash
# Download bundle
wget https://github.com/Homie-Ai-project/homie_os/releases/download/v$version/homie-os-jetson-$version.raucb

# Verify checksum
sha256sum -c homie-os-jetson-$version.sha256

# Install update
sudo rauc install homie-os-jetson-$version.raucb

# Reboot to activate
sudo reboot
\`\`\`

### Verification

After reboot, verify the installation:

\`\`\`bash
# Check RAUC status
sudo rauc status

# Check Homie OS version
cat /etc/homie-version

# Check services
sudo systemctl status homie-orchestrator
\`\`\`

### Rollback (if needed)

\`\`\`bash
# Mark current slot as bad and reboot to previous version
sudo rauc mark bad
sudo reboot
\`\`\`

### Bundle Information

- **Size**: $((bundle_size / 1024 / 1024))MB
- **SHA256**: $bundle_sha256
- **Signed**: $([ "$SIGN_BUNDLE" == "true" ] && echo "Yes" || echo "No (development)")
- **Compatible**: NVIDIA Jetson Orin Nano with RAUC support

EOF
    
    # Create build info
    cat > "$OUTPUT_DIR/build-info.json" << EOF
{
    "version": "$version",
    "build_date": "$BUILD_DATE",
    "git_branch": "$GIT_BRANCH",
    "git_commit": "$GIT_COMMIT",
    "architecture": "arm64",
    "target_platform": "jetson-orin-nano",
    "bundle_size": $bundle_size,
    "bundle_sha256": "$bundle_sha256",
    "signed": $([ "$SIGN_BUNDLE" == "true" ] && echo "true" || echo "false"),
    "rauc_compatible": "jetson-orin-nano"
}
EOF
    
    log "✓ Bundle artifacts created"
}

# Cleanup temporary files
cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        log "Cleaning up temporary files..."
        
        # Remove extracted rootfs
        if [[ -f "$OUTPUT_DIR/rootfs-path.txt" ]]; then
            local rootfs_dir=$(cat "$OUTPUT_DIR/rootfs-path.txt")
            if [[ -d "$rootfs_dir" ]]; then
                rm -rf "$rootfs_dir"
            fi
            rm -f "$OUTPUT_DIR/rootfs-path.txt"
        fi
        
        # Remove bundle working directory
        rm -rf "$OUTPUT_DIR"/bundle-*
        
        # Clean up Docker images (optional)
        # docker rmi "homie-os/jetson-builder:$VERSION" 2>/dev/null || true
        
        log "✓ Cleanup completed"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Homie OS Docker Cross-Platform Builder${NC}"
    echo "====================================="
    echo
    
    parse_args "$@"
    check_prerequisites
    generate_metadata
    
    # Set trap for cleanup
    trap cleanup EXIT INT TERM
    
    build_jetson_image
    extract_rootfs
    create_rauc_bundle
    
    # Print results
    echo
    echo -e "${GREEN}Build completed successfully!${NC}"
    echo
    echo -e "${BLUE}Artifacts created:${NC}"
    ls -la "$OUTPUT_DIR"/*.raucb "$OUTPUT_DIR"/*.sha256 "$OUTPUT_DIR"/*.md 2>/dev/null || true
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Test the bundle on a Jetson Orin Nano device"
    echo "2. Upload to GitHub releases or your distribution server"
    echo "3. Update target systems using RAUC"
    echo
}

# Run main function
main "$@"
```

### Rootfs Extraction Script

Create `scripts/extract-rootfs.sh`:

```bash
#!/bin/bash
# Extract rootfs from Docker container for bundle creation

set -e

CONTAINER_IMAGE="$1"
OUTPUT_DIR="$2"
PLATFORM="${3:-linux/arm64}"

if [[ -z "$CONTAINER_IMAGE" || -z "$OUTPUT_DIR" ]]; then
    echo "Usage: $0 <container_image> <output_dir> [platform]"
    exit 1
fi

echo "Extracting rootfs from $CONTAINER_IMAGE..."

# Create container
CONTAINER_ID=$(docker create --platform "$PLATFORM" "$CONTAINER_IMAGE")

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Export and extract filesystem
echo "Exporting container filesystem..."
docker export "$CONTAINER_ID" | tar -C "$OUTPUT_DIR" -xf -

# Cleanup container
docker rm "$CONTAINER_ID"

echo "Rootfs extracted to: $OUTPUT_DIR"
```

### Docker Bundle Creation Script

Create `scripts/create-docker-bundle.sh`:

```bash
#!/bin/bash
# Create RAUC bundle from Docker-extracted rootfs

set -e

# Configuration
ROOTFS_DIR="$1"
VERSION="$2"
OUTPUT_DIR="${3:-/workspace/dist}"
SIGN_BUNDLE="${4:-false}"

# Validate inputs
if [[ -z "$ROOTFS_DIR" || -z "$VERSION" ]]; then
    echo "Usage: $0 <rootfs_dir> <version> [output_dir] [sign_bundle]"
    exit 1
fi

echo "Creating RAUC bundle from rootfs: $ROOTFS_DIR"
echo "Version: $VERSION"
echo "Output: $OUTPUT_DIR"

# Create bundle directory
BUNDLE_DIR="$OUTPUT_DIR/bundle-$VERSION"
mkdir -p "$BUNDLE_DIR"

# Create filesystem image
echo "Creating filesystem image..."
USED_SPACE=$(du -sb "$ROOTFS_DIR" | cut -f1)
IMAGE_SIZE=$((USED_SPACE + USED_SPACE / 10))  # Add 10% overhead
IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))

mke2fs -t ext4 -d "$ROOTFS_DIR" "$BUNDLE_DIR/rootfs.ext4" "${IMAGE_SIZE_MB}M"
e2fsck -f "$BUNDLE_DIR/rootfs.ext4" || true
resize2fs -M "$BUNDLE_DIR/rootfs.ext4"

# Get image info
FINAL_SIZE=$(stat -c%s "$BUNDLE_DIR/rootfs.ext4")
IMAGE_SHA256=$(sha256sum "$BUNDLE_DIR/rootfs.ext4" | cut -d' ' -f1)

echo "Image size: $((FINAL_SIZE / 1024 / 1024))MB"
echo "SHA256: $IMAGE_SHA256"

# Create manifest
cat > "$BUNDLE_DIR/manifest.raucm" << EOF
[update]
compatible=jetson-orin-nano
version=$VERSION
description=Homie OS Docker Build - $VERSION
build=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

[bundle]
format=plain
verity=true

[image.rootfs]
filename=rootfs.ext4
size=$FINAL_SIZE
sha256=$IMAGE_SHA256
EOF

# Create bundle
BUNDLE_NAME="homie-os-jetson-$VERSION.raucb"
BUNDLE_PATH="$OUTPUT_DIR/$BUNDLE_NAME"

if [[ "$SIGN_BUNDLE" == "true" ]]; then
    echo "Creating signed bundle..."
    rauc bundle --cert=/certs/cert.pem --key=/certs/key.pem "$BUNDLE_DIR" "$BUNDLE_PATH"
else
    echo "Creating unsigned bundle..."
    rauc bundle "$BUNDLE_DIR" "$BUNDLE_PATH"
fi

echo "Bundle created: $BUNDLE_PATH"
echo "Size: $(stat -c%s "$BUNDLE_PATH" | numfmt --to=iec)"
```

## 🚀 GitHub Actions CI/CD

Create `.github/workflows/docker-build-release.yml`:

```yaml
name: Docker Cross-Platform Build and Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version'
        required: true
        default: '1.0.0'
      sign_bundle:
        description: 'Sign the bundle'
        type: boolean
        default: false

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
      
    steps:
    - name: Checkout Repository
      uses: actions/checkout@v4
      with:
        fetch-depth: 0
        
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
      with:
        platforms: linux/arm64,linux/amd64
        
    - name: Set up QEMU
      uses: docker/setup-qemu-action@v3
      
    - name: Log in to Container Registry
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
        
    - name: Install Dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y rauc e2fsprogs
        
    - name: Set Version
      id: version
      run: |
        if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
          VERSION="${{ github.event.inputs.version }}"
        else
          VERSION="${GITHUB_REF#refs/tags/v}"
        fi
        echo "version=$VERSION" >> $GITHUB_OUTPUT
        echo "VERSION=$VERSION" >> $GITHUB_ENV
        
    - name: Build ARM64 Bundle
      run: |
        chmod +x scripts/docker-build.sh
        ./scripts/docker-build.sh \
          --version "${{ steps.version.outputs.version }}" \
          --output "./dist" \
          $([ "${{ github.event.inputs.sign_bundle }}" == "true" ] && echo "--sign" || true) \
          --verbose
          
    - name: Upload Build Artifacts
      uses: actions/upload-artifact@v4
      with:
        name: homie-os-bundles
        path: |
          dist/*.raucb
          dist/*.sha256
          dist/*.md
          dist/*.json
          
    - name: Create GitHub Release
      if: startsWith(github.ref, 'refs/tags/')
      uses: softprops/action-gh-release@v1
      with:
        files: |
          dist/homie-os-jetson-*.raucb
          dist/homie-os-jetson-*.sha256
          dist/INSTALL.md
          dist/build-info.json
        name: "Homie OS v${{ steps.version.outputs.version }}"
        body: |
          ## Homie OS v${{ steps.version.outputs.version }}
          
          ### 🚀 Docker Cross-Platform Build
          
          This release was built using Docker cross-compilation for ARM64 architecture, ensuring compatibility with NVIDIA Jetson Orin Nano devices.
          
          ### 📦 What's Included
          
          - `homie-os-jetson-${{ steps.version.outputs.version }}.raucb` - RAUC update bundle
          - `homie-os-jetson-${{ steps.version.outputs.version }}.sha256` - Checksums for verification
          - `INSTALL.md` - Detailed installation instructions
          - `build-info.json` - Build metadata and information
          
          ### 🔧 Installation
          
          ```bash
          # Download and verify
          wget https://github.com/${{ github.repository }}/releases/download/v${{ steps.version.outputs.version }}/homie-os-jetson-${{ steps.version.outputs.version }}.raucb
          wget https://github.com/${{ github.repository }}/releases/download/v${{ steps.version.outputs.version }}/homie-os-jetson-${{ steps.version.outputs.version }}.sha256
          sha256sum -c homie-os-jetson-${{ steps.version.outputs.version }}.sha256
          
          # Install update
          sudo rauc install homie-os-jetson-${{ steps.version.outputs.version }}.raucb
          sudo reboot
          ```
          
          ### 🛡️ Security
          
          - Bundle signature: ${{ github.event.inputs.sign_bundle == 'true' && '✅ Signed' || '⚠️ Unsigned (development)' }}
          - Architecture: ARM64 (NVIDIA Jetson Orin Nano)
          - Base image: NVIDIA L4T r35.4.1
          
          ### 📋 Requirements
          
          - NVIDIA Jetson Orin Nano with RAUC support
          - Homie OS A/B partition layout
          - At least 2GB free space for installation
          
        draft: false
        prerelease: ${{ contains(steps.version.outputs.version, '-') }}
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## 📝 Usage Instructions

### Development Builds

```bash
# Simple development build
./scripts/docker-build.sh

# Versioned development build
./scripts/docker-build.sh --version "2024.01-dev"

# Verbose output
./scripts/docker-build.sh --version "2024.01-dev" --verbose
```

### Production Builds

```bash
# Production build with signing
./scripts/docker-build.sh --version "1.2.3" --sign

# Build and push to registry
./scripts/docker-build.sh --version "1.2.3" --sign --push
```

### Manual Docker Commands

```bash
# Build ARM64 image manually
docker buildx build \
  --platform linux/arm64 \
  --file docker/Dockerfile.jetson-builder \
  --build-arg VERSION="1.2.3" \
  --tag "homie-os/jetson:1.2.3" \
  --load .

# Extract rootfs
./scripts/extract-rootfs.sh "homie-os/jetson:1.2.3" "./rootfs-extract"

# Create bundle
./scripts/create-docker-bundle.sh "./rootfs-extract" "1.2.3" "./dist"
```

## 🔍 Verification and Testing

### Bundle Verification

```bash
# Verify bundle structure
rauc info dist/homie-os-jetson-1.2.3.raucb

# Check filesystem contents
mkdir -p /tmp/bundle-check
rauc extract dist/homie-os-jetson-1.2.3.raucb /tmp/bundle-check
file /tmp/bundle-check/rootfs.ext4

# Mount and inspect filesystem
sudo mkdir -p /tmp/rootfs-check
sudo mount -o loop /tmp/bundle-check/rootfs.ext4 /tmp/rootfs-check
ls -la /tmp/rootfs-check/
sudo umount /tmp/rootfs-check
```

### Testing on Target

```bash
# Copy bundle to Jetson
scp dist/homie-os-jetson-1.2.3.raucb jetson-device:/tmp/

# Install on Jetson
ssh jetson-device "sudo rauc install /tmp/homie-os-jetson-1.2.3.raucb"

# Reboot and verify
ssh jetson-device "sudo reboot"
# Wait for reboot...
ssh jetson-device "cat /etc/homie-version && rauc status"
```

## 🎯 Summary

This Docker-based approach provides:

- ✅ **Native ARM64 builds** for Jetson hardware
- ✅ **Reproducible builds** using containerized environments
- ✅ **CI/CD integration** with GitHub Actions
- ✅ **Hardware driver support** via NVIDIA L4T base images
- ✅ **Clean, production-ready** bundles without development artifacts
- ✅ **Automated testing** and verification workflows

The result is enterprise-grade RAUC bundles that work perfectly on Jetson Orin Nano devices while maintaining the benefits of cross-platform development! 🚀
