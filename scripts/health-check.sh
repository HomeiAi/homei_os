#!/bin/bash
# System health check script for Homie OS
# Part of Homie OS - Enterprise-grade embedded system

set -e

# Configuration
LOG_FILE="/var/log/homie-health.log"
ALERT_THRESHOLD_ROOT=90
ALERT_THRESHOLD_DATA=85
BOOT_ATTEMPTS_WARNING=2
BOOT_ATTEMPTS_CRITICAL=3

# Exit codes
EXIT_OK=0
EXIT_WARNING=1
EXIT_CRITICAL=2
EXIT_UNKNOWN=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Status tracking
OVERALL_STATUS=$EXIT_OK
WARNINGS=()
CRITICALS=()

# Add warning
add_warning() {
    WARNINGS+=("$1")
    if [[ $OVERALL_STATUS -eq $EXIT_OK ]]; then
        OVERALL_STATUS=$EXIT_WARNING
    fi
}

# Add critical
add_critical() {
    CRITICALS+=("$1")
    OVERALL_STATUS=$EXIT_CRITICAL
}

# Check RAUC service status
check_rauc_service() {
    echo -e "${BLUE}Checking RAUC service...${NC}"
    
    if systemctl is-active rauc >/dev/null 2>&1; then
        echo "✓ RAUC service is running"
    else
        add_critical "RAUC service is not running"
        return
    fi
    
    # Check RAUC status
    if rauc status >/dev/null 2>&1; then
        echo "✓ RAUC status check passed"
    else
        add_critical "RAUC status check failed"
        return
    fi
    
    # Get current slot information
    local current_slot=$(rauc status 2>/dev/null | grep 'booted:' | awk '{print $2}' || echo "unknown")
    echo "  Current slot: $current_slot"
    
    # Check slot status
    local slot_status=$(rauc status --detailed 2>/dev/null | grep -A 5 "^$current_slot:" | grep "state:" | awk '{print $2}' || echo "unknown")
    if [[ "$slot_status" == "booted" ]]; then
        echo "✓ Current slot status is healthy"
    else
        add_warning "Current slot status: $slot_status"
    fi
}

# Check boot attempts
check_boot_attempts() {
    echo -e "${BLUE}Checking boot attempts...${NC}"
    
    if command -v fw_printenv >/dev/null 2>&1; then
        local boot_attempts=$(fw_printenv bootcount 2>/dev/null | cut -d= -f2 || echo "0")
        
        if [[ $boot_attempts -ge $BOOT_ATTEMPTS_CRITICAL ]]; then
            add_critical "High boot attempt count: $boot_attempts"
        elif [[ $boot_attempts -ge $BOOT_ATTEMPTS_WARNING ]]; then
            add_warning "Elevated boot attempt count: $boot_attempts"
        else
            echo "✓ Boot attempt count is normal: $boot_attempts"
        fi
    else
        add_warning "Cannot check boot attempts (fw_printenv not available)"
    fi
}

# Check filesystem space
check_filesystem_space() {
    echo -e "${BLUE}Checking filesystem space...${NC}"
    
    # Check root filesystem
    local root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $root_usage -ge $ALERT_THRESHOLD_ROOT ]]; then
        add_critical "Root filesystem is ${root_usage}% full"
    elif [[ $root_usage -ge $((ALERT_THRESHOLD_ROOT - 10)) ]]; then
        add_warning "Root filesystem is ${root_usage}% full"
    else
        echo "✓ Root filesystem usage: ${root_usage}%"
    fi
    
    # Check data filesystem
    if mountpoint -q /data; then
        local data_usage=$(df /data | awk 'NR==2 {print $5}' | sed 's/%//')
        if [[ $data_usage -ge $ALERT_THRESHOLD_DATA ]]; then
            add_warning "Data filesystem is ${data_usage}% full"
        else
            echo "✓ Data filesystem usage: ${data_usage}%"
        fi
    else
        add_critical "Data filesystem is not mounted"
    fi
}

# Check critical services
check_critical_services() {
    echo -e "${BLUE}Checking critical services...${NC}"
    
    local services=("systemd" "dbus" "rauc")
    local failed_services=()
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo "✓ $service is running"
        else
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        add_critical "Critical services not running: ${failed_services[*]}"
    fi
}

# Check system load
check_system_load() {
    echo -e "${BLUE}Checking system load...${NC}"
    
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_count=$(nproc)
    local load_threshold=$((cpu_count * 2))
    
    if (( $(echo "$load_avg > $load_threshold" | bc -l) )); then
        add_warning "High system load: $load_avg (threshold: $load_threshold)"
    else
        echo "✓ System load is normal: $load_avg"
    fi
}

# Check memory usage
check_memory_usage() {
    echo -e "${BLUE}Checking memory usage...${NC}"
    
    local mem_info=$(free | grep '^Mem:')
    local total_mem=$(echo $mem_info | awk '{print $2}')
    local used_mem=$(echo $mem_info | awk '{print $3}')
    local mem_usage=$((used_mem * 100 / total_mem))
    
    if [[ $mem_usage -ge 90 ]]; then
        add_critical "High memory usage: ${mem_usage}%"
    elif [[ $mem_usage -ge 80 ]]; then
        add_warning "Elevated memory usage: ${mem_usage}%"
    else
        echo "✓ Memory usage is normal: ${mem_usage}%"
    fi
}

# Check storage health
check_storage_health() {
    echo -e "${BLUE}Checking storage health...${NC}"
    
    # Check for I/O errors in dmesg
    local io_errors=$(dmesg | grep -i "i/o error" | wc -l)
    if [[ $io_errors -gt 0 ]]; then
        add_warning "Found $io_errors I/O errors in system log"
    fi
    
    # Check for MMC/SD card errors
    local mmc_errors=$(dmesg | grep -i "mmc.*error" | wc -l)
    if [[ $mmc_errors -gt 0 ]]; then
        add_warning "Found $mmc_errors MMC/SD card errors in system log"
    fi
    
    if [[ $io_errors -eq 0 && $mmc_errors -eq 0 ]]; then
        echo "✓ No storage errors detected"
    fi
}

# Check network connectivity
check_network() {
    echo -e "${BLUE}Checking network connectivity...${NC}"
    
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "✓ Network connectivity is working"
    else
        add_warning "Network connectivity test failed"
    fi
}

# Check temperature (if available)
check_temperature() {
    echo -e "${BLUE}Checking system temperature...${NC}"
    
    local temp_file="/sys/class/thermal/thermal_zone0/temp"
    if [[ -f "$temp_file" ]]; then
        local temp=$(cat "$temp_file")
        local temp_celsius=$((temp / 1000))
        
        if [[ $temp_celsius -ge 80 ]]; then
            add_critical "High system temperature: ${temp_celsius}°C"
        elif [[ $temp_celsius -ge 70 ]]; then
            add_warning "Elevated system temperature: ${temp_celsius}°C"
        else
            echo "✓ System temperature is normal: ${temp_celsius}°C"
        fi
    else
        echo "  Temperature monitoring not available"
    fi
}

# Check partition health
check_partitions() {
    echo -e "${BLUE}Checking partition health...${NC}"
    
    # Check if all expected partitions exist
    local partitions=("/dev/mmcblk0p1" "/dev/mmcblk0p2" "/dev/mmcblk0p3")
    for partition in "${partitions[@]}"; do
        if [[ -b "$partition" ]]; then
            echo "✓ Partition $partition exists"
        else
            add_critical "Missing partition: $partition"
        fi
    done
    
    # Check filesystem consistency (read-only check)
    for partition in "${partitions[@]}"; do
        if [[ -b "$partition" ]]; then
            if tune2fs -l "$partition" >/dev/null 2>&1; then
                local fs_state=$(tune2fs -l "$partition" 2>/dev/null | grep "Filesystem state" | awk -F: '{print $2}' | xargs)
                if [[ "$fs_state" == "clean" ]]; then
                    echo "✓ Filesystem on $partition is clean"
                else
                    add_warning "Filesystem on $partition state: $fs_state"
                fi
            fi
        fi
    done
}

# Generate health report
generate_report() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                        HEALTH CHECK REPORT                     ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo
    
    # Overall status
    case $OVERALL_STATUS in
        $EXIT_OK)
            echo -e "Overall Status: ${GREEN}HEALTHY${NC}"
            ;;
        $EXIT_WARNING)
            echo -e "Overall Status: ${YELLOW}WARNING${NC}"
            ;;
        $EXIT_CRITICAL)
            echo -e "Overall Status: ${RED}CRITICAL${NC}"
            ;;
        *)
            echo -e "Overall Status: ${RED}UNKNOWN${NC}"
            ;;
    esac
    
    echo "Timestamp: $(date)"
    echo
    
    # Critical issues
    if [[ ${#CRITICALS[@]} -gt 0 ]]; then
        echo -e "${RED}Critical Issues:${NC}"
        for issue in "${CRITICALS[@]}"; do
            echo "  ❌ $issue"
        done
        echo
    fi
    
    # Warnings
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warnings:${NC}"
        for warning in "${WARNINGS[@]}"; do
            echo "  ⚠️  $warning"
        done
        echo
    fi
    
    # Recommendations
    if [[ $OVERALL_STATUS -ne $EXIT_OK ]]; then
        echo -e "${BLUE}Recommendations:${NC}"
        
        if [[ ${#CRITICALS[@]} -gt 0 ]]; then
            echo "  • Address critical issues immediately"
            echo "  • Consider system reboot or rollback if issues persist"
            echo "  • Check system logs: journalctl -xe"
        fi
        
        if [[ ${#WARNINGS[@]} -gt 0 ]]; then
            echo "  • Monitor warning conditions"
            echo "  • Schedule maintenance during next window"
            echo "  • Review system performance and capacity"
        fi
        
        echo "  • Check detailed logs: $LOG_FILE"
        echo
    fi
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

# Send alerts (if configured)
send_alerts() {
    if [[ $OVERALL_STATUS -eq $EXIT_CRITICAL ]]; then
        # Send critical alerts
        if command -v mail >/dev/null 2>&1 && [[ -n "${ALERT_EMAIL:-}" ]]; then
            {
                echo "Subject: [CRITICAL] Homie OS Health Check Failed on $(hostname)"
                echo
                echo "Critical health check failure detected:"
                for issue in "${CRITICALS[@]}"; do
                    echo "  - $issue"
                done
                echo
                echo "Please investigate immediately."
                echo "System: $(hostname)"
                echo "Time: $(date)"
            } | mail "$ALERT_EMAIL"
        fi
        
        # Send webhook notification
        if [[ -n "${ALERT_WEBHOOK:-}" ]]; then
            curl -X POST "$ALERT_WEBHOOK" \
                 -H "Content-Type: application/json" \
                 -d "{\"status\":\"critical\",\"hostname\":\"$(hostname)\",\"issues\":[\"$(IFS='","'; echo "${CRITICALS[*]}")\"]}" \
                 >/dev/null 2>&1 || true
        fi
    fi
}

# Main execution
main() {
    echo -e "${GREEN}Homie OS System Health Check${NC}"
    echo "============================="
    echo
    
    # Log start of health check
    log "Starting system health check"
    
    # Run all checks
    check_rauc_service
    echo
    check_boot_attempts
    echo
    check_filesystem_space
    echo
    check_critical_services
    echo
    check_system_load
    echo
    check_memory_usage
    echo
    check_storage_health
    echo
    check_network
    echo
    check_temperature
    echo
    check_partitions
    echo
    
    # Generate report
    generate_report
    
    # Send alerts if necessary
    send_alerts
    
    # Log completion
    case $OVERALL_STATUS in
        $EXIT_OK)
            log "Health check completed: HEALTHY"
            ;;
        $EXIT_WARNING)
            log "Health check completed: WARNING - ${#WARNINGS[@]} warning(s)"
            ;;
        $EXIT_CRITICAL)
            log "Health check completed: CRITICAL - ${#CRITICALS[@]} critical issue(s)"
            ;;
    esac
    
    exit $OVERALL_STATUS
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo
        echo "Perform comprehensive system health check for Homie OS."
        echo
        echo "Exit codes:"
        echo "  0 - Healthy"
        echo "  1 - Warning conditions detected"
        echo "  2 - Critical issues detected"
        echo "  3 - Unknown error"
        echo
        echo "Environment variables:"
        echo "  ALERT_EMAIL - Email address for critical alerts"
        echo "  ALERT_WEBHOOK - Webhook URL for notifications"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
