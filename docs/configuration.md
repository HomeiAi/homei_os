# Configuration Reference

Complete configuration guide for RAUC and Homie OS system components.

## RAUC System Configuration

### Main Configuration File

Location: `/etc/rauc/system.conf`

```ini
[system]
# Device compatibility identifier
compatible=jetson-nano

# Bootloader type (uboot for Jetson Nano)
bootloader=uboot

# Maximum bundle size (2GB)
max-bundle-download-size=2147483648

# Bundle format (plain, verity, or crypt)
bundle-formats=plain

# Variant identifier (optional)
variant=production

[keyring]
# Path to certificate bundle for signature verification
path=/etc/rauc/keyring.pem

# Use system CA bundle (optional)
use-bundle-signing-time=true

[slot.rootfs.0]
device=/dev/mmcblk0p1
type=ext4
bootname=a
readonly=false

[slot.rootfs.1]
device=/dev/mmcblk0p2
type=ext4
bootname=b
readonly=false

# Optional data slot (not updated)
[slot.data.0]
device=/dev/mmcblk0p3
type=ext4
parent=rootfs.0
readonly=false

[handlers]
# Custom installation handlers
system-info=/usr/lib/rauc/handlers/system-info
pre-install=/usr/lib/rauc/handlers/pre-install
post-install=/usr/lib/rauc/handlers/post-install
```

### Advanced Configuration Options

#### Boot Configuration
```ini
[system]
# Boot attempts before marking slot as bad
boot-attempts-primary=3

# Boot attempts for fallback slot
boot-attempts-fallback=1

# Watchdog timeout
statusfile-ep-timeout=30

# Barebox specific options (if using barebox instead of u-boot)
# bootloader=barebox
# grubenv=/boot/grub/grubenv
```

#### Bundle Verification
```ini
[system]
# Require bundle signature verification
bundle-signing-required=true

# Allow bundle format adaptation
bundle-formats=plain,verity

# Intermediate certificate validation
intermediate-certificate-validation=true

# Certificate revocation list
crl-file=/etc/rauc/crl.pem
```

#### Health Monitoring
```ini
[system]
# Enable automatic health monitoring
health-status-enabled=true

# Health check interval (seconds)
health-check-interval=300

# Health timeout after update
health-timeout=1800
```

## U-Boot Configuration

### Environment Variables

Critical U-Boot variables for RAUC integration:

```bash
# Boot slot configuration
bootslot_a=setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4
bootslot_b=setenv bootargs root=/dev/mmcblk0p2 rootfstype=ext4

# RAUC integration
rauc_slot=a
rauc_part.a=1
rauc_part.b=2

# Boot order and fallback
boot_targets=mmc1 mmc0 usb0 pxe dhcp
bootdelay=3

# Boot counting
bootcount=0
bootlimit=3
altbootcmd=run bootcmd_b

# Boot commands
bootcmd_a=run bootslot_a; ext4load mmc 1:${rauc_part.a} ${kernel_addr_r} boot/Image; ext4load mmc 1:${rauc_part.a} ${fdt_addr_r} boot/tegra210-p3448-0000-p3449-0000-a02.dtb; booti ${kernel_addr_r} - ${fdt_addr_r}

bootcmd_b=run bootslot_b; ext4load mmc 1:${rauc_part.b} ${kernel_addr_r} boot/Image; ext4load mmc 1:${rauc_part.b} ${fdt_addr_r} boot/tegra210-p3448-0000-p3449-0000-a02.dtb; booti ${kernel_addr_r} - ${fdt_addr_r}
```

### Setting U-Boot Variables

```bash
# Set variables using fw_setenv
sudo fw_setenv bootslot_a "setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4"
sudo fw_setenv bootslot_b "setenv bootargs root=/dev/mmcblk0p2 rootfstype=ext4"
sudo fw_setenv rauc_slot a

# Save environment
sudo fw_setenv save
```

## Service Configuration

### RAUC Service

Systemd service configuration for RAUC:

```ini
# /etc/systemd/system/rauc.service.d/override.conf
[Unit]
Description=RAUC Update Service
After=network.target

[Service]
Type=dbus
BusName=de.pengutronix.rauc
ExecStart=/usr/local/bin/rauc service
Environment="RAUC_LOG_LEVEL=info"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Health Monitor Service

Custom health monitoring service:

```ini
# /etc/systemd/system/homie-health.service
[Unit]
Description=Homie OS Health Monitor
After=multi-user.target
Wants=rauc.service

[Service]
Type=simple
ExecStart=/usr/local/bin/homie-health-monitor
Restart=always
RestartSec=30
User=root

[Install]
WantedBy=multi-user.target
```

## Network Configuration

### Hawkbit Integration

For remote update management with Eclipse Hawkbit:

```ini
# /etc/rauc/hawkbit.conf
[client]
hawkbit_server=https://hawkbit.example.com
ssl=true
ssl_verify=true
tenant_id=default
target_name=${HOSTNAME}
auth_token_path=/etc/rauc/hawkbit-token
bundle_download_location=/tmp/rauc-downloads/
retry_wait=60
connect_timeout=20
timeout=60
log_level=info

[device]
product=homie-os
model=jetson-nano
serial_number_path=/sys/class/dmi/id/product_serial
hardware_revision_path=/proc/device-tree/nvidia,dtsfilename
```

### Update Server Configuration

For custom update server:

```bash
# /etc/rauc/update-server.conf
SERVER_URL="https://updates.homie-ai.com"
DEVICE_ID="$(cat /etc/machine-id)"
CHECK_INTERVAL=3600
DOWNLOAD_PATH="/tmp/updates"
LOG_LEVEL="info"
```

## Certificate Management

### Certificate Configuration

```bash
# Certificate paths
CA_CERT="/etc/rauc/certs/ca-cert.pem"
DEV_CERT="/etc/rauc/certs/dev-cert.pem"
DEV_KEY="/etc/rauc/certs/dev-key.pem"
PROD_CERT="/etc/rauc/certs/prod-cert.pem"
PROD_KEY="/etc/rauc/certs/prod-key.pem"

# Keyring for verification
KEYRING="/etc/rauc/keyring.pem"
```

### Certificate Rotation

```bash
#!/bin/bash
# /usr/local/bin/rotate-certificates.sh

# Generate new certificates
openssl req -new -newkey rsa:4096 -keyout /tmp/new-key.pem -out /tmp/new-req.pem -nodes
openssl x509 -req -in /tmp/new-req.pem -CA /etc/rauc/certs/ca-cert.pem -CAkey /etc/rauc/certs/ca-key.pem -out /tmp/new-cert.pem -days 365

# Backup old certificates
cp /etc/rauc/certs/dev-cert.pem /etc/rauc/certs/dev-cert.pem.backup
cp /etc/rauc/certs/dev-key.pem /etc/rauc/certs/dev-key.pem.backup

# Install new certificates
mv /tmp/new-cert.pem /etc/rauc/certs/dev-cert.pem
mv /tmp/new-key.pem /etc/rauc/certs/dev-key.pem

# Update keyring
cat /etc/rauc/certs/ca-cert.pem > /etc/rauc/keyring.pem

# Restart RAUC service
systemctl restart rauc
```

## Filesystem Configuration

### Partition Mount Configuration

```bash
# /etc/fstab
UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults,noatime 0 1
UUID=87654321-4321-4321-4321-210987654321 /data ext4 defaults,noatime,nofail 0 2

# Temporary filesystems
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
tmpfs /var/tmp tmpfs defaults,noatime,mode=1777 0 0
```

### Persistent Directory Configuration

```bash
# /usr/local/bin/setup-persistent-dirs.sh
#!/bin/bash

# Create symlinks for persistent data
mkdir -p /data/app/{config,logs,cache,databases}
mkdir -p /data/system/{ssh,network,certificates}

# Link configuration directories
ln -sf /data/app/config /etc/app-config
ln -sf /data/app/logs /var/log/app
ln -sf /data/system/ssh /etc/ssh/ssh_host_keys
```

## Monitoring Configuration

### Prometheus Metrics

Export RAUC metrics for monitoring:

```yaml
# /etc/prometheus/rauc-exporter.yml
listen_address: "0.0.0.0:9090"
metrics_path: "/metrics"
log_level: "info"

rauc:
  command: "/usr/local/bin/rauc"
  status_command: "status --detailed --output-format=json"
  info_command: "info --output-format=json"
  
metrics:
  - name: "rauc_slot_status"
    help: "RAUC slot status (0=inactive, 1=active, 2=booted)"
    type: "gauge"
    
  - name: "rauc_boot_attempts"
    help: "Number of boot attempts for current slot"
    type: "counter"
    
  - name: "rauc_last_update_timestamp"
    help: "Timestamp of last successful update"
    type: "gauge"
```

### Log Configuration

```bash
# /etc/rsyslog.d/rauc.conf
# RAUC logging configuration
:programname, isequal, "rauc" /var/log/rauc.log
& stop

# Log rotation
# /etc/logrotate.d/rauc
/var/log/rauc.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
```

## Environment-Specific Configurations

### Development Environment

```ini
# /etc/rauc/system.conf.dev
[system]
compatible=jetson-nano-dev
bootloader=uboot
max-bundle-download-size=1073741824
bundle-formats=plain

# Skip signature verification in development
[keyring]
# path=/etc/rauc/keyring.pem
# use-bundle-signing-time=false

# Allow unsigned bundles
bundle-signing-required=false
```

### Production Environment

```ini
# /etc/rauc/system.conf.prod
[system]
compatible=jetson-nano-prod
bootloader=uboot
max-bundle-download-size=2147483648
bundle-formats=verity

# Strict verification
[keyring]
path=/etc/rauc/keyring.pem
use-bundle-signing-time=true

# Require signed bundles
bundle-signing-required=true
intermediate-certificate-validation=true

# Health monitoring
health-status-enabled=true
health-timeout=1800
```

## Security Configuration

### File Permissions

```bash
# RAUC configuration files
chmod 644 /etc/rauc/system.conf
chmod 644 /etc/rauc/keyring.pem

# Certificate files
chmod 600 /etc/rauc/certs/*-key.pem
chmod 644 /etc/rauc/certs/*-cert.pem

# Scripts and binaries
chmod 755 /usr/local/bin/rauc*
chmod 755 /usr/local/bin/homie*
```

### SELinux/AppArmor

```bash
# AppArmor profile for RAUC
# /etc/apparmor.d/usr.local.bin.rauc
#include <tunables/global>

/usr/local/bin/rauc {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  capability sys_admin,
  capability dac_override,

  /usr/local/bin/rauc mr,
  /etc/rauc/** r,
  /dev/mmcblk0* rw,
  /tmp/rauc-* rw,
  
  network inet stream,
  network inet dgram,
  
  /proc/mounts r,
  /sys/class/block/** r,
}
```

## Backup Configuration

### Automatic Backup

```bash
# /etc/systemd/system/homie-backup.service
[Unit]
Description=Homie OS Data Backup
Requires=homie-backup.timer

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-data.sh
User=root

# /etc/systemd/system/homie-backup.timer
[Unit]
Description=Run Homie OS Data Backup
Requires=homie-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

## Validation

### Configuration Validation Script

```bash
#!/bin/bash
# /usr/local/bin/validate-config.sh

echo "Validating Homie OS configuration..."

# Check RAUC configuration
if rauc info > /dev/null 2>&1; then
    echo "✓ RAUC configuration valid"
else
    echo "✗ RAUC configuration invalid"
    exit 1
fi

# Check partition layout
if [ -b /dev/mmcblk0p1 ] && [ -b /dev/mmcblk0p2 ] && [ -b /dev/mmcblk0p3 ]; then
    echo "✓ Partition layout correct"
else
    echo "✗ Partition layout incorrect"
    exit 1
fi

# Check mount points
if mountpoint -q /data; then
    echo "✓ Data partition mounted"
else
    echo "✗ Data partition not mounted"
    exit 1
fi

# Check certificates
if [ -f /etc/rauc/keyring.pem ]; then
    echo "✓ RAUC keyring present"
else
    echo "✗ RAUC keyring missing"
    exit 1
fi

echo "Configuration validation passed"
```

This comprehensive configuration reference covers all aspects of setting up and maintaining a RAUC-based update system on Jetson Nano.
