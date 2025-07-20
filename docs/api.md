# API Reference

REST API documentation for remote management of Homie OS RAUC system.

## Overview

The Homie OS management API provides remote control capabilities for RAUC updates, system monitoring, and configuration management. The API is built on top of RAUC's D-Bus interface and provides additional functionality for enterprise deployment.

## Base Configuration

### Service Configuration

```ini
# /etc/systemd/system/homie-api.service
[Unit]
Description=Homie OS Management API
After=network.target rauc.service
Requires=rauc.service

[Service]
Type=simple
ExecStart=/usr/local/bin/homie-api-server
User=root
Group=root
Restart=always
RestartSec=5
Environment=API_PORT=8080
Environment=API_LOG_LEVEL=info

[Install]
WantedBy=multi-user.target
```

### API Server Configuration

```yaml
# /etc/homie/api-config.yaml
server:
  host: "0.0.0.0"
  port: 8080
  ssl:
    enabled: false
    cert_file: "/etc/ssl/certs/homie-api.crt"
    key_file: "/etc/ssl/private/homie-api.key"

authentication:
  enabled: true
  method: "token"  # token, basic, jwt
  token_file: "/etc/homie/api-tokens"

rauc:
  socket_path: "/var/run/rauc"
  config_path: "/etc/rauc/system.conf"
  bundle_download_path: "/tmp/homie-downloads"

logging:
  level: "info"
  file: "/var/log/homie-api.log"
  max_size: "10MB"
  max_backups: 5
```

## Authentication

### Token-Based Authentication

```bash
# Generate API token
API_TOKEN=$(openssl rand -hex 32)
echo "admin:$API_TOKEN" | sudo tee /etc/homie/api-tokens

# Use token in requests
curl -H "Authorization: Bearer $API_TOKEN" \
     http://jetson-nano:8080/api/v1/status
```

### Basic Authentication

```bash
# Configure basic auth
echo "admin:$(openssl passwd -apr1 'your-password')" | sudo tee /etc/homie/api-htpasswd

# Use basic auth in requests
curl -u admin:your-password \
     http://jetson-nano:8080/api/v1/status
```

## API Endpoints

### System Information

#### GET /api/v1/status
Get overall system status including RAUC slot information.

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-15T10:30:00Z",
  "system": {
    "hostname": "jetson-nano-001",
    "uptime": 86400,
    "load_average": [0.5, 0.3, 0.2],
    "memory": {
      "total": 4096,
      "available": 2048,
      "used": 2048
    },
    "disk": {
      "root": {
        "total": 8192,
        "used": 4096,
        "available": 4096
      },
      "data": {
        "total": 16384,
        "used": 2048,
        "available": 14336
      }
    }
  },
  "rauc": {
    "compatible": "jetson-nano",
    "variant": "production",
    "booted": "rootfs.0",
    "slots": {
      "rootfs.0": {
        "class": "rootfs",
        "device": "/dev/mmcblk0p1",
        "type": "ext4",
        "bootname": "a",
        "state": "booted",
        "sha256": "abc123...",
        "size": 8589934592,
        "installed_timestamp": "2024-01-10T08:00:00Z",
        "installed_version": "1.2.0",
        "activated_timestamp": "2024-01-10T08:05:00Z",
        "activated_count": 5
      },
      "rootfs.1": {
        "class": "rootfs",
        "device": "/dev/mmcblk0p2",
        "type": "ext4",
        "bootname": "b",
        "state": "inactive",
        "sha256": "def456...",
        "size": 8589934592,
        "installed_timestamp": "2024-01-05T10:00:00Z",
        "installed_version": "1.1.0"
      }
    }
  }
}
```

#### GET /api/v1/health
Health check endpoint for monitoring systems.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "checks": {
    "rauc_service": "ok",
    "boot_attempts": {
      "status": "ok",
      "current": 0,
      "limit": 3
    },
    "filesystem_space": {
      "status": "ok",
      "root_usage": 50,
      "data_usage": 12
    },
    "critical_services": {
      "status": "ok",
      "services": ["rauc", "dbus", "systemd"]
    }
  }
}
```

#### GET /api/v1/info
Get detailed system and RAUC configuration information.

**Response:**
```json
{
  "system": {
    "compatible": "jetson-nano",
    "variant": "production",
    "bootloader": "uboot",
    "bundle_formats": ["plain", "verity"],
    "max_bundle_size": 2147483648
  },
  "version": {
    "homie_os": "1.0.0",
    "rauc": "1.8.0",
    "api": "1.0.0"
  },
  "hardware": {
    "model": "NVIDIA Jetson Nano Developer Kit",
    "serial": "1234567890",
    "cpu": "ARM Cortex-A57",
    "memory": "4GB",
    "storage": "32GB SD Card"
  }
}
```

### Update Management

#### POST /api/v1/updates/install
Install an update bundle from URL or uploaded file.

**Request (URL):**
```json
{
  "source": "url",
  "url": "https://updates.example.com/homie-os-1.3.0.raucb",
  "verify_ssl": true,
  "progress_callback": "https://callback.example.com/progress"
}
```

**Request (File Upload):**
```bash
curl -X POST \
     -H "Authorization: Bearer $API_TOKEN" \
     -F "bundle=@homie-os-1.3.0.raucb" \
     http://jetson-nano:8080/api/v1/updates/install
```

**Response:**
```json
{
  "status": "accepted",
  "job_id": "update-001",
  "message": "Update installation started",
  "estimated_duration": 300
}
```

#### GET /api/v1/updates/jobs/{job_id}
Get update job status and progress.

**Response:**
```json
{
  "job_id": "update-001",
  "status": "running",
  "progress": 45,
  "stage": "downloading",
  "message": "Downloading bundle from server",
  "started_at": "2024-01-15T10:30:00Z",
  "estimated_completion": "2024-01-15T10:35:00Z",
  "details": {
    "bundle_url": "https://updates.example.com/homie-os-1.3.0.raucb",
    "bundle_size": 1073741824,
    "downloaded": 536870912,
    "target_slot": "rootfs.1"
  }
}
```

#### GET /api/v1/updates/available
Check for available updates from configured update server.

**Response:**
```json
{
  "available": true,
  "updates": [
    {
      "version": "1.3.0",
      "release_date": "2024-01-12T00:00:00Z",
      "size": 1073741824,
      "sha256": "789abc...",
      "url": "https://updates.example.com/homie-os-1.3.0.raucb",
      "changelog": "Security updates and performance improvements",
      "critical": false,
      "compatible": ["jetson-nano"]
    }
  ],
  "current_version": "1.2.0",
  "last_check": "2024-01-15T10:00:00Z"
}
```

#### POST /api/v1/updates/rollback
Rollback to previous slot.

**Request:**
```json
{
  "confirm": true,
  "reboot": true
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Rollback initiated",
  "previous_slot": "rootfs.0",
  "target_slot": "rootfs.1",
  "reboot_scheduled": true,
  "reboot_delay": 30
}
```

### Slot Management

#### POST /api/v1/slots/{slot}/mark
Mark slot status (good, bad, active).

**Request:**
```json
{
  "state": "good"
}
```

**Response:**
```json
{
  "status": "success",
  "slot": "rootfs.1",
  "previous_state": "inactive",
  "new_state": "good"
}
```

#### GET /api/v1/slots
Get detailed information about all slots.

**Response:**
```json
{
  "slots": {
    "rootfs.0": {
      "class": "rootfs",
      "device": "/dev/mmcblk0p1",
      "type": "ext4",
      "bootname": "a",
      "state": "booted",
      "sha256": "abc123...",
      "size": 8589934592,
      "installed_timestamp": "2024-01-10T08:00:00Z",
      "installed_version": "1.2.0",
      "bundle_info": {
        "compatible": "jetson-nano",
        "version": "1.2.0",
        "description": "Production release with security updates"
      }
    }
  }
}
```

### Configuration Management

#### GET /api/v1/config
Get current system configuration.

**Response:**
```json
{
  "rauc": {
    "compatible": "jetson-nano",
    "bootloader": "uboot",
    "max_bundle_size": 2147483648,
    "keyring_path": "/etc/rauc/keyring.pem"
  },
  "update_server": {
    "url": "https://updates.example.com",
    "check_interval": 3600,
    "auto_install": false
  },
  "monitoring": {
    "health_check_interval": 300,
    "log_level": "info"
  }
}
```

#### PUT /api/v1/config
Update system configuration.

**Request:**
```json
{
  "update_server": {
    "url": "https://new-updates.example.com",
    "check_interval": 7200,
    "auto_install": false
  },
  "monitoring": {
    "health_check_interval": 600
  }
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Configuration updated",
  "restart_required": false
}
```

### System Operations

#### POST /api/v1/system/reboot
Reboot the system.

**Request:**
```json
{
  "delay": 30,
  "message": "System maintenance reboot"
}
```

**Response:**
```json
{
  "status": "accepted",
  "message": "Reboot scheduled",
  "delay": 30,
  "scheduled_time": "2024-01-15T10:31:00Z"
}
```

#### POST /api/v1/system/shutdown
Shutdown the system.

**Request:**
```json
{
  "delay": 60
}
```

#### GET /api/v1/system/logs
Get system logs with filtering.

**Query Parameters:**
- `service`: Filter by systemd service (e.g., `rauc`)
- `since`: Time filter (e.g., `1h`, `2024-01-15T10:00:00Z`)
- `level`: Log level filter (`error`, `warning`, `info`, `debug`)
- `lines`: Number of lines to return (default: 100)

**Response:**
```json
{
  "logs": [
    {
      "timestamp": "2024-01-15T10:30:00Z",
      "service": "rauc",
      "level": "info",
      "message": "Slot rootfs.0 marked as good"
    }
  ],
  "total_lines": 1,
  "truncated": false
}
```

## WebSocket API

### Real-time Updates

Connect to WebSocket endpoint for real-time status updates:

```javascript
const ws = new WebSocket('ws://jetson-nano:8080/api/v1/ws');

ws.onmessage = function(event) {
    const data = JSON.parse(event.data);
    console.log('Update:', data);
};

// Subscribe to specific events
ws.send(JSON.stringify({
    action: 'subscribe',
    events: ['update_progress', 'system_health', 'slot_status']
}));
```

### Event Types

```json
{
  "type": "update_progress",
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "job_id": "update-001",
    "progress": 75,
    "stage": "installing",
    "message": "Installing bundle to slot rootfs.1"
  }
}
```

```json
{
  "type": "system_health",
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "status": "healthy",
    "critical_alerts": [],
    "warnings": ["High disk usage on /data partition"]
  }
}
```

## Error Handling

### Standard Error Response

```json
{
  "status": "error",
  "error": {
    "code": "INVALID_BUNDLE",
    "message": "Bundle signature verification failed",
    "details": {
      "bundle_path": "/tmp/update.raucb",
      "verification_error": "Certificate chain validation failed"
    }
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Error Codes

| Code | Description |
|------|-------------|
| `INVALID_REQUEST` | Malformed request or missing parameters |
| `AUTHENTICATION_FAILED` | Invalid or missing authentication |
| `UNAUTHORIZED` | Insufficient permissions |
| `RESOURCE_NOT_FOUND` | Requested resource does not exist |
| `INVALID_BUNDLE` | Bundle validation or signature verification failed |
| `INSUFFICIENT_SPACE` | Not enough disk space for operation |
| `RAUC_ERROR` | RAUC service error |
| `SYSTEM_ERROR` | System-level error |
| `OPERATION_IN_PROGRESS` | Conflicting operation already running |

## Rate Limiting

API requests are rate-limited to prevent abuse:

- **Standard endpoints**: 100 requests per minute
- **Update endpoints**: 10 requests per minute
- **WebSocket connections**: 5 concurrent connections per IP

Rate limit headers are included in responses:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1610707800
```

## SDK Examples

### Python SDK

```python
import requests
import json

class HomieAPI:
    def __init__(self, base_url, token):
        self.base_url = base_url
        self.headers = {'Authorization': f'Bearer {token}'}
    
    def get_status(self):
        response = requests.get(f'{self.base_url}/api/v1/status', 
                              headers=self.headers)
        return response.json()
    
    def install_update(self, bundle_url):
        data = {'source': 'url', 'url': bundle_url}
        response = requests.post(f'{self.base_url}/api/v1/updates/install',
                               json=data, headers=self.headers)
        return response.json()
    
    def get_update_progress(self, job_id):
        response = requests.get(f'{self.base_url}/api/v1/updates/jobs/{job_id}',
                              headers=self.headers)
        return response.json()

# Usage
api = HomieAPI('http://jetson-nano:8080', 'your-api-token')
status = api.get_status()
print(f"Current slot: {status['rauc']['booted']}")
```

### Bash Scripts

```bash
#!/bin/bash
# update-fleet.sh

API_TOKEN="your-api-token"
UPDATE_URL="https://updates.example.com/latest.raucb"

DEVICES=(
    "jetson-nano-001:8080"
    "jetson-nano-002:8080"
    "jetson-nano-003:8080"
)

for device in "${DEVICES[@]}"; do
    echo "Updating $device..."
    
    # Start update
    job_id=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
                  -H "Content-Type: application/json" \
                  -d "{\"source\":\"url\",\"url\":\"$UPDATE_URL\"}" \
                  "http://$device/api/v1/updates/install" | \
             jq -r '.job_id')
    
    # Monitor progress
    while true; do
        status=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
                      "http://$device/api/v1/updates/jobs/$job_id" | \
                 jq -r '.status')
        
        if [ "$status" = "completed" ]; then
            echo "$device: Update completed successfully"
            break
        elif [ "$status" = "failed" ]; then
            echo "$device: Update failed"
            break
        fi
        
        sleep 10
    done
done
```

## Security Considerations

1. **HTTPS**: Always use HTTPS in production
2. **Authentication**: Implement strong token-based authentication
3. **Authorization**: Use role-based access control
4. **Rate Limiting**: Prevent API abuse
5. **Input Validation**: Validate all input parameters
6. **Audit Logging**: Log all API operations
7. **Network Security**: Restrict API access to trusted networks
8. **Certificate Management**: Rotate API certificates regularly

This API provides comprehensive remote management capabilities while maintaining security and reliability for production deployments.
