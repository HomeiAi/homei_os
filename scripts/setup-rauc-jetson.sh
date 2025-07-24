#!/bin/bash
# Automated RAUC setup script for NVIDIA Jetson Nano
# Part of Homie OS - Enterprise-grade embedded system
# Compatible with Ubuntu 20.04 and 22.04

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/homie-setup.log"
BACKUP_DIR="/backup"
RAUC_VERSION="v1.8"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Check system compatibility
check_system() {
    log "Checking system compatibility..."
    
    # Check if running on Jetson Nano
    if ! grep -q "jetson-nano" /proc/device-tree/model 2>/dev/null; then
        if ! grep -q "NVIDIA Jetson Nano" /proc/device-tree/model 2>/dev/null; then
            warn "This system may not be a Jetson Nano. Continuing anyway..."
        fi
    fi
    
    # Check Ubuntu version
    if grep -q "22.04" /etc/os-release; then
        log "Ubuntu 22.04 detected - using updated configuration"
    elif grep -q "20.04" /etc/os-release; then
        log "Ubuntu 20.04 detected - using legacy configuration"
    else
        warn "This script is tested on Ubuntu 20.04 and 22.04. Your system may not be compatible."
    fi
    
    # Check available space
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_SPACE -lt 2097152 ]]; then  # 2GB in KB
        error "Insufficient disk space. At least 2GB free space required."
        exit 1
    fi
    
    log "System compatibility check passed"
}

# Create backup of current system
create_backup() {
    log "Creating system backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup U-Boot environment
    if command -v fw_printenv >/dev/null 2>&1; then
        fw_printenv > "$BACKUP_DIR/uboot-env-$(date +%Y%m%d-%H%M%S).txt"
        log "U-Boot environment backed up"
    fi
    
    # Backup critical configuration files
    tar -czf "$BACKUP_DIR/system-config-$(date +%Y%m%d-%H%M%S).tar.gz" \
        /etc/fstab \
        /etc/hostname \
        /etc/hosts \
        /boot/ \
        2>/dev/null || true
    
    log "System backup completed"
}

# Install system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    # Update package list
    apt update
    
    # Detect Ubuntu version for package selection
    if grep -q "22.04" /etc/os-release; then
        log "Installing packages for Ubuntu 22.04..."
        apt install -y build-essential git cmake pkg-config
        apt install -y libglib2.0-dev libcurl4-openssl-dev libjson-glib-dev
        apt install -y libssl-dev libdbus-1-dev squashfs-tools
        apt install -y libarchive-dev autotools-dev autoconf libtool
        apt install -y u-boot-tools parted curl wget
        
        # Install casync from source for 22.04 (not available in repos)
        if ! command -v casync >/dev/null 2>&1; then
            log "Building casync from source for Ubuntu 22.04..."
            apt install -y meson ninja-build libzstd-dev liblzma-dev libzlib1g-dev
            apt install -y libacl1-dev libselinux1-dev libfuse3-dev
            
            cd /tmp
            rm -rf casync
            git clone https://github.com/systemd/casync.git
            cd casync
            meson build
            ninja -C build
            ninja -C build install
            ldconfig
        fi
    else
        log "Installing packages for Ubuntu 20.04..."
        apt install -y build-essential git cmake pkg-config
        apt install -y libglib2.0-dev libcurl4-openssl-dev libjson-glib-dev
        apt install -y libssl-dev libdbus-1-dev squashfs-tools
        apt install -y casync libarchive-dev autotools-dev autoconf libtool
        apt install -y u-boot-tools parted
    fi
    
    log "Dependencies installed successfully"
}

# Build and install RAUC
install_rauc() {
    log "Building and installing RAUC..."
    
    cd /tmp
    
    # Remove existing rauc directory if it exists
    rm -rf rauc
    
    # Clone RAUC repository
    git clone https://github.com/rauc/rauc.git
    cd rauc
    git checkout "$RAUC_VERSION"
    
    # Build RAUC with updated configuration for newer systems
    if grep -q "22.04" /etc/os-release; then
        log "Building RAUC for Ubuntu 22.04..."
        ./autogen.sh
        ./configure --enable-service --enable-network --enable-json
        make -j$(nproc)
        make install
        ldconfig
    else
        log "Building RAUC for Ubuntu 20.04..."
        ./autogen.sh
        ./configure --enable-service
        make -j$(nproc)
        make install
        ldconfig
    fi
    
    # Verify installation
    if ! command -v rauc >/dev/null 2>&1; then
        error "RAUC installation failed"
        exit 1
    fi
    
    log "RAUC installed successfully (version: $(rauc --version))"
}

# Configure U-Boot for dual boot
configure_uboot() {
    log "Configuring U-Boot for dual boot..."
    
    # Check if fw_setenv is available
    if ! command -v fw_setenv >/dev/null 2>&1; then
        error "fw_setenv not available. Please install u-boot-tools."
        exit 1
    fi
    
    # Create fw_env.config if it doesn't exist
    if [[ ! -f /etc/fw_env.config ]]; then
        # Different configurations for different Ubuntu versions
        if grep -q "22.04" /etc/os-release; then
            cat > /etc/fw_env.config << 'EOF'
# Configuration file for fw_setenv/fw_getenv - Ubuntu 22.04
# Device name	Offset		Size		Endian	Block Size
/dev/mmcblk0	0x1FFFF000	0x1000		0	0x200
EOF
        else
            cat > /etc/fw_env.config << 'EOF'
# Configuration file for fw_setenv/fw_getenv - Ubuntu 20.04
# Device name	Offset		Size
/dev/mmcblk0	0x1FFFF000	0x1000
EOF
        fi
        log "Created /etc/fw_env.config"
    fi
    
    # Configure boot slots
    fw_setenv boot_targets "mmc1 mmc0 usb0 pxe dhcp"
    fw_setenv bootslot_a "setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4"
    fw_setenv bootslot_b "setenv bootargs root=/dev/mmcblk0p2 rootfstype=ext4"
    fw_setenv rauc_slot a
    
    log "U-Boot configuration completed"
}

# Create partition layout
create_partitions() {
    log "Creating partition layout..."
    
    # Get SD card size
    DEVICE="/dev/mmcblk0"
    DEVICE_SIZE=$(blockdev --getsize64 "$DEVICE")
    DEVICE_SIZE_GB=$((DEVICE_SIZE / 1024 / 1024 / 1024))
    
    log "SD card size: ${DEVICE_SIZE_GB}GB"
    
    # Calculate partition sizes based on card size
    if [[ $DEVICE_SIZE_GB -ge 64 ]]; then
        SLOT_SIZE="16GiB"
        log "Using 16GB slots for 64GB+ card"
    elif [[ $DEVICE_SIZE_GB -ge 32 ]]; then
        SLOT_SIZE="8GiB"
        log "Using 8GB slots for 32GB+ card"
    else
        SLOT_SIZE="6GiB"
        log "Using 6GB slots for smaller card"
    fi
    
    # Confirm destructive operation
    echo -e "${RED}WARNING: This will ERASE ALL DATA on $DEVICE${NC}"
    echo "Current partitions:"
    parted "$DEVICE" print 2>/dev/null || true
    echo
    read -p "Continue with partitioning? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Partitioning cancelled by user"
        exit 1
    fi
    
    # Create full system backup before partitioning
    log "Creating full system backup (this may take a while)..."
    dd if="$DEVICE" of="$BACKUP_DIR/full-system-backup-$(date +%Y%m%d-%H%M%S).img" bs=1M status=progress
    
    # Unmount any mounted partitions
    umount "${DEVICE}"* 2>/dev/null || true
    
    # Create new partition table
    parted "$DEVICE" --script -- \
        mklabel gpt \
        mkpart primary ext4 1MiB "$SLOT_SIZE" \
        mkpart primary ext4 "$SLOT_SIZE" "$((${SLOT_SIZE%GiB} * 2))GiB" \
        mkpart primary ext4 "$((${SLOT_SIZE%GiB} * 2))GiB" 100%
    
    # Wait for kernel to recognize new partitions
    sleep 2
    partprobe "$DEVICE"
    sleep 2
    
    # Format partitions
    mkfs.ext4 -F -L rootfs_a "${DEVICE}p1"
    mkfs.ext4 -F -L rootfs_b "${DEVICE}p2"
    mkfs.ext4 -F -L userdata "${DEVICE}p3"
    
    log "Partition layout created successfully"
}

# Configure RAUC system
configure_rauc() {
    log "Configuring RAUC system..."
    
    # Create RAUC configuration directory
    mkdir -p /etc/rauc
    
    # Create system configuration with version-specific settings
    if grep -q "22.04" /etc/os-release; then
        cat > /etc/rauc/system.conf << 'EOF'
[system]
compatible=jetson-nano-ubuntu2204
bootloader=uboot
max-bundle-download-size=2147483648
bundle-formats=plain
statusfile=/data/rauc.status

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
    else
        cat > /etc/rauc/system.conf << 'EOF'
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
    fi
    
    log "RAUC system configuration created"
}

# Generate RAUC signing keys
generate_keys() {
    log "Generating RAUC signing keys..."
    
    mkdir -p /etc/rauc/certs
    cd /etc/rauc/certs
    
    # Generate Certificate Authority with updated OpenSSL configuration for newer systems
    if grep -q "22.04" /etc/os-release; then
        # For Ubuntu 22.04, use updated OpenSSL configuration
        openssl req -x509 -newkey rsa:4096 -keyout ca-key.pem -out ca-cert.pem -days 7300 -nodes \
            -subj "/C=US/ST=CA/L=San Francisco/O=Homie OS/CN=Homie OS CA" \
            -config <(printf "[req]\ndistinguished_name=req\n[v3_ca]\nbasicConstraints=CA:TRUE")
        
        # Generate development certificate
        openssl req -new -newkey rsa:4096 -keyout dev-key.pem -out dev-req.pem -nodes \
            -subj "/C=US/ST=CA/L=San Francisco/O=Homie OS/CN=Homie OS Dev"
        
        openssl x509 -req -in dev-req.pem -CA ca-cert.pem -CAkey ca-key.pem -out dev-cert.pem -days 365 \
            -extensions v3_req -extfile <(printf "[v3_req]\nkeyUsage=digitalSignature\nextendedKeyUsage=codeSigning")
    else
        # For Ubuntu 20.04, use legacy OpenSSL configuration
        openssl req -x509 -newkey rsa:4096 -keyout ca-key.pem -out ca-cert.pem -days 7300 -nodes \
            -subj "/C=US/ST=CA/L=San Francisco/O=Homie OS/CN=Homie OS CA"
        
        # Generate development certificate
        openssl req -new -newkey rsa:4096 -keyout dev-key.pem -out dev-req.pem -nodes \
            -subj "/C=US/ST=CA/L=San Francisco/O=Homie OS/CN=Homie OS Dev"
        
        openssl x509 -req -in dev-req.pem -CA ca-cert.pem -CAkey ca-key.pem -out dev-cert.pem -days 365
    fi
    
    # Clean up request file
    rm -f dev-req.pem
    
    # Set up keyring
    cp ca-cert.pem /etc/rauc/keyring.pem
    
    # Set appropriate permissions
    chmod 600 *-key.pem
    chmod 644 *-cert.pem
    chmod 644 /etc/rauc/keyring.pem
    
    log "RAUC signing keys generated"
}

# Setup data partition
setup_data_partition() {
    log "Setting up data partition..."
    
    # Create data directory
    mkdir -p /data
    
    # Add to fstab for persistent mounting
    if ! grep -q "/data" /etc/fstab; then
        echo "/dev/mmcblk0p3 /data ext4 defaults,nofail 0 2" >> /etc/fstab
    fi
    
    # Mount data partition
    mount -a
    
    # Verify mount
    if mountpoint -q /data; then
        log "Data partition mounted successfully"
    else
        error "Failed to mount data partition"
        exit 1
    fi
    
    # Create standard directories
    mkdir -p /data/{app,system,backups,logs}
    chmod 755 /data/*
    
    log "Data partition setup completed"
}

# Copy current system to slot A
copy_system() {
    log "Copying current system to slot A..."
    
    # Mount slot A
    mkdir -p /mnt/rootfs_a
    mount /dev/mmcblk0p1 /mnt/rootfs_a
    
    # Copy current system (excluding special directories)
    rsync -aHAXx \
        --exclude=/proc \
        --exclude=/sys \
        --exclude=/dev \
        --exclude=/tmp \
        --exclude=/media \
        --exclude=/mnt \
        --exclude=/data \
        --exclude=/var/cache \
        --exclude=/var/log/journal \
        / /mnt/rootfs_a/
    
    # Update fstab in new root
    sed -i 's|^[^#]*\s/\s|/dev/mmcblk0p1 / |' /mnt/rootfs_a/etc/fstab
    
    # Ensure data partition entry exists
    if ! grep -q "/data" /mnt/rootfs_a/etc/fstab; then
        echo "/dev/mmcblk0p3 /data ext4 defaults,nofail 0 2" >> /mnt/rootfs_a/etc/fstab
    fi
    
    # Clean up sensitive data
    rm -f /mnt/rootfs_a/etc/ssh/ssh_host_*
    rm -f /mnt/rootfs_a/root/.bash_history
    find /mnt/rootfs_a/home -name ".bash_history" -delete 2>/dev/null || true
    
    # Unmount
    umount /mnt/rootfs_a
    rmdir /mnt/rootfs_a
    
    log "System copied to slot A successfully"
}

# Enable RAUC service
enable_rauc_service() {
    log "Enabling RAUC service..."
    
    # Create systemd service override with version-specific configuration
    mkdir -p /etc/systemd/system/rauc.service.d
    
    if grep -q "22.04" /etc/os-release; then
        cat > /etc/systemd/system/rauc.service.d/override.conf << 'EOF'
[Unit]
Description=RAUC Update Service
After=network-online.target
Wants=network-online.target

[Service]
Type=dbus
BusName=de.pengutronix.rauc
ExecStart=/usr/local/bin/rauc service
Environment="RAUC_LOG_LEVEL=info"
Environment="RAUC_STATUSFILE=/data/rauc.status"
Restart=on-failure
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF
    else
        cat > /etc/systemd/system/rauc.service.d/override.conf << 'EOF'
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
EOF
    fi
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable rauc
    systemctl start rauc
    
    # Verify service status
    if systemctl is-active rauc >/dev/null; then
        log "RAUC service enabled and started successfully"
    else
        error "Failed to start RAUC service"
        systemctl status rauc
        exit 1
    fi
}

# Install additional scripts
install_scripts() {
    log "Installing additional scripts..."
    
    # Copy scripts from the repository
    if [[ -d "$SCRIPT_DIR" ]]; then
        cp "$SCRIPT_DIR"/create-update-bundle.sh /usr/local/bin/
        cp "$SCRIPT_DIR"/health-check.sh /usr/local/bin/ 2>/dev/null || true
        cp "$SCRIPT_DIR"/backup-system.sh /usr/local/bin/ 2>/dev/null || true
        
        # Make scripts executable
        chmod +x /usr/local/bin/*.sh
        
        log "Additional scripts installed"
    fi
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    # Check RAUC status
    if rauc status >/dev/null 2>&1; then
        log "✓ RAUC status check passed"
    else
        error "✗ RAUC status check failed"
        exit 1
    fi
    
    # Check partition layout
    if [[ -b /dev/mmcblk0p1 && -b /dev/mmcblk0p2 && -b /dev/mmcblk0p3 ]]; then
        log "✓ Partition layout correct"
    else
        error "✗ Partition layout incorrect"
        exit 1
    fi
    
    # Check mount points
    if mountpoint -q /data; then
        log "✓ Data partition mounted"
    else
        error "✗ Data partition not mounted"
        exit 1
    fi
    
    # Check RAUC service
    if systemctl is-active rauc >/dev/null; then
        log "✓ RAUC service running"
    else
        error "✗ RAUC service not running"
        exit 1
    fi
    
    log "Installation verification completed successfully"
}

# Display final information
show_completion_info() {
    log "Homie OS RAUC setup completed successfully!"
    echo
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    SETUP COMPLETED SUCCESSFULLY                ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${BLUE}System Information:${NC}"
    echo "  • RAUC Version: $(rauc --version 2>/dev/null || echo 'Unknown')"
    echo "  • Current Slot: $(rauc status 2>/dev/null | grep 'booted:' | awk '{print $2}' || echo 'Unknown')"
    echo "  • Data Partition: $(df -h /data | awk 'NR==2 {print $2 " total, " $4 " available"}')"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Reboot the system to test the new partition layout"
    echo "  2. Create your first update bundle: ./create-update-bundle.sh"
    echo "  3. Review documentation in docs/ directory"
    echo "  4. Configure remote update management (optional)"
    echo
    echo -e "${BLUE}Important Files:${NC}"
    echo "  • RAUC Config: /etc/rauc/system.conf"
    echo "  • Certificates: /etc/rauc/certs/"
    echo "  • Backups: $BACKUP_DIR"
    echo "  • Logs: $LOG_FILE"
    echo
    echo -e "${YELLOW}Remember to:${NC}"
    echo "  • Keep your signing keys secure"
    echo "  • Regular backup of /data partition"
    echo "  • Monitor system health after updates"
    echo
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
}

# Main execution
main() {
    log "Starting Homie OS RAUC setup for Jetson Nano"
    
    check_root
    check_system
    create_backup
    install_dependencies
    install_rauc
    configure_uboot
    create_partitions
    configure_rauc
    generate_keys
    setup_data_partition
    copy_system
    enable_rauc_service
    install_scripts
    verify_installation
    show_completion_info
    
    log "Setup completed. Please reboot to activate the new partition layout."
    echo
    read -p "Reboot now? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Rebooting system..."
        reboot
    fi
}

# Handle script interruption
trap 'error "Script interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"
