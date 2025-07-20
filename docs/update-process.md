# Update Process

Complete guide to creating, testing, and deploying updates with Homie OS RAUC system.

## Overview

The update process in Homie OS follows these key principles:
- **Atomic**: Complete success or complete rollback
- **Signed**: Cryptographically verified updates
- **Tested**: Automatic health verification
- **Safe**: Previous version always available

## Update Workflow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Prepare   │───▶│   Create    │───▶│   Deploy    │───▶│   Verify    │
│   System    │    │   Bundle    │    │   Update    │    │   Health    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

## Creating Update Bundles

### Method 1: Automated Script

Use the provided script for streamlined bundle creation:

```bash
# Create update bundle from current system
./scripts/create-update-bundle.sh

# Create bundle with custom version
./scripts/create-update-bundle.sh --version "2.1.0"

# Create bundle with specific components
./scripts/create-update-bundle.sh --include-docker --exclude-cache
```

### Method 2: Manual Bundle Creation

For custom requirements or understanding the process:

#### Step 1: Prepare Root Filesystem

```bash
# Create working directories
sudo mkdir -p /tmp/rootfs_build /tmp/bundle

# Copy current system (customize exclusions as needed)
sudo rsync -aHAXx \
  --exclude=/proc \
  --exclude=/sys \
  --exclude=/dev \
  --exclude=/tmp \
  --exclude=/media \
  --exclude=/mnt \
  --exclude=/data \
  --exclude=/var/cache \
  --exclude=/var/log/* \
  / /tmp/rootfs_build/

# Clean up sensitive data
sudo rm -f /tmp/rootfs_build/etc/ssh/ssh_host_*
sudo rm -f /tmp/rootfs_build/root/.bash_history
sudo rm -rf /tmp/rootfs_build/home/*/.bash_history
```

#### Step 2: Create Filesystem Image

```bash
# Create ext4 filesystem image (adjust size as needed)
sudo mke2fs -t ext4 -d /tmp/rootfs_build /tmp/bundle/rootfs.ext4 7G

# Optimize filesystem
sudo e2fsck -f /tmp/bundle/rootfs.ext4
sudo resize2fs -M /tmp/bundle/rootfs.ext4
```

#### Step 3: Create Bundle Manifest

```bash
cat > /tmp/bundle/manifest.raucm << EOF
[update]
compatible=jetson-nano
version=$(date +%Y%m%d-%H%M%S)
description=Homie OS Update $(date +"%Y-%m-%d %H:%M:%S")

[bundle]
format=verity

[image.rootfs]
filename=rootfs.ext4
size=$(stat -c%s /tmp/bundle/rootfs.ext4)
sha256=$(sha256sum /tmp/bundle/rootfs.ext4 | cut -d' ' -f1)

[hooks]
filename=hook.sh
EOF
```

#### Step 4: Create Update Hook (Optional)

```bash
cat > /tmp/bundle/hook.sh << 'EOF'
#!/bin/bash

case "$1" in
    slot-post-install)
        # Post-installation tasks
        echo "Update installed successfully"
        ;;
    slot-pre-install)
        # Pre-installation tasks
        echo "Preparing for update installation"
        ;;
esac
EOF

chmod +x /tmp/bundle/hook.sh
```

#### Step 5: Create Signed Bundle

```bash
# Create RAUC bundle
sudo rauc bundle \
  --cert=/etc/rauc/certs/dev-cert.pem \
  --key=/etc/rauc/certs/dev-key.pem \
  /tmp/bundle \
  /tmp/homie-os-update-$(date +%Y%m%d-%H%M%S).raucb
```

## Deploying Updates

### Local Installation

```bash
# Install update bundle
sudo rauc install /path/to/update.raucb

# Check installation status
sudo rauc status

# Reboot to activate new slot
sudo reboot
```

### Remote Installation

#### Using curl
```bash
# Download and install from remote server
curl -L https://updates.example.com/latest.raucb | sudo rauc install -

# Or download first, then install
curl -L -o update.raucb https://updates.example.com/latest.raucb
sudo rauc install update.raucb
```

#### Using RAUC HTTP Interface

Enable RAUC's built-in HTTP interface:

```bash
# Start RAUC service with HTTP interface
sudo rauc service --port=8080 &

# Install via HTTP API
curl -X POST -F "file=@update.raucb" http://localhost:8080/install
```

## Update Verification

### Automatic Health Checks

RAUC automatically performs health checks after installation:

1. **Boot Success**: System boots without errors
2. **Service Status**: Critical services are running
3. **Health Timeout**: System remains stable for specified period

### Custom Health Checks

Create custom health verification scripts:

```bash
# Create health check script
sudo tee /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash

# Check critical services
systemctl is-active docker || exit 1
systemctl is-active rauc || exit 1

# Check network connectivity
ping -c 1 8.8.8.8 || exit 1

# Check application health
curl -f http://localhost:8080/health || exit 1

echo "System health check passed"
exit 0
EOF

sudo chmod +x /usr/local/bin/health-check.sh

# Configure RAUC to use health check
sudo tee -a /etc/rauc/system.conf << 'EOF'

[system.health]
check-command=/usr/local/bin/health-check.sh
timeout=300
EOF
```

## Update States and Rollback

### Update States

1. **Active**: Currently running slot
2. **Inactive**: Standby slot (previous version)
3. **Pending**: Update installed, waiting for reboot
4. **Failed**: Update failed verification

### Automatic Rollback

RAUC automatically rolls back on:
- Boot failure after update
- Health check failure
- Service start failures
- System instability

### Manual Rollback

```bash
# Check current status
sudo rauc status

# Mark current slot as bad and switch
sudo rauc mark bad
sudo reboot

# Or mark specific slot as good/bad
sudo rauc mark good other
sudo rauc mark bad booted
```

## Update Strategies

### Development Updates

For development and testing:

```bash
# Frequent small updates
./scripts/create-update-bundle.sh --dev --no-sign

# Skip health checks for development
sudo rauc install --ignore-checksum update.raucb
```

### Production Updates

For production deployment:

```bash
# Full verification and signing
./scripts/create-update-bundle.sh --production

# Install with all safety checks
sudo rauc install update.raucb

# Monitor system after update
sudo journalctl -u rauc -f
```

### Staged Rollouts

Deploy updates gradually:

1. **Canary**: Deploy to 1-5% of devices
2. **Beta**: Deploy to 10-20% of devices
3. **Production**: Deploy to all devices

```bash
# Tag devices for staged rollout
echo "canary" > /data/device-group

# Server-side logic checks device group before serving updates
```

## Monitoring and Logging

### Update Logs

```bash
# View RAUC logs
sudo journalctl -u rauc

# Monitor real-time updates
sudo journalctl -u rauc -f

# Check last update status
sudo rauc status --detailed
```

### System Metrics

Monitor key metrics during updates:

```bash
# Disk space
df -h

# Memory usage
free -h

# System load
uptime

# Service status
systemctl status
```

## Advanced Features

### Delta Updates

For bandwidth-efficient updates:

```bash
# Create delta bundle (requires casync)
sudo rauc bundle \
  --cert=/etc/rauc/certs/dev-cert.pem \
  --key=/etc/rauc/certs/dev-key.pem \
  --delta-from=/path/to/previous.raucb \
  /tmp/bundle \
  delta-update.raucb
```

### Encrypted Updates

For secure update delivery:

```bash
# Create encrypted bundle
sudo rauc bundle \
  --cert=/etc/rauc/certs/dev-cert.pem \
  --key=/etc/rauc/certs/dev-key.pem \
  --encrypt=/etc/rauc/certs/encryption.pem \
  /tmp/bundle \
  encrypted-update.raucb
```

### Network Updates

Configure automatic network updates:

```bash
# Create RAUC Hawkbit configuration
sudo tee /etc/rauc/hawkbit.conf << 'EOF'
[client]
hawkbit_server=https://hawkbit.example.com
ssl=true
tenant_id=default
target_name=jetson-nano-001
auth_token=your-auth-token
bundle_download_location=/tmp/
retry_wait=60
connect_timeout=20
timeout=60
log_level=info
EOF
```

## Troubleshooting Updates

### Common Issues

1. **Bundle Verification Failed**
   ```bash
   # Check certificate validity
   openssl x509 -in /etc/rauc/certs/dev-cert.pem -text -noout
   
   # Verify bundle signature
   rauc info update.raucb
   ```

2. **Insufficient Space**
   ```bash
   # Check available space
   df -h
   
   # Clean up old bundles
   sudo find /tmp -name "*.raucb" -mtime +7 -delete
   ```

3. **Boot Failure After Update**
   ```bash
   # Boot from previous slot
   # System should automatically rollback
   
   # Check boot logs
   sudo journalctl -b
   ```

### Recovery Procedures

If updates fail consistently:

1. **Check System Health**: Verify base system integrity
2. **Review Logs**: Check RAUC and system logs for errors
3. **Test Bundles**: Verify bundle creation process
4. **Manual Recovery**: Boot from known good slot

### Debug Mode

Enable RAUC debug logging:

```bash
# Edit RAUC service
sudo systemctl edit rauc

# Add debug configuration
[Service]
Environment="RAUC_LOG_LEVEL=debug"

# Restart service
sudo systemctl restart rauc
```

## Best Practices

1. **Version Control**: Use semantic versioning for updates
2. **Testing**: Always test updates in development environment
3. **Monitoring**: Implement comprehensive health monitoring
4. **Backup**: Backup critical data before major updates
5. **Documentation**: Document all update procedures and changes
6. **Automation**: Automate update creation and deployment
7. **Rollback Plan**: Always have a rollback strategy
8. **Security**: Keep signing certificates secure and rotated

## Integration Examples

### CI/CD Pipeline

```yaml
# .github/workflows/build-update.yml
name: Build Update Bundle
on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v2
      - name: Build Update Bundle
        run: |
          ./scripts/create-update-bundle.sh --version ${{ github.ref_name }}
      - name: Upload Artifact
        uses: actions/upload-artifact@v2
        with:
          name: update-bundle
          path: "*.raucb"
```

### Docker Integration

```dockerfile
# Dockerfile for update creation
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y rauc
COPY scripts/ /scripts/
ENTRYPOINT ["/scripts/create-update-bundle.sh"]
```
