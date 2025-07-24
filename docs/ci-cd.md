# Homie OS CI/CD Documentation

## 🚀 Automated Build and Release Process

This repository includes a comprehensive CI/CD pipeline that automatically builds and publishes Homie OS RAUC bundles for NVIDIA Jetson devices.

## 📋 Workflow Overview

### Build Triggers
- **Push to main/develop**: Creates alpha builds
- **Git tags (v*)**: Creates release builds  
- **Manual dispatch**: Custom version builds
- **Pull requests**: Validation builds (no release)

### Build Process
1. **Version Generation**: Automatic or manual version assignment
2. **Docker Build**: Cross-compilation for ARM64/Jetson
3. **Bundle Creation**: RAUC bundle with rootfs
4. **Registry Push**: Docker image to GitHub Container Registry
5. **Release Creation**: GitHub release with artifacts
6. **Notification**: Build status reporting

## 🎯 Version Management

### Automatic Versioning
- **Alpha**: `0.1.0-alpha.YYYYMMDD.shortsha`
- **Beta**: `0.1.0-beta.YYYYMMDD.shortsha`
- **RC**: `0.1.0-rc.YYYYMMDD.shortsha`
- **Release**: `0.1.0`

### Manual Version Control
```bash
# Create alpha version
./scripts/manage-version.sh --type alpha

# Bump minor version and create beta
./scripts/manage-version.sh --type beta --bump minor

# Create release version
./scripts/manage-version.sh --type release --bump patch

# Dry run (see what would happen)
./scripts/manage-version.sh --type rc --dry-run
```

## 🛠️ Local Development

### Test Build Locally
```bash
# Run complete local build test
./scripts/test-local-build.sh

# Manual build with specific version
./scripts/docker-build.sh --version 0.1.0-test --no-bundle
./scripts/create-docker-bundle.sh build/rootfs 0.1.0-test build false
```

### Prerequisites
- Docker with Buildx support
- RAUC tools (`apt install rauc`)
- OpenSSL for certificate generation

## 📦 Artifacts

### Build Outputs
- **RAUC Bundle**: `homie-os-jetson-{version}.raucb`
- **Root Filesystem**: `rootfs.ext4`
- **Docker Image**: `ghcr.io/{owner}/homie-os:{version}`
- **Build Report**: `build-report-{version}.json`
- **Bundle Metadata**: `bundle-metadata.json`

### Download Locations
- **GitHub Releases**: Pre-built bundles and metadata
- **Container Registry**: Docker images for development
- **Build Artifacts**: Temporary storage (30 days)

## 🔄 Release Process

### Alpha Release (Automatic)
```bash
git push origin main
# Triggers: alpha build → GitHub pre-release
```

### Beta Release (Manual)
```bash
./scripts/manage-version.sh --type beta --bump minor
git push origin main --tags
# Triggers: beta build → GitHub pre-release
```

### Production Release (Manual)
```bash
./scripts/manage-version.sh --type release --bump patch
git push origin main --tags
# Triggers: release build → GitHub release
```

### Custom Build (Manual Workflow)
```bash
# Via GitHub CLI
gh workflow run build-bundle.yml \
  -f version=1.0.0-custom \
  -f release_type=alpha

# Via GitHub UI
# Actions → Build and Publish Homie OS Bundle → Run workflow
```

## 🎯 Target Platform

- **Architecture**: ARM64
- **Device**: NVIDIA Jetson Orin Nano
- **Base Image**: L4T R36.2.0
- **JetPack**: 6.0
- **Update System**: RAUC

## 🔐 Security

### Certificates
- **Development**: Auto-generated test certificates
- **Production**: Store real certificates in GitHub Secrets:
  - `RAUC_CERT_PEM`: RAUC signing certificate
  - `RAUC_KEY_PEM`: RAUC signing private key

### Signing Process
```bash
# Development (unsigned)
SIGN_BUNDLE=false

# Production (signed)
SIGN_BUNDLE=true
```

## 📊 Monitoring

### Build Status
- **GitHub Actions**: Real-time build logs
- **Container Registry**: Image deployment status
- **Releases**: Published artifact tracking

### Verification
```bash
# Verify bundle integrity
rauc info homie-os-jetson-{version}.raucb

# Check Docker image
docker run --rm ghcr.io/{owner}/homie-os:{version} cat /etc/homie-version

# Validate filesystem
file rootfs.ext4
```

## 🐛 Troubleshooting

### Common Issues
1. **Build Failures**: Check Docker daemon and Buildx setup
2. **Bundle Creation**: Verify RAUC installation
3. **Version Conflicts**: Ensure unique version numbers
4. **Certificate Issues**: Check certificate paths and permissions

### Debug Commands
```bash
# Test Docker cross-compilation
docker buildx ls
docker buildx inspect

# Verify RAUC installation
rauc --version

# Check build environment
./scripts/docker-build.sh --version test-debug --no-bundle
```

## 📚 References

- [RAUC Documentation](https://rauc.readthedocs.io/)
- [Docker Buildx Guide](https://docs.docker.com/buildx/)
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [NVIDIA L4T Documentation](https://docs.nvidia.com/jetson/archives/r36.2/DeveloperGuide/text/IN/QuickStart.html)
