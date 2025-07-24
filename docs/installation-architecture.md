# Homie OS Complete Installation Architecture

## 🏗️ **Three-Layer Architecture**

Homie OS now provides a complete, integrated platform with automatic deployment of all components:

```
┌─────────────────────────────────────────────────────────────┐
│                        Homie OS                            │
│              Base OS with RAUC Updates                     │
├─────────────────────────────────────────────────────────────┤
│                   Homie Orchestrator                       │
│              Service Management Layer                      │
├─────────────────────────────────────────────────────────────┤
│                    Homie AI Stack                          │
│        Ollama + Open WebUI + CatGPT Interface             │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 **Installation Flow**

### **1. Homie OS Base System**
- **Base**: NVIDIA L4T r36.2.0 with JetPack 6.0
- **Updates**: RAUC atomic update system
- **Storage**: A/B partition layout with persistent data
- **Services**: Docker, SSH, NetworkManager

### **2. Homie Orchestrator (Auto-Installed)**
- **Location**: `/opt/homie/orchestrator/`
- **Service**: `homie-orchestrator.service`
- **Purpose**: Container management and service orchestration
- **API**: REST API for system management
- **Dependencies**: Automatically installed with Python packages

### **3. Homie AI Stack (Auto-Deployed)**
- **Location**: `/data/ai/` (persistent across updates)
- **Services**: 
  - **Ollama**: Local LLM inference (`localhost:11434`)
  - **Open WebUI**: Modern chat interface (`localhost:8080`)
  - **CatGPT**: React-based frontend (`localhost:3000`)
- **Deployment**: Automatic on first boot via Docker Compose

## 🔄 **First Boot Process**

When Homie OS starts for the first time:

1. **System Initialization**
   - Configure data directories
   - Set up user permissions
   - Wait for Docker service

2. **AI Stack Deployment**
   - Copy AI stack to persistent storage (`/data/ai/`)
   - Run `docker compose up -d`
   - Initialize Ollama with default models
   - Verify all services are responding

3. **System Configuration**
   - Set up log rotation
   - Create system info endpoints
   - Mark setup as complete

## 📁 **Directory Structure**

```
/opt/homie/
├── orchestrator/          # Homie Orchestrator (from homie_orchestrator repo)
│   ├── src/               # Orchestrator source code
│   ├── requirements.txt   # Python dependencies
│   └── scripts/           # Management scripts
├── ai/                    # AI stack templates (from homie_ai repo)
│   ├── docker-compose.yml # AI services definition
│   ├── init-ollama.sh     # Model initialization
│   └── catGPT/           # React frontend
├── config/                # System configuration
├── scripts/               # System scripts
└── .setup-complete        # First-boot completion marker

/data/                     # Persistent storage (survives updates)
├── ai/                    # Active AI stack (copied from /opt/homie/ai/)
├── app/                   # Application data
├── system/                # System data
├── backups/               # Backup storage
└── logs/                  # Application logs
```

## 🛠️ **Services and Ports**

### **System Services**
- `homie-orchestrator.service` - Container orchestration
- `homie-first-boot.service` - First-boot setup (one-time)
- `docker.service` - Container runtime
- `ssh.service` - Remote access

### **AI Services (Auto-Deployed)**
- **Ollama**: `localhost:11434` - LLM API endpoint
- **Open WebUI**: `localhost:8080` - Modern chat interface
- **CatGPT**: `localhost:3000` - React frontend
- **Orchestrator API**: `localhost:8000` - System management

## 🔧 **Build Integration**

The build process now automatically includes all components:

```dockerfile
# Copy all Homie projects
COPY homie_orchestrator/ /opt/homie/orchestrator/
COPY homie_ai/ /opt/homie/ai/
COPY homie_os/config/ /opt/homie/config/

# Install orchestrator dependencies
RUN pip3 install -r /opt/homie/orchestrator/requirements.txt

# Enable services
RUN systemctl enable homie-orchestrator
RUN systemctl enable homie-first-boot
```

## 🚀 **User Experience**

### **After Installation/Update**
1. **Flash Homie OS** to your Jetson device
2. **Boot the system** - first boot takes ~2-3 minutes for AI stack deployment
3. **Access services**:
   - Open WebUI: `http://DEVICE_IP:8080`
   - CatGPT: `http://DEVICE_IP:3000` 
   - Ollama API: `http://DEVICE_IP:11434`

### **System Information**
```bash
# Check system status
/opt/homie/scripts/system-info.sh

# View services
docker ps

# Check logs
journalctl -u homie-orchestrator
journalctl -u homie-first-boot
```

## 📦 **Update Behavior**

- **OS Updates**: RAUC atomic updates preserve `/data/` directory
- **AI Stack**: Persists in `/data/ai/` across OS updates  
- **Configuration**: Maintained in persistent storage
- **Models**: Ollama models stored in persistent Docker volumes

## 🎯 **Benefits**

✅ **Complete Solution**: Everything installed automatically  
✅ **Update Safe**: AI stack and data persist across OS updates  
✅ **Production Ready**: Services start automatically on boot  
✅ **User Friendly**: Access web interfaces immediately  
✅ **Maintainable**: Clear separation of concerns  
✅ **Extensible**: Easy to add more AI services  

The system now provides a complete, turn-key AI platform that's ready to use immediately after installation! 🚀
