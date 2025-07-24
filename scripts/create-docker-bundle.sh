#!/bin/bash
# Create RAUC bundle from Docker-extracted rootfs

set -e

# Configuration
ROOTFS_DIR="$1"
VERSION="$2"
OUTPUT_DIR="${3:-./build}"
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
