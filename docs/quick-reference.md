# Homie OS Quick Variable Reference

## 🚀 Centralized Configuration System

**All variables are now managed in one place**: `config/variables.conf`

### 📋 Configuration Management
```bash
# List all variables
./scripts/load-config.sh list

# Get specific variable
./scripts/load-config.sh get VERSION

# Set variable value
./scripts/load-config.sh set VARIABLE_NAME value

# Validate configuration
./scripts/load-config.sh validate

# Generate .env file
./scripts/load-config.sh generate-env
```

## 🛠️ Most Commonly Updated Variables

### 📋 For New Releases
```bash
# Update project version using config system
./scripts/load-config.sh set VERSION 1.0.0-beta.1

# Or use version management script (updates config automatically)
./scripts/manage-version.sh --type [alpha|beta|rc|release] [--bump major|minor|patch]
```

### 🐳 For NVIDIA L4T Updates  
```bash
# Check for new L4T versions
curl -s https://nvcr.io/v2/nvidia/l4t-base/tags/list | jq '.tags[]' | sort

# Update L4T configuration
./scripts/load-config.sh set L4T_VERSION r36.3.0
./scripts/load-config.sh set L4T_BASE_IMAGE nvcr.io/nvidia/l4t-base:r36.3.0
./scripts/load-config.sh set CUDA_VERSION 12.3
./scripts/load-config.sh set TENSORRT_VERSION 10.1
./scripts/load-config.sh set JETPACK_VERSION 6.1

# Generate new Dockerfile
./scripts/generate-dockerfile.sh
```

### 📦 For New Device Support
```bash
# Update device configuration
./scripts/load-config.sh set TARGET_PLATFORM jetson-agx-orin
./scripts/load-config.sh set RAUC_COMPATIBLE jetson-agx-orin
./scripts/load-config.sh set BUNDLE_NAME_PATTERN "homie-os-agx-{version}.raucb"
```

### 🔧 For Build Configuration
```bash
# Enable/disable features
./scripts/load-config.sh set PUSH_IMAGE true
./scripts/load-config.sh set CREATE_BUNDLE true
./scripts/load-config.sh set SIGN_BUNDLE true

# Update registry settings
./scripts/load-config.sh set REGISTRY myregistry.io
./scripts/load-config.sh set IMAGE_NAME_PATTERN "myorg/homie-os:{version}"
```

## 🛠️ Quick Commands

```bash
# List all current variables
./scripts/config-helper.sh list

# Check for updates needed  
./scripts/config-helper.sh check

# Validate configuration
./scripts/config-helper.sh validate

# Create alpha build
./scripts/manage-version.sh --type alpha

# Update L4T version
./scripts/config-helper.sh update-l4t r36.3.0

# Test build
./scripts/test-local-build.sh
```

## 📍 Key File Locations

| Variable Type | File Location |
|---------------|---------------|
| **Version** | `VERSION` |
| **Docker Base** | `docker/Dockerfile.jetson-builder` |
| **Build Scripts** | `scripts/docker-build.sh` |
| **Bundle Config** | `scripts/create-docker-bundle.sh` |
| **CI/CD** | `.github/workflows/build-bundle.yml` |
| **Version Management** | `scripts/manage-version.sh` |

## ⚡ Emergency Updates

```bash
# Quick L4T update and test
./scripts/config-helper.sh update-l4t r36.3.0
./scripts/test-local-build.sh

# Quick version bump and release
./scripts/manage-version.sh --type release --bump patch
git push origin main --tags

# Quick validation after changes
./scripts/config-helper.sh validate
```
