# Troubleshooting Guide

Comprehensive troubleshooting guide for Homie OS RAUC system issues.

## Common Issues and Solutions

### Installation Issues

#### Issue: RAUC Build Fails
**Symptoms**: 
- Configure or make fails during RAUC compilation
- Missing dependency errors

**Solutions**:
```bash
# Install missing build dependencies
sudo apt update
sudo apt install autotools-dev autoconf libtool libglib2.0-dev
sudo apt install libcurl4-openssl-dev libjson-glib-dev libssl-dev

# Clean and rebuild
cd rauc
make clean
./autogen.sh
./configure --enable-service
make && sudo make install
```

#### Issue: Partition Creation Fails
**Symptoms**:
- parted command fails
- Cannot create partitions

**Solutions**:
```bash
# Check if SD card is mounted
sudo umount /dev/mmcblk0*

# Verify SD card device
lsblk
sudo fdisk -l

# Force partition table creation
sudo parted /dev/mmcblk0 --script mklabel gpt
```

#### Issue: U-Boot Environment Variables Not Set
**Symptoms**:
- fw_setenv command not found
- Cannot modify U-Boot environment

**Solutions**:
```bash
# Install U-Boot tools
sudo apt install u-boot-tools

# Check if fw_env.config exists
ls -la /etc/fw_env.config

# Create fw_env.config if missing
sudo tee /etc/fw_env.config << 'EOF'
# Configuration for fw_setenv/fw_getenv
# Device Name    Offset     Size
/dev/mmcblk0    0x1FFFF000  0x1000
EOF
```

### Boot Issues

#### Issue: System Won't Boot After Partitioning
**Symptoms**:
- Black screen on boot
- No U-Boot prompt
- System hangs at boot

**Solutions**:
```bash
# Recovery steps (requires another system):
# 1. Boot from recovery SD card
# 2. Mount the problematic SD card
sudo mkdir -p /mnt/recovery
sudo mount /dev/mmcblk1p1 /mnt/recovery  # Adjust device as needed

# 3. Check boot files
ls -la /mnt/recovery/boot/

# 4. Restore boot files if missing
sudo cp -r /boot/* /mnt/recovery/boot/

# 5. Fix fstab
sudo nano /mnt/recovery/etc/fstab
# Ensure correct partition UUIDs
```

#### Issue: Boot Loop Between Slots
**Symptoms**:
- System switches between slots A and B repeatedly
- Cannot maintain stable boot

**Solutions**:
```bash
# Check boot attempts
sudo fw_printenv | grep boot

# Reset boot counter
sudo fw_setenv bootcount 0

# Mark current slot as good
sudo rauc mark good booted

# Check RAUC status
sudo rauc status --detailed
```

#### Issue: U-Boot Cannot Find Boot Files
**Symptoms**:
- U-Boot prompt appears
- "File not found" errors in U-Boot

**Solutions**:
```bash
# From U-Boot prompt, check files:
ls mmc 1:1 boot/
ls mmc 1:1 /

# Check if boot directory exists in root filesystem
# May need to move boot files to correct location

# From running system:
sudo ls -la /boot/
sudo ls -la /

# Ensure kernel and device tree are in /boot/
sudo find / -name "Image" -o -name "*.dtb" 2>/dev/null
```

### RAUC Service Issues

#### Issue: RAUC Service Won't Start
**Symptoms**:
- `systemctl status rauc` shows failed state
- D-Bus connection errors

**Solutions**:
```bash
# Check detailed service status
sudo systemctl status rauc -l

# Check RAUC configuration
sudo rauc info

# Verify configuration syntax
sudo rauc status

# Check D-Bus service
sudo systemctl status dbus
sudo systemctl restart dbus

# Restart RAUC service
sudo systemctl restart rauc
```

#### Issue: RAUC Configuration Invalid
**Symptoms**:
- "Invalid configuration" errors
- RAUC commands fail

**Solutions**:
```bash
# Validate configuration
sudo rauc info

# Check configuration file syntax
sudo nano /etc/rauc/system.conf

# Common issues:
# - Missing [system] section
# - Incorrect device paths
# - Missing keyring file

# Test with minimal configuration
sudo tee /etc/rauc/system.conf << 'EOF'
[system]
compatible=jetson-nano
bootloader=uboot

[slot.rootfs.0]
device=/dev/mmcblk0p1
type=ext4
bootname=a

[slot.rootfs.1]
device=/dev/mmcblk0p2
type=ext4
bootname=b
EOF
```

### Update Issues

#### Issue: Bundle Installation Fails
**Symptoms**:
- "Installation failed" errors
- Permission denied errors

**Solutions**:
```bash
# Check available space
df -h

# Verify bundle integrity
sudo rauc info /path/to/bundle.raucb

# Check slot status
sudo rauc status

# Try installing to specific slot
sudo rauc install /path/to/bundle.raucb --target=rootfs.1

# Check installation logs
sudo journalctl -u rauc -f
```

#### Issue: Bundle Signature Verification Fails
**Symptoms**:
- "Signature verification failed" errors
- Certificate validation errors

**Solutions**:
```bash
# Check keyring file
sudo ls -la /etc/rauc/keyring.pem

# Verify certificate validity
openssl x509 -in /etc/rauc/keyring.pem -text -noout

# Check bundle signature
openssl cms -verify -in bundle.raucb -inform DER -CAfile /etc/rauc/keyring.pem

# For development, disable signature verification temporarily
sudo nano /etc/rauc/system.conf
# Add: bundle-signing-required=false
```

#### Issue: Insufficient Space for Update
**Symptoms**:
- "No space left on device" errors
- Update fails during installation

**Solutions**:
```bash
# Check space on all partitions
df -h

# Clean up temporary files
sudo rm -rf /tmp/rauc-*
sudo apt autoremove
sudo apt autoclean

# Check update bundle size
ls -lh /path/to/bundle.raucb

# Increase partition size if needed (requires repartitioning)
```

### Network and Remote Update Issues

#### Issue: Cannot Download Updates
**Symptoms**:
- Network timeouts
- Download failures

**Solutions**:
```bash
# Check network connectivity
ping 8.8.8.8
curl -I https://updates.example.com

# Check certificates for HTTPS
curl -v https://updates.example.com

# Update CA certificates
sudo apt update && sudo apt install ca-certificates

# Check proxy settings
env | grep -i proxy

# Test manual download
curl -L -o test.raucb https://updates.example.com/latest.raucb
```

#### Issue: Hawkbit Connection Fails
**Symptoms**:
- Cannot connect to Hawkbit server
- Authentication failures

**Solutions**:
```bash
# Check Hawkbit configuration
cat /etc/rauc/hawkbit.conf

# Test server connectivity
curl -v https://hawkbit.example.com

# Check authentication token
cat /etc/rauc/hawkbit-token

# Verify tenant and target configuration
curl -H "Authorization: TargetToken YOUR_TOKEN" \
     https://hawkbit.example.com/DEFAULT/controller/v1/TARGET_ID
```

### Storage and Filesystem Issues

#### Issue: Filesystem Corruption
**Symptoms**:
- Boot failures after update
- File system check errors
- Read-only filesystem

**Solutions**:
```bash
# Check filesystem integrity
sudo fsck /dev/mmcblk0p1
sudo fsck /dev/mmcblk0p2

# Force filesystem check
sudo fsck -f /dev/mmcblk0p1

# Repair filesystem
sudo fsck -y /dev/mmcblk0p1

# If severe corruption, recreate filesystem
sudo mkfs.ext4 -F /dev/mmcblk0p1
# Note: This will erase all data on the partition
```

#### Issue: SD Card Wearing Out
**Symptoms**:
- Frequent I/O errors
- Slow performance
- Random boot failures

**Solutions**:
```bash
# Check SD card health
sudo dmesg | grep -i mmc
sudo smartctl -a /dev/mmcblk0  # If supported

# Monitor I/O errors
sudo journalctl | grep -i "i/o error"

# Reduce writes with optimizations
# Add to /etc/fstab:
# tmpfs /tmp tmpfs defaults,noatime 0 0
# tmpfs /var/log tmpfs defaults,noatime 0 0

# Consider using industrial-grade SD card or eMMC
```

#### Issue: Data Partition Mount Fails
**Symptoms**:
- /data not accessible
- Boot hangs waiting for /data

**Solutions**:
```bash
# Check partition status
sudo blkid /dev/mmcblk0p3
lsblk

# Try manual mount
sudo mkdir -p /data
sudo mount /dev/mmcblk0p3 /data

# Check fstab entry
grep data /etc/fstab

# Fix fstab if needed
sudo nano /etc/fstab
# Add nofail option: /dev/mmcblk0p3 /data ext4 defaults,nofail 0 2

# Check filesystem
sudo fsck /dev/mmcblk0p3
```

## Diagnostic Commands

### System Information
```bash
# Hardware information
sudo dmidecode -t system
cat /proc/cpuinfo
cat /proc/meminfo

# Storage information
lsblk
sudo fdisk -l
df -h

# Boot information
sudo journalctl -b
dmesg | head -50
```

### RAUC Diagnostics
```bash
# RAUC status and configuration
sudo rauc status --detailed
sudo rauc info
sudo rauc status --output-format=json

# Certificate information
openssl x509 -in /etc/rauc/keyring.pem -text -noout
ls -la /etc/rauc/

# Service status
sudo systemctl status rauc -l
sudo journalctl -u rauc -n 50
```

### U-Boot Diagnostics
```bash
# U-Boot environment
sudo fw_printenv | sort

# Boot-related variables
sudo fw_printenv | grep -E "(boot|rauc)"

# Verify U-Boot tools configuration
cat /etc/fw_env.config
```

## Recovery Procedures

### Complete System Recovery

If the system is completely unbootable:

1. **Create Recovery SD Card**
   ```bash
   # On another system, flash JetPack to new SD card
   # Boot from recovery SD card
   ```

2. **Mount Problematic SD Card**
   ```bash
   # Insert problematic SD card via USB adapter
   sudo mkdir -p /mnt/recovery
   sudo mount /dev/sdb1 /mnt/recovery  # Adjust device
   ```

3. **Backup Data**
   ```bash
   # Backup user data
   sudo cp -r /mnt/recovery/data /backup/
   
   # Backup system configuration
   sudo cp -r /mnt/recovery/etc /backup/
   ```

4. **Restore or Reinstall**
   ```bash
   # Option 1: Fix existing installation
   # Restore boot files, fix configuration
   
   # Option 2: Fresh installation
   # Repartition and reinstall Homie OS
   ```

### Slot Recovery

If one slot is corrupted but system still boots:

```bash
# Check which slot is active
sudo rauc status

# Mark current slot as good
sudo rauc mark good booted

# Install fresh bundle to inactive slot
sudo rauc install /path/to/known-good-bundle.raucb

# Test by switching slots
sudo rauc mark good other
sudo reboot
```

### Emergency Boot

If both slots are problematic:

1. **U-Boot Manual Boot**
   ```bash
   # Interrupt U-Boot (press key during boot)
   # At U-Boot prompt:
   
   setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rw
   ext4load mmc 1:1 ${kernel_addr_r} boot/Image
   ext4load mmc 1:1 ${fdt_addr_r} boot/tegra210-p3448-0000-p3449-0000-a02.dtb
   booti ${kernel_addr_r} - ${fdt_addr_r}
   ```

2. **Single User Mode**
   ```bash
   # Add to kernel command line in U-Boot:
   setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rw single
   ```

## Monitoring and Prevention

### Health Monitoring Script

```bash
#!/bin/bash
# /usr/local/bin/system-health-check.sh

# Check RAUC status
if ! rauc status > /dev/null 2>&1; then
    echo "CRITICAL: RAUC service not responding"
    exit 2
fi

# Check boot slot health
BOOT_ATTEMPTS=$(fw_printenv bootcount 2>/dev/null | cut -d= -f2)
if [ "${BOOT_ATTEMPTS:-0}" -gt 2 ]; then
    echo "WARNING: High boot attempt count: $BOOT_ATTEMPTS"
    exit 1
fi

# Check filesystem space
ROOT_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$ROOT_USAGE" -gt 90 ]; then
    echo "CRITICAL: Root filesystem $ROOT_USAGE% full"
    exit 2
fi

DATA_USAGE=$(df /data | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DATA_USAGE" -gt 85 ]; then
    echo "WARNING: Data filesystem $DATA_USAGE% full"
    exit 1
fi

# Check critical services
for service in rauc dbus; do
    if ! systemctl is-active $service > /dev/null; then
        echo "CRITICAL: Service $service is not running"
        exit 2
    fi
done

echo "OK: System health check passed"
exit 0
```

### Automated Backup

```bash
#!/bin/bash
# /usr/local/bin/backup-critical-data.sh

BACKUP_DIR="/data/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup RAUC configuration
cp -r /etc/rauc "$BACKUP_DIR/"

# Backup U-Boot environment
fw_printenv > "$BACKUP_DIR/uboot-env.txt"

# Backup system configuration
cp /etc/fstab "$BACKUP_DIR/"
cp /etc/hostname "$BACKUP_DIR/"

# Backup application data
tar -czf "$BACKUP_DIR/app-data.tar.gz" -C /data app/

# Keep only last 7 backups
find /data/backups -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null

echo "Backup completed: $BACKUP_DIR"
```

### Log Analysis

```bash
#!/bin/bash
# /usr/local/bin/analyze-logs.sh

echo "=== RAUC Status ==="
rauc status --detailed

echo -e "\n=== Recent RAUC Logs ==="
journalctl -u rauc --since "24 hours ago" --no-pager

echo -e "\n=== Boot Logs ==="
journalctl -b --no-pager | grep -E "(rauc|boot|mount)"

echo -e "\n=== Storage Errors ==="
dmesg | grep -i -E "(error|fail)" | grep -E "(mmc|sd|storage)"

echo -e "\n=== System Health ==="
/usr/local/bin/system-health-check.sh
```

## Getting Help

### Information to Gather

When seeking help, collect this information:

```bash
# System information
uname -a
cat /etc/os-release
lsb_release -a

# Hardware information
cat /proc/cpuinfo | grep -E "(model|Revision)"
free -h
df -h

# RAUC information
rauc --version
rauc status --detailed --output-format=json
rauc info

# Boot information
fw_printenv | grep -E "(boot|rauc)"
cat /proc/cmdline

# Recent logs
journalctl -u rauc --since "1 hour ago" --no-pager
dmesg | tail -50
```

### Support Channels

- 📚 [Documentation](https://github.com/Homie-Ai-project/homie_os/docs)
- 🐛 [Issue Tracker](https://github.com/Homie-Ai-project/homie_os/issues)
- 💬 [Community Discussions](https://github.com/Homie-Ai-project/homie_os/discussions)
- 📧 [Email Support](mailto:support@homieos.com)

### Creating Bug Reports

Include the following in bug reports:

1. **Clear Description**: What you expected vs what happened
2. **Steps to Reproduce**: Exact commands and procedures
3. **System Information**: Output from information gathering commands
4. **Logs**: Relevant log excerpts (not full logs unless requested)
5. **Configuration**: Relevant configuration files
6. **Timeline**: When the issue started occurring

This comprehensive troubleshooting guide should help resolve most issues you might encounter with the Homie OS RAUC system.
