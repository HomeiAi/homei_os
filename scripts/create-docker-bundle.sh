#!/bin/bash
# Create RAUC bundle from Docker-extracted rootfs

set -e

# Load configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/load-config.sh" load 2>/dev/null || {
    echo "WARNING: Could not load configuration, using defaults"
}

# Configuration with fallbacks
ROOTFS_DIR="$1"
VERSION="$2"
OUTPUT_DIR="${3:-${OUTPUT_DIR:-./build}}"
SIGN_BUNDLE="${4:-${SIGN_BUNDLE:-false}}"

# Validate inputs
if [[ -z "$ROOTFS_DIR" || -z "$VERSION" ]]; then
    echo "Usage: $0 <rootfs_dir> <version> [output_dir] [sign_bundle]"
    exit 1
fi

if [[ ! -d "$ROOTFS_DIR" ]]; then
    echo "Error: Rootfs directory '$ROOTFS_DIR' does not exist"
    exit 1
fi

echo "Creating RAUC bundle from rootfs: $ROOTFS_DIR"
echo "Version: $VERSION"
echo "Output: $OUTPUT_DIR"

# Check rootfs contents
echo "Rootfs contents:"
ls -la "$ROOTFS_DIR/" | head -20

# Create bundle directory
BUNDLE_DIR="$OUTPUT_DIR/bundle-$VERSION"
mkdir -p "$BUNDLE_DIR"

# Create filesystem image
echo "Creating filesystem image..."
USED_SPACE=$(du -sb "$ROOTFS_DIR" | cut -f1)
# Add 50% overhead for safety, minimum 512MB
IMAGE_SIZE=$((USED_SPACE * 3 / 2))
MIN_SIZE=$((512 * 1024 * 1024))
if [[ $IMAGE_SIZE -lt $MIN_SIZE ]]; then
    IMAGE_SIZE=$MIN_SIZE
fi
IMAGE_SIZE_BLOCKS=$((IMAGE_SIZE / 4096))

echo "Rootfs size: $((USED_SPACE / 1024 / 1024))MB"
echo "Creating image with: $((IMAGE_SIZE / 1024 / 1024))MB ($IMAGE_SIZE_BLOCKS blocks)"

# Create empty filesystem first
mke2fs -t ext4 -F "$BUNDLE_DIR/rootfs.ext4" $IMAGE_SIZE_BLOCKS

# Mount and copy files
MOUNT_POINT=$(mktemp -d)
echo "Copying files into the device: "
mount -o loop "$BUNDLE_DIR/rootfs.ext4" "$MOUNT_POINT"
trap "umount '$MOUNT_POINT' 2>/dev/null || true; rmdir '$MOUNT_POINT' 2>/dev/null || true" EXIT

# Copy with proper permissions and exclude problematic files
echo "Copying files from $ROOTFS_DIR to $MOUNT_POINT..."
if ! rsync -avx --exclude="dev/*" --exclude="proc/*" --exclude="sys/*" --exclude="tmp/*" \
      --exclude="run/*" --exclude="mnt/*" --exclude="media/*" --exclude="var/cache/*" \
      --exclude="var/log/*" --exclude="var/tmp/*" --exclude="usr/share/zoneinfo/right/*" \
      --exclude="usr/share/zoneinfo/posix/*" \
      "$ROOTFS_DIR/" "$MOUNT_POINT/"; then
    echo "Error: Failed to copy files to filesystem"
    exit 1
fi

# Create essential directories
mkdir -p "$MOUNT_POINT"/{dev,proc,sys,tmp,run,mnt,media}
chmod 1777 "$MOUNT_POINT/tmp"

# Unmount before continuing
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"
trap - EXIT

# Check and resize filesystem
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
compatible=${RAUC_COMPATIBLE:-jetson-orin-nano}
version=$VERSION
description=Homie OS Docker Build - $VERSION
build=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

[bundle]
format=${BUNDLE_FORMAT:-plain}
verity=${BUNDLE_VERITY:-true}

[image.rootfs]
filename=rootfs.ext4
size=$FINAL_SIZE
sha256=$IMAGE_SHA256
EOF

# Create bundle
BUNDLE_NAME="${BUNDLE_NAME_PATTERN:-homie-os-jetson-{version}.raucb}"
BUNDLE_NAME="${BUNDLE_NAME/\{version\}/$VERSION}"
BUNDLE_PATH="$OUTPUT_DIR/$BUNDLE_NAME"

if [[ "$SIGN_BUNDLE" == "true" ]]; then
    echo "Creating signed bundle..."
    CERT_PATH="${RAUC_CERT_PATH:-/certs/cert.pem}"
    KEY_PATH="${RAUC_KEY_PATH:-/certs/key.pem}"
    rauc bundle --cert="$CERT_PATH" --key="$KEY_PATH" "$BUNDLE_DIR" "$BUNDLE_PATH"
else
    echo "Creating unsigned bundle..."
    rauc bundle "$BUNDLE_DIR" "$BUNDLE_PATH"
fi

echo "Bundle created: $BUNDLE_PATH"
echo "Size: $(stat -c%s "$BUNDLE_PATH" | numfmt --to=iec)"
