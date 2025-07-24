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
