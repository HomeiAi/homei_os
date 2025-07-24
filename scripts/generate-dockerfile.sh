#!/bin/bash
# Generate Dockerfile from template using configuration variables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load configuration
source "$SCRIPT_DIR/load-config.sh" load

TEMPLATE_FILE="$PROJECT_ROOT/docker/Dockerfile.jetson-builder.template"
OUTPUT_FILE="$PROJECT_ROOT/docker/Dockerfile.jetson-builder"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "ERROR: Template file not found: $TEMPLATE_FILE" >&2
    exit 1
fi

echo "Generating Dockerfile from template..."

# Use sed to replace template variables
sed \
    -e "s|{{L4T_VERSION}}|${L4T_VERSION}|g" \
    -e "s|{{L4T_BASE_IMAGE}}|${L4T_BASE_IMAGE}|g" \
    -e "s|{{JETPACK_VERSION}}|${JETPACK_VERSION}|g" \
    -e "s|{{CUDA_VERSION}}|${CUDA_VERSION}|g" \
    -e "s|{{TENSORRT_VERSION}}|${TENSORRT_VERSION}|g" \
    -e "s|{{DEBIAN_FRONTEND}}|${DEBIAN_FRONTEND}|g" \
    "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "Generated: $OUTPUT_FILE"
echo "Base image: $L4T_BASE_IMAGE"
echo "JetPack: $JETPACK_VERSION"
echo "CUDA: $CUDA_VERSION"
echo "TensorRT: $TENSORRT_VERSION"
