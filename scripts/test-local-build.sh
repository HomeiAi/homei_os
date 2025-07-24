#!/bin/bash
# Local test script for GitHub Actions workflow

set -e

echo "🧪 Testing Homie OS Bundle Creation Locally"

# Generate alpha version
DATE=$(date +%Y%m%d)
SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
VERSION="0.1.0-alpha.${DATE}.${SHORT_SHA}"

echo "📦 Building version: $VERSION"

# Create test certificates
echo "🔐 Creating test certificates..."
mkdir -p build/certs
openssl req -x509 -newkey rsa:2048 -keyout build/certs/rauc-key.pem -out build/certs/rauc-cert.pem -days 365 -nodes -subj "/CN=Homie OS Test" 2>/dev/null

# Build Docker image
echo "🐳 Building Docker image..."
./scripts/docker-build.sh --version "$VERSION" --no-bundle

# Create RAUC bundle
echo "📦 Creating RAUC bundle..."
./scripts/create-docker-bundle.sh build/rootfs "$VERSION" build false

# Display results
echo ""
echo "✅ Build completed successfully!"
echo "📊 Build artifacts:"
ls -lh build/homie-os-jetson-*.raucb build/rootfs.ext4 build/build-report-*.json 2>/dev/null || true

echo ""
echo "🎯 To test this bundle:"
echo "  rauc info build/homie-os-jetson-${VERSION}.raucb"
echo ""
echo "🚀 Version built: $VERSION"
