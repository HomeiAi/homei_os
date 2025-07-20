# Homie OS
🔧 Turn your Jetson Nano into an enterprise-grade embedded system with A/B partition updates, automatic recovery, and persistent storage. No more risky apt upgrades!

## Overview

Homie OS transforms your NVIDIA Jetson Nano into a production-ready embedded system using RAUC (Robust Auto-Update Client) for atomic updates. This implementation provides:

- **🔄 Atomic Updates**: Complete OS replacement with zero partial states
- **🛡️ Automatic Rollback**: Instant recovery on boot failure
- **📁 Persistent Storage**: User data survives all OS updates
- **⚡ Zero Downtime**: Update inactive partition while system runs
- **🏭 Enterprise Ready**: Production-grade reliability for edge devices

## Key Features

### A/B Partition System
- **Slot A & B**: Dual root filesystems for atomic switching
- **Persistent Data**: Separate `/data` partition for user content
- **Boot Protection**: U-Boot integration for reliable boot selection

### Update Mechanism
- **RAUC Integration**: Industry-standard update client
- **Signed Bundles**: Cryptographic verification of updates
- **Health Monitoring**: Automatic rollback on system failure
- **Remote Management**: API-driven update deployment

## Quick Start

1. **Flash Base System**: Start with JetPack 4.6.x on Jetson Nano
2. **Run Setup Script**: Execute our automated installation
3. **Configure Partitions**: Set up A/B root and data partitions
4. **Deploy Updates**: Create and install signed update bundles

```bash
# Clone repository
git clone https://github.com/Homie-Ai-project/homie_os.git
cd homie_os

# Run automated setup
sudo ./scripts/setup-rauc-jetson.sh

# Create your first update bundle
./scripts/create-update-bundle.sh
```

## Documentation

- [Installation Guide](docs/installation.md) - Complete setup instructions
- [Partition Layout](docs/partition-layout.md) - Understanding the A/B system
- [Update Process](docs/update-process.md) - Creating and deploying updates
- [Configuration Reference](docs/configuration.md) - RAUC and system configuration
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [API Reference](docs/api.md) - Remote management interface

## Architecture

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

## Requirements

- **Hardware**: NVIDIA Jetson Nano (4GB recommended)
- **Storage**: 32GB+ SD card or eMMC
- **Base OS**: Ubuntu 20.04 LTS (JetPack 4.6.x)
- **Network**: Internet connection for initial setup

## Support

- 📚 [Documentation](docs/)
- 🐛 [Issue Tracker](https://github.com/Homie-Ai-project/homie_os/issues)
- 💬 [Discussions](https://github.com/Homie-Ai-project/homie_os/discussions)
- 📧 [Contact](mailto:support@homieos.com)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

---

**⚠️ Important**: This system modifies boot partitions and requires careful setup. Always backup your data before installation.
