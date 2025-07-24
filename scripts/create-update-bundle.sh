#!/bin/bash
# Create RAUC update bundle script
# Part of Homie OS - Enterprise-grade embedded system

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/homie-bundle-$(date +%Y%m%d-%H%M%S)"
BUNDLE_DIR="$WORK_DIR/bundle"
ROOTFS_DIR="$WORK_DIR/rootfs"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)}"

# Default values
VERSION=""
DESCRIPTION=""
INCLUDE_DOCKER=false
EXCLUDE_CACHE=true
EXCLUDE_LOGS=true
SIGN_BUNDLE=true
DEVELOPMENT=false
COMPRESSION="xz"
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create RAUC update bundle from current system.

Options:
    -v, --version VERSION      Set bundle version (default: auto-generated)
    -d, --description DESC     Set bundle description
    -o, --output DIR          Output directory (default: current directory)
    
    --include-docker          Include Docker data in bundle
    --exclude-cache           Exclude cache directories (default: true)
    --exclude-logs            Exclude log files (default: true)
    --no-sign                 Create unsigned bundle (development only)
    --dev                     Development mode (no signing, less compression)
    
    --compression TYPE        Compression type: none, gzip, xz (default: xz)
    --verbose                 Enable verbose output
    --fix-config              Fix RAUC configuration and exit
    
    -h, --help               Show this help message

Examples:
    $0                                    # Create bundle with auto-generated version
    $0 --version "2.1.0"                  # Create bundle with specific version
    $0 --dev --no-sign                    # Create development bundle (works without RAUC setup)
    $0 --include-docker --output /data    # Include Docker data, output to /data

Development Mode:
    Use --dev flag when RAUC is not installed or configured on the build system.
    This mode creates bundle structure that can be converted to RAUC bundle later.

EOF
}

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

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -d|--description)
                DESCRIPTION="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --include-docker)
                INCLUDE_DOCKER=true
                shift
                ;;
            --exclude-cache)
                EXCLUDE_CACHE=true
                shift
                ;;
            --exclude-logs)
                EXCLUDE_LOGS=true
                shift
                ;;
            --no-sign)
                SIGN_BUNDLE=false
                shift
                ;;
            --dev)
                DEVELOPMENT=true
                SIGN_BUNDLE=false
                COMPRESSION="gzip"
                shift
                ;;
            --compression)
                COMPRESSION="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --fix-config)
                # Check if running as root
                if [[ $EUID -ne 0 ]]; then
                    error "This option requires root privileges"
                    exit 1
                fi
                
                echo -e "${BLUE}Fixing RAUC Configuration${NC}"
                echo "========================="
                
                if fix_rauc_config; then
                    log "RAUC configuration fixed successfully!"
                    log "You can now run the bundle creation script normally."
                else
                    error "Could not fix RAUC configuration automatically."
                    echo "Please check the error messages above and fix manually."
                fi
                exit 0
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

# Fix RAUC configuration
fix_rauc_config() {
    log "Attempting to fix RAUC configuration..."
    
    # Create RAUC directories if they don't exist
    mkdir -p /etc/rauc /etc/rauc/certs
    
    # Check what's wrong with the current configuration
    local rauc_error=$(rauc info 2>&1 || true)
    echo "RAUC error: $rauc_error"
    
    # Check if configuration file exists
    if [[ ! -f /etc/rauc/system.conf ]]; then
        log "Creating missing RAUC configuration file..."
        cat > /etc/rauc/system.conf << 'EOF'
[system]
compatible=jetson-nano
bootloader=uboot
statusfile=/tmp/rauc.status

[keyring]
path=/etc/rauc/keyring.pem

[slot.rootfs.0]
device=/dev/sdd1
type=ext4
bootname=a

[slot.rootfs.1]
device=/dev/sdd2
type=ext4
bootname=b
EOF
    fi
    
    # Check if keyring exists
    if [[ ! -f /etc/rauc/keyring.pem ]]; then
        log "Creating missing RAUC keyring..."
        
        # Generate minimal CA certificate for development
        openssl req -x509 -newkey rsa:2048 -keyout /etc/rauc/certs/ca-key.pem -out /etc/rauc/certs/ca-cert.pem -days 365 -nodes \
            -subj "/C=US/O=Homie OS Dev/CN=Homie OS CA" 2>/dev/null
        
        # Copy CA cert as keyring
        cp /etc/rauc/certs/ca-cert.pem /etc/rauc/keyring.pem
        chmod 644 /etc/rauc/keyring.pem
        chmod 600 /etc/rauc/certs/ca-key.pem
        
        # Generate development signing certificate
        openssl req -new -newkey rsa:2048 -keyout /etc/rauc/certs/dev-key.pem -out /etc/rauc/certs/dev-req.pem -nodes \
            -subj "/C=US/O=Homie OS Dev/CN=Homie OS Dev Cert" 2>/dev/null
        
        openssl x509 -req -in /etc/rauc/certs/dev-req.pem -CA /etc/rauc/certs/ca-cert.pem -CAkey /etc/rauc/certs/ca-key.pem \
            -out /etc/rauc/certs/dev-cert.pem -days 365 2>/dev/null
        
        rm -f /etc/rauc/certs/dev-req.pem
        chmod 600 /etc/rauc/certs/dev-key.pem
        chmod 644 /etc/rauc/certs/dev-cert.pem
        
        log "✓ RAUC certificates created"
    fi
    
    # Test the configuration
    if rauc info >/dev/null 2>&1; then
        log "✓ RAUC configuration is now valid"
        return 0
    else
        warn "RAUC configuration still has issues. This may be normal in a development environment."
        log "Current RAUC info output:"
        rauc info 2>&1 || true
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
    
    # Check if RAUC is installed
    if ! command -v rauc >/dev/null 2>&1; then
        if [[ "$DEVELOPMENT" == "true" ]]; then
            warn "RAUC is not installed. Development mode will create bundle structure without RAUC validation."
        else
            error "RAUC is not installed. Please run setup-rauc-jetson.sh first, or use --dev mode."
            exit 1
        fi
    fi
    
    # Check RAUC configuration (only if cd /s installed)
    if command -v rauc >/dev/null 2>&1; then
        if ! rauc info >/dev/null 2>&1; then
            if [[ "$DEVELOPMENT" == "true" ]]; then
                warn "RAUC configuration is invalid. Development mode will proceed anyway."
            else
                error "RAUC configuration is invalid. Attempting to fix..."
                if fix_rauc_config; then
                    log "✓ RAUC configuration fixed successfully"
                else
                    error "Could not fix RAUC configuration. Use --dev mode or fix manually."
                    echo "Manual steps:"
                    echo "1. Check /etc/rauc/system.conf syntax"
                    echo "2. Ensure /etc/rauc/keyring.pem exists"
                    echo "3. Verify device paths in configuration"
                    exit 1
                fi
            fi
        else
            log "✓ RAUC configuration is valid"
        fi
    fi
    
    # Check certificates if signing is enabled
    if [[ "$SIGN_BUNDLE" == "true" ]]; then
        if [[ ! -f /etc/rauc/certs/dev-cert.pem || ! -f /etc/rauc/certs/dev-key.pem ]]; then
            if [[ "$DEVELOPMENT" == "true" ]]; then
                warn "RAUC signing certificates not found. Disabling signing for development mode."
                SIGN_BUNDLE=false
            else
                error "RAUC signing certificates not found. Run setup script or use --no-sign"
                exit 1
            fi
        fi
    fi
    
    # Check required tools
    local required_tools=("rsync" "mke2fs" "tar")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "Required tool '$tool' not found"
            exit 1
        fi
    done
    
    # Check available disk space
    local available_space=$(df /tmp | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then  # 2GB in KB
        error "Insufficient disk space in /tmp. At least 2GB required."
        exit 1
    fi
    
    debug "Prerequisites check passed"
}

# Generate version and description
generate_metadata() {
    if [[ -z "$VERSION" ]]; then
        VERSION="$(date +%Y%m%d-%H%M%S)"
        log "Auto-generated version: $VERSION"
    fi
    
    if [[ -z "$DESCRIPTION" ]]; then
        DESCRIPTION="Homie OS Update $(date +'%Y-%m-%d %H:%M:%S')"
        if [[ "$DEVELOPMENT" == "true" ]]; then
            DESCRIPTION="$DESCRIPTION (Development Build)"
        fi
    fi
    
    debug "Version: $VERSION"
    debug "Description: $DESCRIPTION"
}

# Prepare working directories
prepare_directories() {
    log "Preparing working directories..."
    
    mkdir -p "$ROOTFS_DIR" "$BUNDLE_DIR" "$OUTPUT_DIR"
    
    debug "Work directory: $WORK_DIR"
    debug "Rootfs directory: $ROOTFS_DIR"
    debug "Bundle directory: $BUNDLE_DIR"
    debug "Output directory: $OUTPUT_DIR"
}

# Copy root filesystem
copy_rootfs() {
    log "Copying root filesystem (this may take several minutes)..."
    
    # Build exclusion list
    local exclude_opts=(
        --exclude=/proc
        --exclude=/sys
        --exclude=/dev
        --exclude=/tmp
        --exclude=/media
        --exclude=/mnt
        --exclude=/data
        --exclude=/var/run
        --exclude=/var/lock
        --exclude="$WORK_DIR"
    )
    
    if [[ "$EXCLUDE_CACHE" == "true" ]]; then
        exclude_opts+=(
            --exclude=/var/cache
            --exclude=/home/*/.cache
            --exclude=/root/.cache
        )
    fi
    
    if [[ "$EXCLUDE_LOGS" == "true" ]]; then
        exclude_opts+=(
            --exclude=/var/log/*
            --exclude=/var/log/journal
        )
    fi
    
    if [[ "$INCLUDE_DOCKER" != "true" ]]; then
        exclude_opts+=(
            --exclude=/var/lib/docker
            --exclude=/var/lib/containerd
        )
    fi
    
    # Additional development exclusions
    if [[ "$DEVELOPMENT" == "true" ]]; then
        exclude_opts+=(
            --exclude=*.pyc
            --exclude=__pycache__
            --exclude=.git
            --exclude=node_modules
        )
    fi
    
    # Copy filesystem
    if [[ "$VERBOSE" == "true" ]]; then
        rsync -aHAXx --progress "${exclude_opts[@]}" / "$ROOTFS_DIR/"
    else
        rsync -aHAXx "${exclude_opts[@]}" / "$ROOTFS_DIR/"
    fi
    
    log "Root filesystem copied successfully"
}

# Clean up sensitive data
cleanup_sensitive_data() {
    log "Cleaning up sensitive data..."
    
    # Remove SSH host keys (will be regenerated on first boot)
    rm -f "$ROOTFS_DIR"/etc/ssh/ssh_host_*
    
    # Remove shell history
    rm -f "$ROOTFS_DIR"/root/.bash_history
    find "$ROOTFS_DIR"/home -name ".bash_history" -delete 2>/dev/null || true
    
    # Remove temporary files
    find "$ROOTFS_DIR"/tmp -type f -delete 2>/dev/null || true
    find "$ROOTFS_DIR"/var/tmp -type f -delete 2>/dev/null || true
    
    # Remove log files if not excluded above
    if [[ "$EXCLUDE_LOGS" != "true" ]]; then
        find "$ROOTFS_DIR"/var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
    fi
    
    # Remove package cache
    rm -rf "$ROOTFS_DIR"/var/lib/apt/lists/*
    
    # Clear machine ID (will be regenerated)
    truncate -s 0 "$ROOTFS_DIR"/etc/machine-id || true
    
    debug "Sensitive data cleanup completed"
}

# Create filesystem image
create_filesystem_image() {
    log "Creating filesystem image..."
    
    # Calculate required size
    local used_space=$(du -sb "$ROOTFS_DIR" | cut -f1)
    local image_size=$((used_space + used_space / 10))  # Add 10% overhead
    local image_size_mb=$((image_size / 1024 / 1024))
    
    debug "Used space: $((used_space / 1024 / 1024))MB"
    debug "Image size: ${image_size_mb}MB"
    
    # Create ext4 filesystem image
    mke2fs -t ext4 -d "$ROOTFS_DIR" "$BUNDLE_DIR/rootfs.ext4" "${image_size_mb}M"
    
    # Optimize filesystem
    e2fsck -f "$BUNDLE_DIR/rootfs.ext4"
    resize2fs -M "$BUNDLE_DIR/rootfs.ext4"
    
    # Get actual image size
    local actual_size=$(stat -c%s "$BUNDLE_DIR/rootfs.ext4")
    log "Filesystem image created: $((actual_size / 1024 / 1024))MB"
}

# Create bundle manifest
create_manifest() {
    log "Creating bundle manifest..."
    
    local image_size=$(stat -c%s "$BUNDLE_DIR/rootfs.ext4")
    local image_sha256=$(sha256sum "$BUNDLE_DIR/rootfs.ext4" | cut -d' ' -f1)
    
    cat > "$BUNDLE_DIR/manifest.raucm" << EOF
[update]
compatible=jetson-nano
version=$VERSION
description=$DESCRIPTION
build=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

[bundle]
format=plain
EOF
    
    if [[ "$DEVELOPMENT" != "true" ]]; then
        echo "verity=true" >> "$BUNDLE_DIR/manifest.raucm"
    fi
    
    cat >> "$BUNDLE_DIR/manifest.raucm" << EOF

[image.rootfs]
filename=rootfs.ext4
size=$image_size
sha256=$image_sha256
EOF
    
    debug "Manifest created with SHA256: $image_sha256"
}

# Create update hooks (optional)
create_hooks() {
    if [[ "$DEVELOPMENT" != "true" ]]; then
        log "Creating update hooks..."
        
        cat > "$BUNDLE_DIR/hook.sh" << 'EOF'
#!/bin/bash

case "$1" in
    slot-pre-install)
        echo "Preparing for update installation..."
        # Stop critical services
        systemctl stop docker 2>/dev/null || true
        ;;
    slot-post-install)
        echo "Update installation completed"
        # Mark slot as good after successful installation
        rauc mark good "$RAUC_SLOT_NAME" 2>/dev/null || true
        ;;
    slot-install)
        echo "Installing update to slot $RAUC_SLOT_NAME"
        ;;
esac
EOF
        
        chmod +x "$BUNDLE_DIR/hook.sh"
        
        # Add hook to manifest
        echo "" >> "$BUNDLE_DIR/manifest.raucm"
        echo "[hooks]" >> "$BUNDLE_DIR/manifest.raucm"
        echo "filename=hook.sh" >> "$BUNDLE_DIR/manifest.raucm"
        
        debug "Update hooks created"
    fi
}

# Create signed bundle
create_bundle() {
    local bundle_name="homie-os-$VERSION"
    if [[ "$DEVELOPMENT" == "true" ]]; then
        bundle_name="$bundle_name-dev"
    fi
    bundle_name="$bundle_name.raucb"
    
    local bundle_path="$OUTPUT_DIR/$bundle_name"
    
    log "Creating RAUC bundle: $bundle_name"
    
    # Check if RAUC is available for bundle creation
    if ! command -v rauc >/dev/null 2>&1; then
        warn "RAUC not available - creating bundle archive manually"
        
        # Create bundle as tar archive (can be converted to .raucb later)
        local tar_bundle="${bundle_path%.raucb}.tar.gz"
        cd "$BUNDLE_DIR"
        tar -czf "$tar_bundle" .
        
        local bundle_size=$(stat -c%s "$tar_bundle")
        log "Bundle archive created: $(basename "$tar_bundle") ($((bundle_size / 1024 / 1024))MB)"
        
        echo
        echo -e "${YELLOW}Note: Bundle created as tar archive since RAUC is not available.${NC}"
        echo "To convert to RAUC bundle on target system, run:"
        echo "  rauc bundle <extracted_bundle_dir> $bundle_name"
        echo
        
        return 0
    fi
    
    if [[ "$SIGN_BUNDLE" == "true" ]]; then
        rauc bundle \
            --cert=/etc/rauc/certs/dev-cert.pem \
            --key=/etc/rauc/certs/dev-key.pem \
            "$BUNDLE_DIR" \
            "$bundle_path"
    else
        warn "Creating unsigned bundle (development only)"
        rauc bundle \
            "$BUNDLE_DIR" \
            "$bundle_path"
    fi
    
    # Verify bundle
    if [[ -f "$bundle_path" ]]; then
        local bundle_size=$(stat -c%s "$bundle_path")
        log "Bundle created successfully: $bundle_name ($((bundle_size / 1024 / 1024))MB)"
        
        # Show bundle info (only if RAUC is available)
        if [[ "$VERBOSE" == "true" ]] && command -v rauc >/dev/null 2>&1; then
            rauc info "$bundle_path"
        fi
        
        echo
        echo -e "${GREEN}Bundle Information:${NC}"
        echo "  File: $bundle_path"
        echo "  Size: $((bundle_size / 1024 / 1024))MB"
        echo "  Version: $VERSION"
        echo "  Signed: $([ "$SIGN_BUNDLE" == "true" ] && echo "Yes" || echo "No")"
        echo "  SHA256: $(sha256sum "$bundle_path" | cut -d' ' -f1)"
        
    else
        error "Failed to create bundle"
        exit 1
    fi
}

# Cleanup temporary files
cleanup() {
    if [[ -d "$WORK_DIR" ]]; then
        log "Cleaning up temporary files..."
        rm -rf "$WORK_DIR"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Homie OS Update Bundle Creator${NC}"
    echo "=============================="
    echo
    
    parse_args "$@"
    check_prerequisites
    generate_metadata
    prepare_directories
    
    # Set trap for cleanup
    trap cleanup EXIT INT TERM
    
    copy_rootfs
    cleanup_sensitive_data
    create_filesystem_image
    create_manifest
    create_hooks
    create_bundle
    
    log "Update bundle creation completed successfully!"
}

# Run main function
main "$@"
