# Centralized Configuration Management System

## 🎯 Overview

Homie OS now uses a **centralized configuration management system** where all variables are stored in one place and automatically propagated throughout the build system. This ensures consistency, reduces errors, and simplifies maintenance.

## 📁 Single Source of Truth

**All configuration is managed in**: `config/variables.conf`

This file contains 50+ variables organized into logical sections:
- **Version Management** - Project version, build metadata
- **NVIDIA L4T** - Base images, CUDA, TensorRT versions  
- **Platform** - Target devices, architectures
- **RAUC Bundle** - Update bundle configuration
- **CI/CD** - Automation settings
- **Security** - Signing and certificates
- **Development** - Debug and testing options
- **System** - Runtime configuration
- **Advanced** - Expert-level settings

## 🛠️ Configuration Manager

The `scripts/load-config.sh` script provides a complete interface for configuration management:

```bash
# View all variables and their current values
./scripts/load-config.sh list

# Get a specific variable value
./scripts/load-config.sh get VERSION

# Set a variable (creates backup automatically)
./scripts/load-config.sh set L4T_VERSION r36.3.0

# Validate entire configuration
./scripts/load-config.sh validate

# Generate .env file for external tools
./scripts/load-config.sh generate-env
```

## 🏗️ Template-Based Generation

The system uses templates to generate actual configuration files from the centralized variables:

### Dockerfile Generation
```bash
# Template: docker/Dockerfile.jetson-builder.template
# Contains: FROM {{L4T_BASE_IMAGE}}, ENV {{VARIABLE_NAME}}=value

# Generate actual Dockerfile:
./scripts/generate-dockerfile.sh

# Auto-generated: docker/Dockerfile.jetson-builder (never edit manually)
```

### Automatic Integration
All build scripts automatically load the centralized configuration:
- `scripts/docker-build.sh` - Docker image building
- `scripts/create-docker-bundle.sh` - RAUC bundle creation
- `scripts/manage-version.sh` - Version management
- CI/CD workflows - Automated deployments

## 🔄 Configuration Workflow

### 1. Update Variables
```bash
# Option A: Direct editing
nano config/variables.conf

# Option B: Using config manager
./scripts/load-config.sh set VARIABLE_NAME new_value
```

### 2. Automatic Propagation
- Variables are validated on change
- Backup created automatically
- Templates regenerated as needed
- Build scripts use updated values

### 3. Build Process
```bash
# Everything uses centralized config automatically
./scripts/docker-build.sh      # Uses config/variables.conf
./scripts/create-bundle.sh     # Uses config/variables.conf
```

## 📊 Configuration Validation

Built-in validation ensures configuration integrity:

```bash
# Check entire configuration
./scripts/load-config.sh validate

# Validation includes:
# ✓ Required variables present
# ✓ Version format compliance
# ✓ Platform compatibility
# ✓ File path validity
# ✓ Boolean value formats
```

## 🔧 Common Configuration Tasks

### Update NVIDIA L4T Version
```bash
./scripts/load-config.sh set L4T_VERSION r36.3.0
./scripts/load-config.sh set L4T_BASE_IMAGE nvcr.io/nvidia/l4t-base:r36.3.0
./scripts/load-config.sh set CUDA_VERSION 12.3
./scripts/load-config.sh set TENSORRT_VERSION 10.1
./scripts/load-config.sh set JETPACK_VERSION 6.1
```

### Change Target Platform
```bash
./scripts/load-config.sh set TARGET_PLATFORM jetson-agx-orin
./scripts/load-config.sh set RAUC_COMPATIBLE jetson-agx-orin
./scripts/load-config.sh set BUNDLE_NAME_PATTERN "homie-os-agx-{version}.raucb"
```

### Enable/Disable Features
```bash
./scripts/load-config.sh set PUSH_IMAGE true
./scripts/load-config.sh set CREATE_BUNDLE false
./scripts/load-config.sh set SIGN_BUNDLE true
./scripts/load-config.sh set DEBUG_MODE false
```

## 📚 Documentation

- **[Configuration Variables](configuration-variables.md)** - Complete variable reference
- **[Quick Reference](quick-reference.md)** - Common configuration commands
- **[API Documentation](api.md)** - Build script APIs

## 🎉 Benefits

### Before: Distributed Configuration
- Variables scattered across multiple files
- Manual synchronization required
- Inconsistency prone
- Difficult to track changes

### After: Centralized Configuration
- ✅ Single source of truth
- ✅ Automatic synchronization
- ✅ Built-in validation
- ✅ Change tracking with backups
- ✅ Template-based generation
- ✅ Configuration management API

## 🚀 Getting Started

1. **View current configuration:**
   ```bash
   ./scripts/load-config.sh list
   ```

2. **Make a change:**
   ```bash
   ./scripts/load-config.sh set VERSION 1.0.0-beta.2
   ```

3. **Validate configuration:**
   ```bash
   ./scripts/load-config.sh validate
   ```

4. **Build with new configuration:**
   ```bash
   ./scripts/docker-build.sh
   ```

The centralized configuration system ensures your changes are automatically applied throughout the entire build pipeline! 🎯
