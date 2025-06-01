#!/bin/bash

# hardware_change_detector.sh - Hardware Change Detection and Auto-Optimization
# Part of Milestone 6: Dynamic Hardware Optimization
# 
# This script implements a service to monitor for hardware changes and
# automatically trigger optimization when changes are detected.

set -euo pipefail

# Get project root directory for relative imports
PROJECT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

# Source required utilities
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Hardware monitoring configuration
readonly HARDWARE_SPEC_FILE="/opt/n8n/data/hardware_specs.json"
readonly DETECTOR_LOG_FILE="/opt/n8n/logs/hardware_detector.log"
readonly DETECTOR_PID_FILE="/var/run/n8n_hardware_detector.pid"
readonly DETECTOR_SERVICE_FILE="/etc/systemd/system/n8n-hardware-detector.service"

# Monitoring intervals
readonly CHECK_INTERVAL_SECONDS=300  # Check every 5 minutes
readonly OPTIMIZATION_DELAY_SECONDS=60  # Wait 1 minute before optimization

# Change detection thresholds
readonly CPU_CHANGE_THRESHOLD=1      # Minimum CPU core change to trigger
readonly MEMORY_CHANGE_THRESHOLD_GB=1  # Minimum memory change in GB
readonly DISK_CHANGE_THRESHOLD_GB=5    # Minimum disk change in GB

# Email notification settings
readonly EMAIL_SUBJECT_PREFIX="[n8n Server]"
readonly EMAIL_COOLDOWN_HOURS=1      # Minimum hours between email notifications

# =============================================================================
# HARDWARE DETECTION FUNCTIONS
# =============================================================================

get_current_hardware_specs() {
    local cpu_cores memory_gb disk_gb
    
    # Get current hardware specifications
    cpu_cores=$(nproc 2>/dev/null || echo "1")
    memory_gb=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}' 2>/dev/null || echo "1")
    disk_gb=$(df /opt/n8n 2>/dev/null | tail -1 | awk '{print int($2/1024/1024)}' || echo "20")
    
    # Create JSON object with current specs
    cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cpu_cores": $cpu_cores,
    "memory_gb": $memory_gb,
    "disk_gb": $disk_gb,
    "hostname": "$(hostname)",
    "uptime": "$(uptime -p 2>/dev/null || echo 'unknown')"
}
EOF
}

load_previous_hardware_specs() {
    if [[ -f "$HARDWARE_SPEC_FILE" ]]; then
        cat "$HARDWARE_SPEC_FILE"
    else
        echo "{}"
    fi
}

save_hardware_specs() {
    local specs="$1"
    local backup_file="${HARDWARE_SPEC_FILE}.backup"
    
    # Create backup of previous specs
    [[ -f "$HARDWARE_SPEC_FILE" ]] && cp "$HARDWARE_SPEC_FILE" "$backup_file"
    
    # Save new specs
    echo "$specs" > "$HARDWARE_SPEC_FILE"
    
    log_info "Hardware specifications saved to $HARDWARE_SPEC_FILE"
}

# =============================================================================
# CHANGE DETECTION FUNCTIONS
# =============================================================================

extract_spec_value() {
    local json="$1"
    local key="$2"
    
    echo "$json" | grep -o "\"$key\": *[0-9]*" | grep -o "[0-9]*$" || echo "0"
}

detect_hardware_changes() {
    local current_specs previous_specs
    local current_cpu current_memory current_disk
    local previous_cpu previous_memory previous_disk
    local changes_detected=false
    local change_summary=""
    
    # Get current and previous specifications
    current_specs=$(get_current_hardware_specs)
    previous_specs=$(load_previous_hardware_specs)
    
    # Extract values for comparison
    current_cpu=$(extract_spec_value "$current_specs" "cpu_cores")
    current_memory=$(extract_spec_value "$current_specs" "memory_gb")
    current_disk=$(extract_spec_value "$current_specs" "disk_gb")
    
    previous_cpu=$(extract_spec_value "$previous_specs" "cpu_cores")
    previous_memory=$(extract_spec_value "$previous_specs" "memory_gb")
    previous_disk=$(extract_spec_value "$previous_specs" "disk_gb")
    
    # Check for CPU changes
    local cpu_diff=$((current_cpu - previous_cpu))
    if [[ "${cpu_diff#-}" -ge "$CPU_CHANGE_THRESHOLD" ]]; then
        changes_detected=true
        change_summary="${change_summary}CPU: ${previous_cpu} → ${current_cpu} cores (${cpu_diff:+$cpu_diff})\n"
        log_info "CPU change detected: ${previous_cpu} → ${current_cpu} cores"
    fi
    
    # Check for memory changes
    local memory_diff=$((current_memory - previous_memory))
    if [[ "${memory_diff#-}" -ge "$MEMORY_CHANGE_THRESHOLD_GB" ]]; then
        changes_detected=true
        change_summary="${change_summary}Memory: ${previous_memory}GB → ${current_memory}GB (${memory_diff:+$memory_diff}GB)\n"
        log_info "Memory change detected: ${previous_memory}GB → ${current_memory}GB"
    fi
    
    # Check for disk changes
    local disk_diff=$((current_disk - previous_disk))
    if [[ "${disk_diff#-}" -ge "$DISK_CHANGE_THRESHOLD_GB" ]]; then
        changes_detected=true
        change_summary="${change_summary}Disk: ${previous_disk}GB → ${current_disk}GB (${disk_diff:+$disk_diff}GB)\n"
        log_info "Disk change detected: ${previous_disk}GB → ${current_disk}GB"
    fi
    
    # Export results for use by other functions
    export HARDWARE_CHANGED="$changes_detected"
    export CURRENT_HARDWARE_SPECS="$current_specs"
    export PREVIOUS_HARDWARE_SPECS="$previous_specs"
    export CHANGE_SUMMARY="$change_summary"
    
    if [[ "$changes_detected" == "true" ]]; then
        log_info "Hardware changes detected - optimization will be triggered"
        return 0
    else
        log_debug "No significant hardware changes detected"
        return 1
    fi
}

# =============================================================================
# EMAIL NOTIFICATION FUNCTIONS
# =============================================================================

check_email_cooldown() {
    local cooldown_file="/opt/n8n/data/last_email_notification"
    local current_time last_email_time time_diff
    
    current_time=$(date +%s)
    
    if [[ -f "$cooldown_file" ]]; then
        last_email_time=$(cat "$cooldown_file" 2>/dev/null || echo "0")
        time_diff=$((current_time - last_email_time))
        
        # Check if cooldown period has passed (convert hours to seconds)
        if [[ "$time_diff" -lt $((EMAIL_COOLDOWN_HOURS * 3600)) ]]; then
            log_debug "Email notification in cooldown period"
            return 1
        fi
    fi
    
    # Update last email time
    echo "$current_time" > "$cooldown_file"
    return 0
}

send_hardware_change_notification() {
    local change_type="$1"  # "detected" or "optimized"
    local subject body
    
    # Check email cooldown
    if ! check_email_cooldown; then
        log_debug "Skipping email notification due to cooldown"
        return 0
    fi
    
    # Load email configuration
    local email_config
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        source "$PROJECT_ROOT/conf/user.env"
    elif [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        source "$PROJECT_ROOT/conf/default.env"
    fi
    
    # Check if email is configured
    if [[ -z "${EMAIL_SENDER:-}" || -z "${EMAIL_RECIPIENT:-}" ]]; then
        log_warn "Email not configured - skipping notification"
        return 0
    fi
    
    # Prepare email content based on change type
    case "$change_type" in
        "detected")
            subject="${EMAIL_SUBJECT_PREFIX} Hardware Change Detected"
            body="Hardware changes have been detected on your n8n server:

$(echo -e "$CHANGE_SUMMARY")

Server: $(hostname)
Detection Time: $(date)

Automatic optimization will begin shortly to adapt to the new hardware configuration.

Previous Hardware:
$(echo "$PREVIOUS_HARDWARE_SPECS" | grep -E '(cpu_cores|memory_gb|disk_gb)' | sed 's/[",]//g' | sed 's/^[[:space:]]*/- /')

Current Hardware:
$(echo "$CURRENT_HARDWARE_SPECS" | grep -E '(cpu_cores|memory_gb|disk_gb)' | sed 's/[",]//g' | sed 's/^[[:space:]]*/- /')

This is an automated notification from your n8n server monitoring system."
            ;;
        "optimized")
            subject="${EMAIL_SUBJECT_PREFIX} Hardware Optimization Completed"
            body="Hardware optimization has been completed on your n8n server.

$(echo -e "$CHANGE_SUMMARY")

Server: $(hostname)
Optimization Time: $(date)

All services have been reconfigured and restarted to take advantage of the new hardware specifications.

Current Configuration:
$(echo "$CURRENT_HARDWARE_SPECS" | grep -E '(cpu_cores|memory_gb|disk_gb)' | sed 's/[",]//g' | sed 's/^[[:space:]]*/- /')

You can view detailed optimization results in the Netdata dashboard at:
https://$(hostname)/netdata/

This is an automated notification from your n8n server monitoring system."
            ;;
        *)
            log_error "Invalid email notification type: $change_type"
            return 1
            ;;
    esac
    
    # Send email notification
    if send_email_notification "$subject" "$body"; then
        log_info "Email notification sent successfully"
    else
        log_warn "Failed to send email notification"
    fi
}

send_email_notification() {
    local subject="$1"
    local body="$2"
    local temp_file
    
    temp_file=$(mktemp)
    
    # Create email message
    cat > "$temp_file" << EOF
To: ${EMAIL_RECIPIENT}
From: ${EMAIL_SENDER}
Subject: ${subject}

${body}
EOF
    
    # Try multiple email sending methods
    local email_sent=false
    
    # Method 1: Try msmtp if available
    if command -v msmtp >/dev/null 2>&1; then
        if msmtp -t < "$temp_file" >/dev/null 2>&1; then
            email_sent=true
        fi
    fi
    
    # Method 2: Try sendmail if available and msmtp failed
    if [[ "$email_sent" == "false" ]] && command -v sendmail >/dev/null 2>&1; then
        if sendmail -t < "$temp_file" >/dev/null 2>&1; then
            email_sent=true
        fi
    fi
    
    # Method 3: Try mail command if available and others failed
    if [[ "$email_sent" == "false" ]] && command -v mail >/dev/null 2>&1; then
        if echo "$body" | mail -s "$subject" "$EMAIL_RECIPIENT" >/dev/null 2>&1; then
            email_sent=true
        fi
    fi
    
    # Cleanup
    rm -f "$temp_file"
    
    if [[ "$email_sent" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

test_email_functionality() {
    local test_subject="${EMAIL_SUBJECT_PREFIX} Hardware Detector Test Email"
    local test_body="This is a test email from the n8n server hardware change detector.

Server: $(hostname)
Test Time: $(date)

If you receive this email, the notification system is working correctly.

Current Hardware:
$(get_current_hardware_specs | grep -E '(cpu_cores|memory_gb|disk_gb)' | sed 's/[",]//g' | sed 's/^[[:space:]]*/- /')

This is an automated test from your n8n server monitoring system."
    
    log_info "Sending test email notification..."
    
    if send_email_notification "$test_subject" "$test_body"; then
        log_info "✓ Test email sent successfully"
        return 0
    else
        log_error "✗ Failed to send test email"
        return 1
    fi
}

# =============================================================================
# OPTIMIZATION TRIGGER FUNCTIONS
# =============================================================================

trigger_optimization() {
    log_info "Triggering hardware optimization due to detected changes..."
    
    # Send notification about detected changes
    send_hardware_change_notification "detected"
    
    # Wait for system to stabilize
    log_info "Waiting ${OPTIMIZATION_DELAY_SECONDS} seconds for system to stabilize..."
    sleep "$OPTIMIZATION_DELAY_SECONDS"
    
    # Run optimization script
    local optimization_script="$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    if [[ -f "$optimization_script" ]]; then
        log_info "Running dynamic optimization..."
        
        if bash "$optimization_script" --optimize; then
            log_info "✓ Hardware optimization completed successfully"
            
            # Send notification about completed optimization
            send_hardware_change_notification "optimized"
            
            # Update stored hardware specifications
            save_hardware_specs "$CURRENT_HARDWARE_SPECS"
            
            return 0
        else
            log_error "✗ Hardware optimization failed"
            return 1
        fi
    else
        log_error "Optimization script not found: $optimization_script"
        return 1
    fi
}

# =============================================================================
# SERVICE MANAGEMENT FUNCTIONS
# =============================================================================

create_systemd_service() {
    log_info "Creating systemd service for hardware change detector..."
    
    # Create systemd service file
    cat > "$DETECTOR_SERVICE_FILE" << EOF
[Unit]
Description=n8n Hardware Change Detector
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$PROJECT_ROOT/setup/hardware_change_detector.sh --daemon
ExecStop=/bin/kill -TERM \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/n8n /var/run /var/log

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable n8n-hardware-detector.service
    
    log_info "Systemd service created and enabled"
}

start_detector_service() {
    if systemctl is-active n8n-hardware-detector.service >/dev/null 2>&1; then
        log_info "Hardware detector service is already running"
        return 0
    fi
    
    log_info "Starting hardware detector service..."
    
    if systemctl start n8n-hardware-detector.service; then
        log_info "✓ Hardware detector service started successfully"
        return 0
    else
        log_error "✗ Failed to start hardware detector service"
        return 1
    fi
}

stop_detector_service() {
    if ! systemctl is-active n8n-hardware-detector.service >/dev/null 2>&1; then
        log_info "Hardware detector service is not running"
        return 0
    fi
    
    log_info "Stopping hardware detector service..."
    
    if systemctl stop n8n-hardware-detector.service; then
        log_info "✓ Hardware detector service stopped successfully"
        return 0
    else
        log_error "✗ Failed to stop hardware detector service"
        return 1
    fi
}

get_detector_status() {
    local status
    
    if systemctl is-active n8n-hardware-detector.service >/dev/null 2>&1; then
        status="running"
    elif systemctl is-enabled n8n-hardware-detector.service >/dev/null 2>&1; then
        status="stopped"
    else
        status="disabled"
    fi
    
    echo "$status"
}

# =============================================================================
# DAEMON FUNCTIONS
# =============================================================================

run_daemon() {
    log_info "Starting hardware change detector daemon..."
    
    # Create necessary directories
    mkdir -p "$(dirname "$HARDWARE_SPEC_FILE")" "$(dirname "$DETECTOR_LOG_FILE")"
    
    # Initialize hardware specs if not exists
    if [[ ! -f "$HARDWARE_SPEC_FILE" ]]; then
        log_info "Initializing hardware specifications..."
        local initial_specs
        initial_specs=$(get_current_hardware_specs)
        save_hardware_specs "$initial_specs"
    fi
    
    # Main monitoring loop
    while true; do
        log_debug "Checking for hardware changes..."
        
        if detect_hardware_changes; then
            log_info "Hardware changes detected - triggering optimization"
            
            if trigger_optimization; then
                log_info "Optimization completed successfully"
            else
                log_error "Optimization failed - will retry on next check"
            fi
        fi
        
        # Wait for next check
        sleep "$CHECK_INTERVAL_SECONDS"
    done
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
Hardware Change Detector for n8n Server

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --daemon            Run as daemon (continuous monitoring)
    --check-once        Check for changes once and exit
    --install-service   Install and enable systemd service
    --start-service     Start the detector service
    --stop-service      Stop the detector service
    --status            Show detector service status
    --test-email        Send test email notification
    --force-optimize    Force optimization regardless of changes
    --show-specs        Display current hardware specifications
    --help              Show this help message

EXAMPLES:
    $0 --daemon         # Run continuous monitoring
    $0 --check-once     # Single check for changes
    $0 --test-email     # Test email notifications
    $0 --status         # Check service status

The detector monitors for hardware changes every 5 minutes and automatically
triggers optimization when significant changes are detected.

Hardware change thresholds:
- CPU cores: ±${CPU_CHANGE_THRESHOLD} cores
- Memory: ±${MEMORY_CHANGE_THRESHOLD_GB}GB
- Disk space: ±${DISK_CHANGE_THRESHOLD_GB}GB

Email notifications are sent when changes are detected and after optimization
is completed (with ${EMAIL_COOLDOWN_HOURS}h cooldown between notifications).
EOF
}

main() {
    local action="check-once"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --daemon)
                action="daemon"
                shift
                ;;
            --check-once)
                action="check-once"
                shift
                ;;
            --install-service)
                action="install-service"
                shift
                ;;
            --start-service)
                action="start-service"
                shift
                ;;
            --stop-service)
                action="stop-service"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --test-email)
                action="test-email"
                shift
                ;;
            --force-optimize)
                action="force-optimize"
                shift
                ;;
            --show-specs)
                action="show-specs"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Execute requested action
    case $action in
        "daemon")
            run_daemon
            ;;
        "check-once")
            if detect_hardware_changes; then
                log_info "Hardware changes detected"
                echo -e "$CHANGE_SUMMARY"
                exit 0
            else
                log_info "No hardware changes detected"
                exit 1
            fi
            ;;
        "install-service")
            create_systemd_service
            log_info "Service installed. Use --start-service to start monitoring."
            ;;
        "start-service")
            start_detector_service
            ;;
        "stop-service")
            stop_detector_service
            ;;
        "status")
            local status
            status=$(get_detector_status)
            log_info "Hardware detector service status: $status"
            
            if [[ "$status" == "running" ]]; then
                systemctl status n8n-hardware-detector.service --no-pager
            fi
            ;;
        "test-email")
            test_email_functionality
            ;;
        "force-optimize")
            # Force optimization by setting change variables
            export HARDWARE_CHANGED="true"
            export CURRENT_HARDWARE_SPECS="$(get_current_hardware_specs)"
            export PREVIOUS_HARDWARE_SPECS="{}"
            export CHANGE_SUMMARY="Forced optimization requested"
            
            trigger_optimization
            ;;
        "show-specs")
            local current_specs
            current_specs=$(get_current_hardware_specs)
            echo "Current Hardware Specifications:"
            echo "$current_specs" | jq . 2>/dev/null || echo "$current_specs"
            ;;
        *)
            log_error "Invalid action: $action"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 