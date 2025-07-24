# Homie OS
🔧 Complete AI platform for Jetson devices with enterprise-grade updates, automatic recovery, and instant AI deployment. Transform your Jetson into a production-ready AI system!

## Overview

Homie OS is a complete AI platform that transforms your NVIDIA Jetson device into a production-ready embedded AI system. It combines:

- **🔄 Atomic Updates**: Complete OS replacement with zero partial states using RAUC
- **🛡️ Automatic Rollback**: Instant recovery on boot failure  
- **📁 Persistent Storage**: User data and AI models survive all OS updates
- **⚡ Zero Downtime**: Update inactive partition while system runs
- **🤖 Complete AI Stack**: Ollama, Open WebUI, and CatGPT auto-deployed
- **🏭 Enterprise Ready**: Production-grade reliability for edge AI devices

## 🎯 What You Get

**Complete AI Platform Out-of-the-Box:**
- **Ollama** - Local LLM inference engine (port 11434)
- **Open WebUI** - Modern chat interface (port 8080) 
- **CatGPT** - React-based frontend (port 3000)
- **Homie Orchestrator** - Container management API (port 8000)

**Enterprise Features:**
- A/B partition updates with automatic rollback
- Persistent data across all OS updates
- Systemd services for all components
- Comprehensive logging and monitoring
- API-driven remote management

## Key Features

### 🤖 Complete AI Platform
- **Ollama Integration**: Local LLM inference with GPU acceleration
- **Multiple Interfaces**: Open WebUI and custom CatGPT frontend
- **Model Management**: Automatic initialization with popular models
- **API Access**: Full REST API for AI operations

### 🔄 A/B Partition System
- **Slot A & B**: Dual root filesystems for atomic switching
- **Persistent Data**: Separate `/data` partition for user content and AI models
- **Boot Protection**: U-Boot integration for reliable boot selection

### 🚀 Automatic Deployment
- **First Boot Setup**: Complete AI stack deployed automatically
- **Service Management**: All components managed via systemd
- **Container Orchestration**: Docker Compose for service coordination
- **Health Monitoring**: Automatic service health checks

### 📦 Update Mechanism
- **RAUC Integration**: Industry-standard update client
- **Signed Bundles**: Cryptographic verification of updates
- **AI Persistence**: Models and data survive OS updates
- **Remote Management**: API-driven update deployment

## 🚀 Quick Start

### **Instant AI Platform**

1. **Flash Homie OS** to your Jetson device
2. **Boot and wait** ~2-3 minutes for automatic AI stack deployment  
3. **Access your AI services**:
   - **Open WebUI**: `http://YOUR_JETSON_IP:8080`
   - **CatGPT**: `http://YOUR_JETSON_IP:3000`
   - **Ollama API**: `http://YOUR_JETSON_IP:11434`

### **Development Setup**

```bash
# Clone repository
git clone https://github.com/Homie-Ai-project/homie_os.git
cd homie_os

# Configure for your platform (example: Jetson Orin Nano)
./scripts/load-config.sh set TARGET_PLATFORM jetson-orin-nano
./scripts/load-config.sh set RAUC_COMPATIBLE jetson-orin-nano

# Build complete system with AI stack
./scripts/docker-build.sh

# Create installation bundle
./scripts/create-docker-bundle.sh build/rootfs 1.0.0-beta.1

## 🧠 **What's Included**

### **AI Services (Auto-Deployed)**
- **Ollama**: Local LLM inference engine with GPU acceleration
- **Open WebUI**: Modern, responsive chat interface
- **CatGPT**: Custom React-based AI frontend
- **Popular Models**: Llama 3.2, Mistral, CodeLlama automatically downloaded

### **System Services**
- **Homie Orchestrator**: Container and service management
- **Docker Engine**: Container runtime with GPU support
- **RAUC**: Atomic update system
- **NetworkManager**: Network configuration
- **SSH**: Secure remote access

### **Development Tools**
- **Python 3**: With FastAPI, PyTorch support
- **Git**: Version control
- **Build tools**: gcc, make, development headers
- **System utilities**: htop, curl, vim, nano

```bash
# Create your first update bundle
./scripts/create-update-bundle.sh
```

## 🏗️ **Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│                        Homie OS                            │
│  ┌─────────────────┬─────────────────┬─────────────────────┐ │
│  │   Slot A        │   Slot B        │     User Data       │ │
│  │  /dev/mmcblk0p1 │  /dev/mmcblk0p2 │    /dev/mmcblk0p3   │ │
│  │   (rootfs_a)    │   (rootfs_b)    │    (userdata)       │ │
│  │   8GB - ext4    │   8GB - ext4    │   16GB - ext4       │ │
│  └─────────────────┴─────────────────┴─────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                   Homie Orchestrator                       │
│              Service Management Layer                      │
├─────────────────────────────────────────────────────────────┤
│                    Homie AI Stack                          │
│        Ollama + Open WebUI + CatGPT Interface             │
└─────────────────────────────────────────────────────────────┘
```

## Requirements

- **Hardware**: NVIDIA Jetson Nano (4GB recommended)
- **Storage**: 32GB+ SD card or eMMC
- **Base OS**: Ubuntu 20.04 LTS (JetPack 4.6.x)
- **Network**: Internet connection for initial setup

## Documentation

- 🏗️ [Installation Architecture](docs/installation-architecture.md) - **NEW! Complete system overview**
- 🛠️ [Configuration Management](docs/configuration-management.md) - Centralized configuration system
- 📋 [Configuration Variables](docs/configuration-variables.md) - Complete variable reference  
- ⚡ [Quick Reference](docs/quick-reference.md) - Common configuration commands
- 📦 [Installation Guide](docs/installation.md) - Complete setup instructions
- 🔄 [Partition Layout](docs/partition-layout.md) - Understanding the A/B system
- 🚀 [Update Process](docs/update-process.md) - Creating and deploying updates
- ⚙️ [Configuration Reference](docs/configuration.md) - RAUC and system configuration
- 🐛 [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- 🔌 [API Reference](docs/api.md) - Remote management interface

## Support

- 📚 [Documentation](docs/)
- �️ [Configuration Variables Guide](docs/configuration-variables.md)
- ⚡ [Quick Reference](docs/quick-reference.md)
- 🔄 [CI/CD Documentation](docs/ci-cd.md)
- �🐛 [Issue Tracker](https://github.com/Homie-Ai-project/homie_os/issues)
- 💬 [Discussions](https://github.com/Homie-Ai-project/homie_os/discussions)
- 📧 [Contact](mailto:support@homieos.com)

## 🎯 Centralized Configuration

The entire system now uses **one configuration file**: `config/variables.conf`

```bash
# View all configuration variables
./scripts/load-config.sh list

# Update any variable (automatically validated)
./scripts/load-config.sh set L4T_VERSION r36.3.0

# Validate entire configuration  
./scripts/load-config.sh validate

# Generate build files (templates → actual files)
./scripts/generate-dockerfile.sh
```

See [Configuration Management Guide](docs/configuration-management.md) for complete details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

---

**⚠️ Important**: This system modifies boot partitions and requires careful setup. Always backup your data before installation.
