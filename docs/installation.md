# Installation Guide

Complete step-by-step guide to install RAUC A/B update system on NVIDIA Jetson Nano.

## Prerequisites

### Hardware Requirements
- NVIDIA Jetson Nano (4GB recommended)
- 32GB+ SD card or eMMC storage
- Stable power supply (5V/4A recommended)
- Network connection

### Software Requirements
- Ubuntu 20.04 LTS (JetPack 4.6.x)
- Root access to the system
- Basic command line knowledge

## Step-by-Step Installation

### 1. Prepare Base System

Start with a fresh JetPack 4.6.x installation on your Jetson Nano.

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install build dependencies
sudo apt install build-essential git cmake pkg-config
```

### 2. Install RAUC Dependencies

```bash
# Install required libraries
sudo apt install libglib2.0-dev libcurl4-openssl-dev libjson-glib-dev
sudo apt install libssl-dev libdbus-1-dev squashfs-tools
sudo apt install casync libarchive-dev
```

### 3. Build and Install RAUC

```bash
# Clone RAUC repository
git clone https://github.com/rauc/rauc.git
cd rauc
git checkout v1.8  # Use stable version

# Configure and build
./autogen.sh
./configure --enable-service
make

# Install RAUC
sudo make install
sudo ldconfig
```

### 4. Configure U-Boot for Dual Boot

**⚠️ Warning**: Backup your U-Boot environment before making changes.

```bash
# Backup current U-Boot environment
sudo fw_printenv > uboot_env_backup.txt

# Configure boot targets and slots
sudo fw_setenv boot_targets "mmc1 mmc0 usb0 pxe dhcp"
sudo fw_setenv bootslot_a "setenv bootargs root=/dev/mmcblk0p1"
sudo fw_setenv bootslot_b "setenv bootargs root=/dev/mmcblk0p2"

# Set default boot slot
sudo fw_setenv rauc_slot a
```

### 5. Create Partition Layout

**⚠️ Critical**: This step will repartition your SD card. **Backup all data first!**

```bash
# Create full system backup
sudo dd if=/dev/mmcblk0 of=/backup/jetson_backup.img bs=1M status=progress

# Repartition SD card (for 32GB card)
sudo parted /dev/mmcblk0 --script -- \
  mklabel gpt \
  mkpart primary ext4 1MiB 8GiB \
  mkpart primary ext4 8GiB 16GiB \
  mkpart primary ext4 16GiB 100%

# Format partitions with labels
sudo mkfs.ext4 -F -L rootfs_a /dev/mmcblk0p1
sudo mkfs.ext4 -F -L rootfs_b /dev/mmcblk0p2
sudo mkfs.ext4 -F -L userdata /dev/mmcblk0p3
```

### 6. Configure RAUC System

```bash
# Create RAUC configuration directory
sudo mkdir -p /etc/rauc

# Create system configuration
sudo tee /etc/rauc/system.conf << 'EOF'
[system]
compatible=jetson-nano
bootloader=uboot
max-bundle-download-size=2147483648

[keyring]
path=/etc/rauc/keyring.pem

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

### 7. Generate RAUC Signing Keys

```bash
# Create certificate directory
sudo mkdir -p /etc/rauc/certs
cd /etc/rauc/certs

# Generate Certificate Authority
sudo openssl req -x509 -newkey rsa:4096 -keyout ca-key.pem -out ca-cert.pem -days 7300 -nodes \
  -subj "/C=US/ST=CA/L=San Francisco/O=Homie OS/CN=Homie OS CA"

# Generate development certificate
sudo openssl req -new -newkey rsa:4096 -keyout dev-key.pem -out dev-req.pem -nodes \
  -subj "/C=US/ST=CA/L=San Francisco/O=Homie OS/CN=Homie OS Dev"

sudo openssl x509 -req -in dev-req.pem -CA ca-cert.pem -CAkey ca-key.pem -out dev-cert.pem -days 365

# Set up keyring
sudo cp ca-cert.pem /etc/rauc/keyring.pem

# Secure private keys
sudo chmod 600 /etc/rauc/certs/*-key.pem
sudo chmod 644 /etc/rauc/certs/*-cert.pem
```

### 8. Setup Data Partition Mount

```bash
# Create data directory
sudo mkdir -p /data

# Add to fstab for persistent mounting
echo "/dev/mmcblk0p3 /data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

# Mount data partition
sudo mount -a

# Verify mount
df -h /data
```

### 9. Enable RAUC Service

```bash
# Enable and start RAUC service
sudo systemctl enable rauc
sudo systemctl start rauc

# Verify service status
sudo systemctl status rauc
```

### 10. Copy Current System to Slot A

Since we've repartitioned, we need to restore the system to Slot A:

```bash
# Mount Slot A
sudo mkdir -p /mnt/rootfs_a
sudo mount /dev/mmcblk0p1 /mnt/rootfs_a

# Copy current system (excluding special directories)
sudo rsync -aHAXx \
  --exclude=/proc \
  --exclude=/sys \
  --exclude=/dev \
  --exclude=/tmp \
  --exclude=/media \
  --exclude=/mnt \
  --exclude=/data \
  / /mnt/rootfs_a/

# Update fstab in new root
sudo sed -i 's|/dev/mmcblk0p1|/dev/mmcblk0p1|g' /mnt/rootfs_a/etc/fstab
echo "/dev/mmcblk0p3 /data ext4 defaults,nofail 0 2" | sudo tee -a /mnt/rootfs_a/etc/fstab

# Unmount
sudo umount /mnt/rootfs_a
```

### 11. Verify Installation

```bash
# Check RAUC status
sudo rauc status

# Check current boot slot
sudo rauc status --detailed

# Test RAUC info
sudo rauc info
```

### 12. Reboot and Test

```bash
# Reboot to test the new partition layout
sudo reboot
```

After reboot, verify everything is working:

```bash
# Check mounted filesystems
df -h

# Verify RAUC is working
sudo rauc status

# Check data partition
ls -la /data
```

## Automated Installation

For convenience, you can use our automated setup script:

```bash
# Clone the repository
git clone https://github.com/Homie-Ai-project/homie_os.git
cd homie_os

# Run automated setup (requires sudo)
sudo ./scripts/setup-rauc-jetson.sh
```

## Next Steps

1. [Create your first update bundle](update-process.md)
2. [Configure remote management](configuration.md)
3. [Set up monitoring](troubleshooting.md#monitoring)

## Troubleshooting

If you encounter issues during installation, see our [Troubleshooting Guide](troubleshooting.md).

## Recovery

If something goes wrong:

1. Boot from backup SD card
2. Restore from the backup image created in step 5
3. Retry installation with corrected parameters

```bash
# Restore from backup
sudo dd if=/backup/jetson_backup.img of=/dev/mmcblk0 bs=1M status=progress
```
