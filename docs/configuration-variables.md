# Homie OS Configuration Variables Guide

This document provides a comprehensive overview of all configurable variables in the Homie OS project and how to manage them for subsequent versions.

## 📋 Table of Contents

1. [Centralized Configuration System](#centralized-configuration-system)
2. [Core Version Variables](#core-version-variables)
3. [Build Configuration](#build-configuration)
4. [Docker and Container Settings](#docker-and-container-settings)
5. [NVIDIA/Jetson Platform Variables](#nvidiajetson-platform-variables)
6. [RAUC Bundle Configuration](#rauc-bundle-configuration)
7. [CI/CD Pipeline Variables](#cicd-pipeline-variables)
8. [Security and Certificates](#security-and-certificates)
9. [Development Environment](#development-environment)
10. [How to Update Variables](#how-to-update-variables)
11. [Version Update Checklist](#version-update-checklist)

---

## 🎯 Centralized Configuration System

All Homie OS variables are now managed through a **single configuration file**: `config/variables.conf`

### Configuration Management Commands
```bash
# List all configuration variables
./scripts/load-config.sh list

# Get specific variable value
./scripts/load-config.sh get VERSION

# Set a variable to new value
./scripts/load-config.sh set L4T_VERSION r36.3.0

# Validate configuration
./scripts/load-config.sh validate

# Generate environment file
./scripts/load-config.sh generate-env
```

### How It Works
1. **Single Source**: All variables defined in `config/variables.conf`
2. **Auto-Loading**: Scripts automatically load configuration
3. **Template System**: Dockerfile generated from template with current values
4. **Validation**: Built-in validation for format and dependencies
5. **Backup**: Automatic backups when making changes

---

## 🎯 Core Version Variables

### Primary Version Control
| Variable | Current Value | Description |
|----------|---------------|-------------|
| `VERSION` | `0.1.0-alpha.20250724.initial` | Primary version identifier |
| `HOMIE_BRANCH` | `main` | Git branch being built |

**Location**: `config/variables.conf`
**Management**: Use `./scripts/load-config.sh set VERSION <value>` or version management script

### Version Generation Logic
```bash
# Alpha/Beta/RC versions
VERSION="${MAJOR}.${MINOR}.${PATCH}-${TYPE}.${DATE}.${SHORT_SHA}"
# Example: 0.1.0-alpha.20250724.d18ffbc

# Release versions  
VERSION="${MAJOR}.${MINOR}.${PATCH}"
# Example: 1.0.0
```

---

## 🔧 Build Configuration

### Build Directories and Paths
| Variable | Location | Default Value | Description |
|----------|----------|---------------|-------------|
| `PROJECT_ROOT` | `scripts/docker-build.sh` | `$(dirname "$SCRIPT_DIR")` | Root project directory |
| `DOCKER_DIR` | `scripts/docker-build.sh` | `$PROJECT_ROOT/docker` | Docker files location |
| `BUILD_DIR` | `scripts/docker-build.sh` | `$PROJECT_ROOT/build` | Build output directory |
| `OUTPUT_DIR` | `scripts/create-docker-bundle.sh` | `./build` | Bundle output directory |

### Build Behavior Controls
| Variable | Location | Default Value | Description |
|----------|----------|---------------|-------------|
| `PUSH_IMAGE` | `scripts/docker-build.sh` | `false` | Whether to push to registry |
| `CREATE_BUNDLE` | `scripts/docker-build.sh` | `true` | Whether to create RAUC bundle |
| `SIGN_BUNDLE` | `scripts/create-docker-bundle.sh` | `false` | Whether to sign RAUC bundle |

---

## 🐳 Docker and Container Settings

### Base Images and Tags
| Variable | Location | Current Value | Description |
|----------|----------|---------------|-------------|
| `FROM` | `docker/Dockerfile.jetson-builder` | `nvcr.io/nvidia/l4t-base:r36.2.0` | NVIDIA L4T base image |
| `IMAGE_NAME` | CI/CD, Scripts | `homie-os:jetson-{version}` | Built image naming pattern |
| `REGISTRY` | CI/CD | `ghcr.io` | Container registry URL |

### Container Environment Variables
| Variable | Location | Current Value | Description |
|----------|----------|---------------|-------------|
| `DEBIAN_FRONTEND` | Dockerfile | `noninteractive` | Debian package installation mode |
| `CUDA_VERSION` | Dockerfile | `12.2` | CUDA toolkit version |
| `TRT_VERSION` | Dockerfile | `10.0` | TensorRT version |
| `JETPACK_VERSION` | Dockerfile | `6.0` | JetPack version |

### Docker Build Arguments
| Variable | Location | Default | Description |
|----------|----------|---------|-------------|
| `VERSION` | Dockerfile | `unknown` | Build version argument |
| `BUILD_DATE` | Dockerfile | Auto-generated | Build timestamp |
| `HOMIE_BRANCH` | Dockerfile | `main` | Source branch |

---

## 🚀 NVIDIA/Jetson Platform Variables

### L4T (Linux for Tegra) Configuration
| Variable | Location | Current Value | Update Trigger |
|----------|----------|---------------|----------------|
| `L4T_VERSION` | Dockerfile, Docs | `r36.2.0` | New L4T release |
| `JETPACK_VERSION` | Dockerfile, Docs | `6.0` | New JetPack release |
| `CUDA_VERSION` | Dockerfile | `12.2` | CUDA update |
| `TRT_VERSION` | Dockerfile | `10.0` | TensorRT update |

### Target Platform
| Variable | Location | Current Value | Description |
|----------|----------|---------------|-------------|
| `ARCHITECTURE` | CI/CD, Scripts | `arm64` | Target CPU architecture |
| `PLATFORM` | CI/CD, Scripts | `jetson-orin-nano` | Target device platform |
| `COMPATIBLE` | RAUC manifest | `jetson-orin-nano` | RAUC compatibility string |

### How to Update for New L4T Release:
1. Check [NVIDIA Container Registry](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/l4t-base) for new tags
2. Update `FROM` line in `docker/Dockerfile.jetson-builder`
3. Update version variables in build metadata
4. Update documentation references
5. Test build compatibility

---

## 📦 RAUC Bundle Configuration

### Bundle Metadata
| Variable | Location | Current Value | Description |
|----------|----------|---------------|-------------|
| `compatible` | RAUC manifest | `jetson-orin-nano` | Device compatibility |
| `format` | RAUC manifest | `plain` | Bundle format type |
| `verity` | RAUC manifest | `true` | Enable dm-verity |

### Bundle Naming
| Variable | Location | Pattern | Description |
|----------|----------|---------|-------------|
| `BUNDLE_NAME` | `scripts/create-docker-bundle.sh` | `homie-os-jetson-{version}.raucb` | Bundle filename pattern |
| `BUNDLE_DIR` | `scripts/create-docker-bundle.sh` | `{output}/bundle-{version}` | Temporary bundle directory |

### Certificate Paths
| Variable | Location | Default Value | Description |
|----------|----------|---------------|-------------|
| `RAUC_CERT_PATH` | CI/CD | `/certs/cert.pem` | RAUC signing certificate |
| `RAUC_KEY_PATH` | CI/CD | `/certs/key.pem` | RAUC signing private key |

---

## 🔄 CI/CD Pipeline Variables

### GitHub Actions Environment
| Variable | Location | Default Value | Description |
|----------|----------|---------------|-------------|
| `REGISTRY` | `.github/workflows/build-bundle.yml` | `ghcr.io` | Container registry |
| `IMAGE_NAME` | CI/CD | `${{ github.repository }}/homie-os` | Image name pattern |

### Workflow Triggers
| Variable | Location | Values | Description |
|----------|----------|--------|-------------|
| `CHANNEL` | Docker install | `stable\|test` | Docker installation channel |
| `release_type` | CI/CD | `alpha\|beta\|rc\|release` | Release type for builds |

### Build Matrix Variables
| Variable | Location | Current Value | Description |
|----------|----------|---------------|-------------|
| `platforms` | CI/CD | `linux/arm64` | Target build platforms |
| `retention-days` | CI/CD | `30` | Artifact retention period |

---

## 🔐 Security and Certificates

### Certificate Configuration
| Variable | Location | Type | Description |
|----------|----------|------|-------------|
| `RAUC_CERT_PEM` | GitHub Secrets | Secret | Production RAUC certificate |
| `RAUC_KEY_PEM` | GitHub Secrets | Secret | Production RAUC private key |
| `GITHUB_TOKEN` | GitHub Actions | Auto | Repository access token |

### Signing Configuration
| Variable | Location | Default | Description |
|----------|----------|---------|-------------|
| `SIGN_BUNDLE` | Scripts | `false` | Enable bundle signing |
| `cert_path` | RAUC config | `/certs/cert.pem` | Certificate file path |
| `key_path` | RAUC config | `/certs/key.pem` | Private key file path |

---

## 💻 Development Environment

### Local Development Variables
| Variable | Location | Default | Description |
|----------|----------|---------|-------------|
| `DRY_RUN` | Version scripts | `false` | Preview mode without changes |
| `BUMP_TYPE` | Version scripts | None | Version increment type |
| `RELEASE_TYPE` | Version scripts | `alpha` | Release type for generation |

### Docker Environment
| Variable | Location | Default | Description |
|----------|----------|---------|-------------|
| `DOCKER_BUILDKIT` | Environment | `1` | Enable BuildKit |
| `BUILDX_BUILDER` | Environment | `multiarch` | Buildx builder name |

---

## 🔄 How to Update Variables

### 1. Using Configuration Manager (Recommended)

#### Update Single Variable
```bash
# Update L4T version
./scripts/load-config.sh set L4T_VERSION r36.3.0
./scripts/load-config.sh set L4T_BASE_IMAGE nvcr.io/nvidia/l4t-base:r36.3.0

# Update CUDA version
./scripts/load-config.sh set CUDA_VERSION 12.3

# Update project version
./scripts/load-config.sh set VERSION 1.0.0-beta.1
```

#### Bulk Updates via Config File
```bash
# Edit the configuration file directly
nano config/variables.conf

# Validate changes
./scripts/load-config.sh validate

# Generate updated Dockerfile
./scripts/generate-dockerfile.sh
```

### 2. Platform Updates

#### Update L4T Base Image
1. **Check NVIDIA Registry**:
   ```bash
   # Check available tags
   curl -s https://nvcr.io/v2/nvidia/l4t-base/tags/list | jq '.tags[]' | sort
   ```

2. **Update Configuration**:
   ```bash
   # Update L4T version and base image
   ./scripts/load-config.sh set L4T_VERSION r36.3.0
   ./scripts/load-config.sh set L4T_BASE_IMAGE nvcr.io/nvidia/l4t-base:r36.3.0
   
   # Update related versions
   ./scripts/load-config.sh set CUDA_VERSION 12.3
   ./scripts/load-config.sh set TENSORRT_VERSION 10.1
   ./scripts/load-config.sh set JETPACK_VERSION 6.1
   ```

3. **Generate and Test**:
   ```bash
   # Generate new Dockerfile
   ./scripts/generate-dockerfile.sh
   
   # Test build
   ./scripts/test-local-build.sh
   ```

### 3. Version Management

#### Using Version Management Script
```bash
# Create new version with automatic updates
./scripts/manage-version.sh --type beta --bump minor

# This updates VERSION in config/variables.conf automatically
```

#### Manual Version Update
```bash
# Set specific version
./scripts/load-config.sh set VERSION 1.2.0-rc.1

# Update VERSION file as well (for compatibility)
echo "1.2.0-rc.1" > VERSION
```

### 3. Bundle Configuration Updates

#### Update RAUC Compatibility
```bash
# scripts/create-docker-bundle.sh
cat > "$BUNDLE_DIR/manifest.raucm" << EOF
[update]
compatible=jetson-agx-orin    # NEW DEVICE TYPE
version=$VERSION
EOF
```

#### Update Bundle Naming
```bash
# For new device support
BUNDLE_NAME="homie-os-agx-$VERSION.raucb"  # NEW DEVICE PREFIX
```

### 4. CI/CD Configuration Updates

#### Update Build Matrix
```yaml
# .github/workflows/build-bundle.yml
strategy:
  matrix:
    platform: 
      - linux/arm64
      - linux/arm64/v8    # ADD NEW VARIANTS
```

#### Update Container Registry
```yaml
env:
  REGISTRY: myregistry.io    # NEW REGISTRY
  IMAGE_NAME: myorg/homie-os # NEW IMAGE NAME
```

---

## ✅ Version Update Checklist

### For L4T/JetPack Updates
- [ ] Check NVIDIA Container Registry for new L4T tags
- [ ] Update `FROM` line in `docker/Dockerfile.jetson-builder`
- [ ] Update `CUDA_VERSION`, `TRT_VERSION`, `JETPACK_VERSION`
- [ ] Update build info generation in scripts
- [ ] Update documentation references
- [ ] Test build with new base image
- [ ] Verify container functionality
- [ ] Update CI/CD if needed

### For Device Platform Updates  
- [ ] Update RAUC `compatible` field
- [ ] Update bundle naming patterns
- [ ] Update platform documentation
- [ ] Test on target hardware
- [ ] Update device-specific configurations

### For Release Version Bumps
- [ ] Update `VERSION` file or use version script
- [ ] Tag git repository
- [ ] Trigger CI/CD build
- [ ] Verify build artifacts
- [ ] Test deployment on target
- [ ] Create GitHub release
- [ ] Update documentation

### For Security Updates
- [ ] Rotate RAUC certificates if needed
- [ ] Update GitHub Secrets
- [ ] Test signed bundle creation
- [ ] Verify signature validation
- [ ] Update security documentation

---

## 📚 Variable Reference Files

### Key Configuration Files
| File | Purpose | Key Variables |
|------|---------|---------------|
| `config/variables.conf` | **PRIMARY CONFIG** - All variables | All configuration variables |
| `scripts/load-config.sh` | Configuration management | Load, set, validate |
| `docker/Dockerfile.jetson-builder.template` | Container build template | FROM, ENV variables |
| `docker/Dockerfile.jetson-builder` | Generated container build | Auto-generated from template |
| `scripts/docker-build.sh` | Build orchestration | Uses config variables |
| `scripts/create-docker-bundle.sh` | Bundle creation | Uses config variables |
| `.github/workflows/build-bundle.yml` | CI/CD pipeline | Registry, image names |
| `scripts/manage-version.sh` | Version management | Version logic |

### Documentation Files
| File | Purpose |
|------|---------|
| `docs/ci-cd.md` | CI/CD process documentation |
| `docs/docker-cross-build.md` | Docker build documentation |
| `README.md` | Project overview |

---

## 🔍 Variable Dependencies

### Configuration Chain
```
config/variables.conf → load-config.sh → Scripts → Dockerfile template → Generated Dockerfile
```

### Version Chain
```
VERSION (config) → HOMIE_VERSION → Docker tags → Bundle names → Release artifacts
```

### Platform Chain  
```
L4T_BASE_IMAGE (config) → CUDA/TensorRT versions → JetPack version → Device compatibility
```

### Build Chain
```
Git trigger → CI/CD → Load config → Generate Dockerfile → Docker build → Bundle creation → Registry push → Release
```

---

## 🚨 Important Notes

1. **Always test builds** after updating platform variables
2. **Coordinate L4T updates** with NVIDIA release schedules  
3. **Backup certificates** before rotation
4. **Document breaking changes** in release notes
5. **Test on actual hardware** before production releases
6. **Keep documentation in sync** with variable changes

This configuration system provides flexibility while maintaining consistency across the Homie OS build and deployment pipeline.
