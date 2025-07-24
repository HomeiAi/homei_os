# RAUC Update Workflow Guide
> Complete guide to understanding and implementing RAUC-based A/B updates for Homie OS

## 🔄 Understanding RAUC (Robust Auto-Update Controller)

RAUC is an enterprise-grade update framework that implements **A/B partition updates** for embedded Linux systems. It provides atomic, fail-safe updates with automatic rollback capabilities.

### Core Concepts

#### **A/B Partition System**
- **Dual Root Filesystems**: Your system has two identical root partitions (Slot A & Slot B)
- **Active/Inactive**: One partition runs the current system, the other receives updates
- **Atomic Switching**: U-Boot switches between partitions during reboot
- **Rollback Protection**: Automatic rollback if the new system fails to boot

#### **Update Process Flow**
```
Current System (Slot A) → Update Slot B → Reboot → Boot from Slot B
     ↓ (if boot fails)
Automatic Rollback to Slot A
```

#### **Partition Layout Example**
```
┌─────────────────────────────────────────────────────────────┐
│                    SD Card (32GB example)                   │
├─────────────────┬─────────────────┬─────────────────────────┤
│   Slot A        │   Slot B        │     User Data           │
│  /dev/mmcblk0p1 │  /dev/mmcblk0p2 │    /dev/mmcblk0p3       │
│   (rootfs_a)    │   (rootfs_b)    │    (userdata)           │
│   8GB - ext4    │   8GB - ext4    │   16GB - ext4           │
└─────────────────┴─────────────────┴─────────────────────────┘
```

## 📦 Bundle Creation Strategies

### **Cross-Platform Building (Recommended)**

**You do NOT need the same hardware to create RAUC bundles!**

#### **Why Cross-Platform Works:**
- ✅ **Faster builds** - Use powerful development machines
- ✅ **CI/CD friendly** - Works in GitHub Actions, Jenkins, etc.
- ✅ **Reproducible** - Same environment every time
- ✅ **No target disruption** - Don't interfere with running systems
- ✅ **Scalable** - Build for multiple target types simultaneously

#### **Development Machine Bundle Creation:**
```bash
# On your development machine (any Linux system)
cd /path/to/homie_os

# Development bundle (unsigned, faster)
sudo ./scripts/create-update-bundle.sh --dev --verbose

# Production bundle (signed)
sudo ./scripts/create-update-bundle.sh --version "1.2.3"

# Custom configuration
sudo ./scripts/create-update-bundle.sh \
  --version "1.2.3" \
  --description "Security update with new AI models" \
  --include-docker \
  --output /data/releases
```

### **What's Inside a RAUC Bundle**

A RAUC bundle (`.raucb` file) contains:

1. **Filesystem Image** (`rootfs.ext4`)
   - Complete root filesystem as ext4 image
   - Optimized and compressed
   - Contains all system files, applications, configurations

2. **Manifest** (`manifest.raucm`)
   - Metadata: version, description, build date
   - Checksums (SHA256) for verification
   - Installation instructions
   - Compatibility information

3. **Digital Signatures** (Production bundles)
   - Cryptographic verification
   - Certificate chain validation
   - Tamper detection

4. **Update Hooks** (Optional)
   - Pre/post installation scripts
   - Service management
   - Custom update logic

```
bundle.raucb
├── rootfs.ext4          # Filesystem image
├── manifest.raucm      # Bundle metadata
├── hook.sh             # Update scripts (optional)
└── [signature data]    # Digital signatures
```

## 🌐 GitHub-Based Update Distribution

### **GitHub Releases Strategy**

GitHub Releases provide an excellent platform for distributing RAUC bundles:

#### **Automated CI/CD Pipeline**

Create `.github/workflows/build-release.yml`:

```yaml
name: Build and Release Homie OS Update

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version'
        required: true
        default: '1.0.0'

jobs:
  build-update:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout Repository
      uses: actions/checkout@v4
      
    - name: Install Dependencies
      run: |
        sudo apt update
        sudo apt install -y \
          build-essential \
          rauc \
          e2fsprogs \
          rsync \
          openssl
    
    - name: Setup RAUC Configuration
      run: |
        sudo ./scripts/create-update-bundle.sh --fix-config
    
    - name: Build Update Bundle
      run: |
        VERSION="${{ github.event.inputs.version || github.ref_name }}"
        sudo ./scripts/create-update-bundle.sh \
          --version "${VERSION#v}" \
          --description "Homie OS Release ${VERSION#v}" \
          --output "./dist"
    
    - name: Generate Release Notes
      run: |
        cat > release-notes.md << EOF
        ## Homie OS Update ${{ github.ref_name }}
        
        ### 🚀 Installation Instructions
        
        **Direct Installation:**
        \`\`\`bash
        # Download and install
        wget https://github.com/Homie-Ai-project/homie_os/releases/download/${{ github.ref_name }}/homie-os-${{ github.ref_name #v }}.raucb
        sudo rauc install homie-os-${{ github.ref_name #v }}.raucb
        sudo reboot
        \`\`\`
        
        **Automatic Update:**
        \`\`\`bash
        # Enable automatic updates
        sudo systemctl enable homie-update-checker.timer
        sudo systemctl start homie-update-checker.timer
        \`\`\`
        
        ### ✅ Verification
        After installation, verify the update:
        \`\`\`bash
        rauc status
        cat /etc/homie-version
        \`\`\`
        
        ### 🔄 Rollback (if needed)
        \`\`\`bash
        sudo rauc mark bad
        sudo reboot
        \`\`\`
        EOF
    
    - name: Create GitHub Release
      uses: softprops/action-gh-release@v1
      with:
        files: |
          dist/*.raucb
          dist/*.tar.gz
        name: "Homie OS ${{ github.ref_name }}"
        body_path: release-notes.md
        draft: false
        prerelease: false
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### **Release Asset Structure**

Your GitHub releases will contain:

```
Release v1.2.3
├── homie-os-1.2.3.raucb          # Signed production bundle
├── homie-os-1.2.3-dev.tar.gz     # Development bundle (if needed)
├── homie-os-1.2.3.sha256         # Checksums
└── install-instructions.md       # Installation guide
```

## 🎯 Target System Update Workflow

### **Initial Setup on Target (Jetson Nano)**

```bash
# 1. Clone the repository
git clone https://github.com/Homie-Ai-project/homie_os.git
cd homie_os

# 2. Check system compatibility
sudo ./scripts/setup-rauc-jetson.sh --check-setup

# 3. Set up A/B partitions (DESTRUCTIVE - backs up first)
sudo ./scripts/setup-rauc-jetson.sh

# 4. Verify RAUC configuration
sudo rauc status
```

### **Manual Update Process**

#### **Method 1: Direct from GitHub Releases**
```bash
# Get latest release
LATEST_VERSION=$(curl -s https://api.github.com/repos/Homie-Ai-project/homie_os/releases/latest | jq -r '.tag_name')

# Download bundle
wget "https://github.com/Homie-Ai-project/homie_os/releases/download/$LATEST_VERSION/homie-os-${LATEST_VERSION#v}.raucb"

# Install update
sudo rauc install "homie-os-${LATEST_VERSION#v}.raucb"

# Reboot to activate
sudo reboot
```

#### **Method 2: Local Bundle Installation**
```bash
# Install from local file
sudo rauc install /path/to/homie-os-v1.2.3.raucb

# Verify before reboot
rauc status

# Reboot when ready
sudo reboot
```

#### **Method 3: USB Installation**
```bash
# Mount USB drive
sudo mount /dev/sda1 /mnt

# Install from USB
sudo rauc install /mnt/homie-os-v1.2.3.raucb

# Unmount and reboot
sudo umount /mnt
sudo reboot
```

### **Automatic Update Service**

Create a fully automated update system:

#### **Update Client Script**
Create `/usr/local/bin/homie-update-client`:

```bash
#!/bin/bash
# Automatic update client for Homie OS

set -e

# Configuration
GITHUB_REPO="Homie-Ai-project/homie_os"
VERSION_FILE="/etc/homie-version"
UPDATE_LOCK="/var/lock/homie-update"
LOG_FILE="/var/log/homie-update.log"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
}

# Prevent concurrent updates
if [[ -f "$UPDATE_LOCK" ]]; then
    log "Update already in progress (lock file exists)"
    exit 0
fi

trap 'rm -f "$UPDATE_LOCK"' EXIT
touch "$UPDATE_LOCK"

check_for_updates() {
    log "Checking for updates..."
    
    # Get current version
    local current_version="unknown"
    if [[ -f "$VERSION_FILE" ]]; then
        current_version=$(cat "$VERSION_FILE")
    fi
    
    # Get latest release from GitHub API
    local api_response=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest")
    local latest_version=$(echo "$api_response" | jq -r '.tag_name' | sed 's/^v//')
    local download_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | endswith(".raucb")) | .browser_download_url')
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        error "No RAUC bundle found in latest release"
        return 1
    fi
    
    log "Current version: $current_version"
    log "Latest version: $latest_version"
    
    if [[ "$latest_version" != "$current_version" ]]; then
        log "New version available: $latest_version"
        install_update "$latest_version" "$download_url"
    else
        log "System is up to date"
    fi
}

install_update() {
    local version="$1"
    local download_url="$2"
    local bundle_file="/tmp/homie-update-$version.raucb"
    
    log "Downloading update $version..."
    if ! wget -O "$bundle_file" "$download_url"; then
        error "Failed to download update bundle"
        return 1
    fi
    
    # Verify bundle integrity
    log "Verifying bundle integrity..."
    if ! rauc info "$bundle_file" >/dev/null 2>&1; then
        error "Bundle verification failed"
        rm -f "$bundle_file"
        return 1
    fi
    
    # Stop critical services before update
    log "Stopping services for update..."
    systemctl stop docker 2>/dev/null || true
    systemctl stop homie-orchestrator 2>/dev/null || true
    
    # Install update
    log "Installing update $version..."
    if rauc install "$bundle_file"; then
        log "Update installed successfully"
        rm -f "$bundle_file"
        
        # Update version file
        echo "$version" > "$VERSION_FILE"
        
        # Schedule reboot
        log "Update completed. System will reboot in 60 seconds..."
        shutdown -r +1 "Homie OS update to $version completed - rebooting"
        
        # Send notification (optional)
        notify_update_complete "$version"
    else
        error "Update installation failed"
        rm -f "$bundle_file"
        
        # Restart stopped services
        systemctl start docker 2>/dev/null || true
        systemctl start homie-orchestrator 2>/dev/null || true
        return 1
    fi
}

notify_update_complete() {
    local version="$1"
    
    # Send notification via webhook, email, etc.
    # Example webhook notification:
    curl -X POST "https://your-webhook-url.com/notify" \
        -H "Content-Type: application/json" \
        -d "{\"message\": \"Homie OS updated to version $version\", \"hostname\": \"$(hostname)\"}" \
        2>/dev/null || true
}

# Main execution
main() {
    log "Starting Homie OS update check"
    
    # Check if RAUC is available
    if ! command -v rauc >/dev/null 2>&1; then
        error "RAUC not found"
        exit 1
    fi
    
    # Check network connectivity
    if ! ping -c 1 github.com >/dev/null 2>&1; then
        log "No network connectivity, skipping update check"
        exit 0
    fi
    
    # Check for updates
    check_for_updates
    
    log "Update check completed"
}

main "$@"
```

#### **Systemd Service Configuration**

Create `/etc/systemd/system/homie-update-checker.service`:

```ini
[Unit]
Description=Homie OS Update Checker
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/homie-update-client
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Create `/etc/systemd/system/homie-update-checker.timer`:

```ini
[Unit]
Description=Check for Homie OS updates daily
Requires=homie-update-checker.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600
AccuracySec=1h

[Install]
WantedBy=timers.target
```

#### **Enable Automatic Updates**
```bash
# Make update client executable
sudo chmod +x /usr/local/bin/homie-update-client

# Enable and start the timer
sudo systemctl enable homie-update-checker.timer
sudo systemctl start homie-update-checker.timer

# Check status
sudo systemctl status homie-update-checker.timer

# View logs
sudo journalctl -u homie-update-checker.service -f
```

## 🛡️ Security & Verification

### **Digital Signatures**

RAUC uses X.509 certificates for bundle signing:

#### **Production Certificate Management**
```bash
# Generate CA certificate (keep private key secure!)
openssl req -x509 -newkey rsa:4096 -keyout ca-key.pem -out ca-cert.pem -days 3650 -nodes \
    -subj "/C=US/O=Homie OS/CN=Homie OS Root CA"

# Generate signing certificate
openssl req -new -newkey rsa:4096 -keyout signing-key.pem -out signing-req.pem -nodes \
    -subj "/C=US/O=Homie OS/CN=Homie OS Release Signing"

openssl x509 -req -in signing-req.pem -CA ca-cert.pem -CAkey ca-key.pem \
    -out signing-cert.pem -days 365 \
    -extensions v3_req -extfile <(printf "[v3_req]\nkeyUsage=digitalSignature\nextendedKeyUsage=codeSigning")

# Distribute CA certificate to target systems
sudo cp ca-cert.pem /etc/rauc/keyring.pem
```

#### **Bundle Verification Process**
```bash
# Verify bundle signature
rauc info bundle.raucb

# Check certificate chain
openssl verify -CAfile /etc/rauc/keyring.pem bundle-cert.pem

# Manual signature verification
rauc verify bundle.raucb
```

### **Target System Verification**

```bash
# Check current slot and version
rauc status

# Verify system integrity
rauc mark good  # Mark current slot as good

# Check boot status
rauc info mark

# View update history
journalctl -u rauc -n 50
```

## 🚀 Complete Workflow Summary

### **Development → Production Pipeline**

1. **Development Phase**
   ```bash
   # Local development
   git commit -m "Add new features"
   git push origin feature-branch
   
   # Create test bundle
   sudo ./scripts/create-update-bundle.sh --dev --version "test-$(date +%s)"
   ```

2. **CI/CD Pipeline**
   ```bash
   # Triggered by git tag
   git tag v1.2.3
   git push origin v1.2.3
   
   # GitHub Actions builds and releases bundle automatically
   ```

3. **Target System Update**
   ```bash
   # Automatic (if enabled)
   # Manual check: sudo systemctl start homie-update-checker.service
   
   # Manual installation
   sudo rauc install homie-os-1.2.3.raucb
   sudo reboot
   ```

4. **Verification & Rollback**
   ```bash
   # After reboot, verify
   rauc status
   cat /etc/homie-version
   
   # If issues occur, rollback
   sudo rauc mark bad
   sudo reboot  # Boots previous version
   ```

### **Recovery Scenarios**

#### **Failed Update Recovery**
```bash
# If update fails during installation
rauc status  # Check slot status

# Manual rollback
rauc mark bad
reboot

# Force boot from specific slot
# (via U-Boot console)
setenv rauc_slot a  # or 'b'
boot
```

#### **Corrupted System Recovery**
```bash
# Boot from USB/SD with recovery image
# Mount and repair filesystem
sudo mount /dev/mmcblk0p1 /mnt  # Mount good slot
sudo chroot /mnt /bin/bash       # Enter system

# Or restore from backup
sudo dd if=backup.img of=/dev/mmcblk0p1 bs=1M status=progress
```

## 📊 Best Practices

### **Bundle Creation**
- ✅ Use semantic versioning (1.2.3)
- ✅ Include detailed release notes
- ✅ Test bundles in staging environment
- ✅ Keep bundles under 1GB for faster downloads
- ✅ Sign all production bundles

### **Target System Management**
- ✅ Enable automatic updates for security patches
- ✅ Monitor update status and logs
- ✅ Maintain backup strategies
- ✅ Test rollback procedures regularly
- ✅ Document recovery processes

### **Security Considerations**
- ✅ Protect signing keys with hardware security modules
- ✅ Use separate certificates for development and production
- ✅ Implement certificate rotation policies
- ✅ Monitor for unauthorized bundle installations
- ✅ Verify bundle integrity before installation

This workflow provides enterprise-grade update capabilities with the convenience of GitHub hosting and the reliability of RAUC's A/B partition system! 🚀