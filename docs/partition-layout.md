# Partition Layout

Understanding the A/B partition system used in Homie OS for atomic updates.

## Overview

Homie OS uses a dual-partition (A/B) system that ensures atomic updates and reliable rollback capabilities. This design is based on Android's A/B update mechanism and is widely used in embedded systems requiring high reliability.

## Physical Layout

### SD Card Layout (32GB Example)

```
┌─────────────────────────────────────────────────────────────┐
│                    SD Card (32GB)                           │
├─────────────────┬─────────────────┬─────────────────────────┤
│   Slot A        │   Slot B        │     User Data           │
│  /dev/mmcblk0p1 │  /dev/mmcblk0p2 │    /dev/mmcblk0p3      │
│   (rootfs_a)    │   (rootfs_b)    │    (userdata)          │
│   8GB - ext4    │   8GB - ext4    │   16GB - ext4          │
│   1MiB - 8GiB   │  8GiB - 16GiB   │  16GiB - 100%          │
└─────────────────┴─────────────────┴─────────────────────────┘
```

### For Different SD Card Sizes

#### 16GB SD Card
```
Slot A: 6GB (1MiB - 6GiB)
Slot B: 6GB (6GiB - 12GiB)
Data:   4GB (12GiB - 100%)
```

#### 64GB SD Card
```
Slot A: 16GB (1MiB - 16GiB)
Slot B: 16GB (16GiB - 32GiB)
Data:   32GB (32GiB - 100%)
```

## Partition Functions

### Partition 1 - Slot A (rootfs_a)
- **Device**: `/dev/mmcblk0p1`
- **Label**: `rootfs_a`
- **Size**: 8GB (configurable)
- **Type**: ext4
- **Mount**: `/` (when active)
- **Purpose**: Complete OS installation (bootable root filesystem)

**Contains**:
- Linux kernel and device tree
- System libraries and binaries
- Application software
- System configuration files
- Boot scripts and services

### Partition 2 - Slot B (rootfs_b)
- **Device**: `/dev/mmcblk0p2`
- **Label**: `rootfs_b`
- **Size**: 8GB (configurable)
- **Type**: ext4
- **Mount**: `/` (when active)
- **Purpose**: Backup/update OS installation

**Contains**:
- Identical structure to Slot A
- Used for atomic updates
- Becomes active after successful update

### Partition 3 - User Data (userdata)
- **Device**: `/dev/mmcblk0p3`
- **Label**: `userdata`
- **Size**: Remaining space (16GB in example)
- **Type**: ext4
- **Mount**: `/data` (always mounted)
- **Purpose**: Persistent application data storage

**Contains**:
- Application configurations
- User files and databases
- Log files
- Container volumes
- Any data that should survive OS updates

## Boot Process Flow

```
┌─────────┐    ┌──────────────┐    ┌─────────────┐    ┌─────────────┐
│ U-Boot  │───▶│ Check Boot   │───▶│ Mount Active│───▶│ Mount /data │
│         │    │ Slot (A/B)   │    │ Rootfs      │    │ Partition   │
└─────────┘    └──────────────┘    └─────────────┘    └─────────────┘
```

### Boot Slot Selection

U-Boot determines which slot to boot from based on:

1. **RAUC Slot State**: Current active slot (A or B)
2. **Boot Counter**: Attempts remaining for current slot
3. **Health Check**: System health verification
4. **Fallback Logic**: Automatic switch on boot failure

## Update Process States

### Before Update
```
Slot A: ✅ Active (booted from)
Slot B: 💤 Inactive (standby)
Data:   📁 Always mounted at /data
```

### During Update
```
Slot A: ✅ Active (current running system)
Slot B: 🔄 Being updated (new image written)
Data:   📁 Untouched, continues operation
```

### After Successful Update
```
Slot A: 💤 Inactive (previous version available for rollback)
Slot B: ✅ Active (new version running)
Data:   📁 Same content, survives update
```

### After Failed Update (Automatic Rollback)
```
Slot A: ✅ Active (rolled back to previous version)
Slot B: ❌ Inactive (failed update, marked bad)
Data:   📁 Same content, unaffected
```

## Partition Configuration

### Creating Custom Partition Layout

For different requirements, you can adjust the partition sizes:

```bash
# For development (smaller OS partitions)
sudo parted /dev/mmcblk0 --script -- \
  mklabel gpt \
  mkpart primary ext4 1MiB 4GiB \
  mkpart primary ext4 4GiB 8GiB \
  mkpart primary ext4 8GiB 100%

# For production (larger OS partitions)
sudo parted /dev/mmcblk0 --script -- \
  mklabel gpt \
  mkpart primary ext4 1MiB 12GiB \
  mkpart primary ext4 12GiB 24GiB \
  mkpart primary ext4 24GiB 100%
```

### Partition Alignment

- **Start**: 1MiB boundary for optimal performance
- **Alignment**: 4K sectors for modern storage
- **End**: Percentage-based for flexibility across card sizes

## Data Persistence Strategy

### What Goes in `/data`

```
/data/
├── app/                    # Application data
│   ├── configs/           # Configuration files
│   ├── databases/         # Application databases
│   └── logs/              # Application logs
├── docker/                # Docker volumes and data
├── user/                  # User-specific files
├── cache/                 # Persistent cache data
└── backups/               # System and app backups
```

### Symlinks for Persistence

Critical application data can be symlinked to `/data`:

```bash
# Example: Docker data
sudo ln -sf /data/docker /var/lib/docker

# Example: Application logs
sudo ln -sf /data/app/logs /var/log/myapp
```

## Key Benefits

### 🔄 Atomic Updates
- Complete image replacement eliminates partial update states
- Either fully successful or completely rolled back
- No broken system states possible

### ⚡ Instant Rollback
- Switch boot slot in seconds on failure
- Previous version always available
- No downtime for recovery

### 📊 Zero Downtime Updates
- Update inactive slot while system runs normally
- No service interruption during update process
- Switch happens only at next reboot

### 💾 Data Persistence
- `/data` partition survives all OS updates
- Application data and configurations preserved
- Clear separation of OS and user data

### 🏗️ Space Efficiency
- Only 2x OS storage needed (vs 3x for some systems)
- Efficient use of available storage
- Configurable partition sizes based on needs

## Monitoring and Verification

### Check Current Layout
```bash
# View partition table
sudo parted /dev/mmcblk0 print

# Check filesystem labels
sudo blkid

# View mounted filesystems
df -h
```

### Verify RAUC Configuration
```bash
# Check RAUC status
sudo rauc status

# View slot information
sudo rauc status --detailed

# Check system configuration
sudo rauc info
```

## Troubleshooting

### Common Issues

1. **Partition Size Too Small**: Increase OS partition size
2. **Boot Failure**: Check U-Boot environment variables
3. **Mount Issues**: Verify `/etc/fstab` entries
4. **Update Failures**: Check available space and permissions

### Recovery Procedures

See the [Troubleshooting Guide](troubleshooting.md) for detailed recovery procedures.

## Best Practices

1. **Size OS Partitions**: Allow 20% extra space for updates
2. **Monitor Disk Usage**: Keep `/data` partition below 80%
3. **Regular Backups**: Backup `/data` partition regularly
4. **Test Updates**: Always test in development environment first
5. **Health Monitoring**: Implement application health checks
