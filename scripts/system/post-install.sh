#!/bin/bash

# Homie OS Post-Installation Script
# This script runs on first boot to set up the AI stack

set -euo pipefail

# Configuration
HOMIE_DATA_DIR="/data"
AI_STACK_DIR="/opt/homie/ai-stack"
ORCHESTRATOR_DIR="/opt/homie/orchestrator"
LOG_FILE="/var/log/homie-post-install.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date): $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date): $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date): $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date): $1" | tee -a "$LOG_FILE"
}

# Check if first boot setup is needed
if [[ -f "/opt/homie/.setup-complete" ]]; then
    log_info "Homie OS setup already completed. Skipping first-boot setup."
    exit 0
fi

log_info "Starting Homie OS first-boot setup..."

# Ensure data directories exist
log_info "Setting up data directories..."
mkdir -p "$HOMIE_DATA_DIR"/{app,system,backups,logs,ai}
chown -R homie:homie "$HOMIE_DATA_DIR"

# Wait for Docker to be ready
log_info "Waiting for Docker service..."
for i in {1..30}; do
    if docker info >/dev/null 2>&1; then
        log_success "Docker is ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log_error "Docker failed to start after 30 attempts"
        exit 1
    fi
    sleep 2
done

# Add homie user to docker group
log_info "Adding homie user to docker group..."
usermod -aG docker homie

# Deploy AI stack if available
if [[ -d "$AI_STACK_DIR" ]]; then
    log_info "Deploying AI stack..."
    
    # Copy AI stack to data directory for persistence
    cp -r "$AI_STACK_DIR"/* "$HOMIE_DATA_DIR/ai/"
    chown -R homie:homie "$HOMIE_DATA_DIR/ai/"
    
    # Deploy using orchestrator
    cd "$HOMIE_DATA_DIR/ai"
    if [[ -f "docker-compose.yml" ]]; then
        log_info "Starting AI services with Docker Compose..."
        sudo -u homie docker compose up -d
        
        # Wait for services to be ready
        sleep 10
        
        # Check if Ollama is responding
        for i in {1..20}; do
            if curl -f http://localhost:11434/api/version >/dev/null 2>&1; then
                log_success "Ollama is ready"
                break
            fi
            if [[ $i -eq 20 ]]; then
                log_warning "Ollama may not be responding properly"
            fi
            sleep 3
        done
        
        # Initialize Ollama with default models (if setup script exists)
        if [[ -f "$HOMIE_DATA_DIR/ai/init-ollama.sh" ]]; then
            log_info "Initializing Ollama with default models..."
            sudo -u homie bash "$HOMIE_DATA_DIR/ai/init-ollama.sh"
        fi
        
        log_success "AI stack deployed successfully"
    else
        log_warning "No docker-compose.yml found in AI stack directory"
    fi
else
    log_warning "No AI stack found, skipping AI deployment"
fi

# Set up log rotation
log_info "Setting up log rotation..."
cat > /etc/logrotate.d/homie << EOF
/var/log/homie-*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}

$HOMIE_DATA_DIR/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 homie homie
}
EOF

# Create system info script
log_info "Creating system information endpoint..."
cat > /opt/homie/scripts/system-info.sh << 'EOF'
#!/bin/bash
# Homie OS System Information

echo "=== Homie OS System Information ==="
echo "Version: $(cat /etc/homie-version 2>/dev/null || echo 'Unknown')"
echo "Build Info: $(cat /etc/homie-build-info 2>/dev/null || echo 'Unknown')"
echo "Uptime: $(uptime -p)"
echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo "Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')"
echo "Docker: $(docker --version 2>/dev/null || echo 'Not available')"
echo ""
echo "=== Running Services ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not available"
echo ""
echo "=== AI Services ==="
echo "Ollama: $(curl -s http://localhost:11434/api/version 2>/dev/null | jq -r '.version // "Not responding"')"
echo "Open WebUI: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null | grep -q 200 && echo "Running" || echo "Not responding")"
echo "CatGPT: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null | grep -q 200 && echo "Running" || echo "Not responding")"
EOF

chmod +x /opt/homie/scripts/system-info.sh

# Mark setup as complete
log_success "First-boot setup completed successfully"
touch /opt/homie/.setup-complete
chown homie:homie /opt/homie/.setup-complete

log_info "Homie OS is ready! Access the AI interface at:"
log_info "  - Open WebUI: http://$(hostname -I | awk '{print $1}'):8080"
log_info "  - CatGPT: http://$(hostname -I | awk '{print $1}'):3000"
log_info "  - Ollama API: http://$(hostname -I | awk '{print $1}'):11434"

exit 0
