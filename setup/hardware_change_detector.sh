#!/bin/bash

# hardware_change_detector.sh - Hardware Change Detection and Auto-Optimization
# Part of Milestone 6: Dynamic Hardware Optimization
# 
# This script implements a service to monitor for hardware changes and
# automatically trigger optimization when changes are detected.

# Only apply strict error handling when running as main script, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

# Get project root directory for relative imports
PROJECT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

# Source required utilities
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Configuration files and paths
HARDWARE_SPEC_FILE="/opt/n8n/hardware_specs.json"
DETECTOR_LOG_FILE="/opt/n8n/logs/hardware_detector.log"
DETECTOR_PID_FILE="/opt/n8n/hardware_detector.pid"
DETECTOR_SERVICE_FILE="/etc/systemd/system/n8n-hardware-detector.service"

# Detection and optimization settings
CHECK_INTERVAL_SECONDS=3600  # Check every hour
OPTIMIZATION_DELAY_SECONDS=300  # Wait 5 minutes before optimization

# Change thresholds
CPU_CHANGE_THRESHOLD=1  # Minimum CPU core change
MEMORY_CHANGE_THRESHOLD_GB=1  # Minimum memory change in GB
DISK_CHANGE_THRESHOLD_GB=5  # Minimum disk change in GB

# Email notification settings - load from environment with fallback
EMAIL_SUBJECT_PREFIX="${EMAIL_SUBJECT_PREFIX:-[n8n Server]}"
EMAIL_COOLDOWN_HOURS="${EMAIL_COOLDOWN_HOURS:-24}"  # Send emails at most once per day

# =============================================================================
# EMAIL CONFIGURATION FUNCTIONS
# =============================================================================

load_email_configuration() {
    echo "DEBUG: Loading email configuration..." >&2
    
    # Check for required email configuration variables
    local missing_vars=()
    [[ -z "${EMAIL_SENDER:-}" ]] && missing_vars+=("EMAIL_SENDER")
    [[ -z "${EMAIL_RECIPIENT:-}" ]] && missing_vars+=("EMAIL_RECIPIENT")
    [[ -z "${SMTP_SERVER:-}" ]] && missing_vars+=("SMTP_SERVER")
    [[ -z "${SMTP_PORT:-}" ]] && missing_vars+=("SMTP_PORT")
    [[ -z "${SMTP_USERNAME:-}" ]] && missing_vars+=("SMTP_USERNAME")
    [[ -z "${SMTP_PASSWORD:-}" ]] && missing_vars+=("SMTP_PASSWORD")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "WARNING: Missing email configuration variables: ${missing_vars[*]}" >&2
        echo "WARNING: Email notifications will be disabled" >&2
        return 1
    fi
    
    echo "DEBUG: Email configuration loaded successfully" >&2
    return 0
}

get_email_subject() {
    local notification_type="$1"
    
    # Get domain prefix dynamically
    local full_domain="${NGINX_SERVER_NAME:-$(hostname -d 2>/dev/null || echo 'server')}"
    local domain_name="${full_domain%%.*}"  # Extract just the domain name without TLD
    local subject_prefix="[${domain_name}]"
    
    case "$notification_type" in
        "hardware_change")
            echo "${subject_prefix} Hardware Change Detected"
            ;;
        "optimization_completed")
            echo "${subject_prefix} Hardware Optimization Completed"
            ;;
        "optimization_failed")
            echo "${subject_prefix} Hardware Optimization Failed"
            ;;
        "test")
            echo "${subject_prefix} Test Email"
            ;;
        *)
            echo "${subject_prefix} Hardware Optimization Update"
            ;;
    esac
}

get_email_body() {
    local notification_type="$1"
    local message="$2"
    
    case "$notification_type" in
        "hardware_change")
            cat << EOF
Hardware change detected on n8n server.

Previous Hardware Specifications:
$message

The system will automatically optimize configuration based on the new hardware specifications.

This is an automated notification from your n8n server monitoring system.
EOF
            ;;
        "optimization_completed")
            cat << EOF
Hardware optimization has been completed successfully.

$message

Your n8n server configuration has been updated to match the current hardware specifications.

This is an automated notification from your n8n server monitoring system.
EOF
            ;;
        "test")
            cat << EOF
This is a test email from your n8n server monitoring system.

$message

If you receive this email, the email notification system is working correctly.

Server: $(hostname)
Date: $(date)
EOF
            ;;
        *)
            cat << EOF
n8n Server Update:

$message

This is an automated notification from your n8n server monitoring system.
EOF
            ;;
    esac
}

format_email_message() {
    local subject="$1"
    local body="$2"
    
    cat << EOF
To: ${EMAIL_RECIPIENT}
From: ${EMAIL_SENDER}
Subject: $subject

$body
EOF
}

is_email_cooldown_active() {
    local notification_type="$1"
    local cooldown_dir="${2:-/opt/n8n/cooldown}"
    local cooldown_file="$cooldown_dir/${notification_type}_cooldown"
    local cooldown_hours="${EMAIL_COOLDOWN_HOURS:-24}"
    
    if [[ ! -f "$cooldown_file" ]]; then
        return 1  # No cooldown file, not in cooldown
    fi
    
    local last_notification_time
    last_notification_time=$(cat "$cooldown_file" 2>/dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    local cooldown_seconds=$((cooldown_hours * 3600))
    
    if (( current_time - last_notification_time < cooldown_seconds )); then
        return 0  # Still in cooldown
    else
        return 1  # Cooldown expired
    fi
}

set_email_cooldown() {
    local notification_type="$1"
    local cooldown_dir="${2:-/opt/n8n/cooldown}"
    local cooldown_file="$cooldown_dir/${notification_type}_cooldown"
    
    mkdir -p "$cooldown_dir"
    echo "$(date +%s)" > "$cooldown_file"
    
    echo "DEBUG: Email cooldown set for $notification_type until $(date -d "@$(($(date +%s) + EMAIL_COOLDOWN_HOURS * 3600))")" >&2
}

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

validate_email_configuration() {
    local missing_vars=()
    
    [[ -z "${EMAIL_SENDER:-}" ]] && missing_vars+=("EMAIL_SENDER")
    [[ -z "${EMAIL_RECIPIENT:-}" ]] && missing_vars+=("EMAIL_RECIPIENT")
    [[ -z "${SMTP_SERVER:-}" ]] && missing_vars+=("SMTP_SERVER")
    [[ -z "${SMTP_PORT:-}" ]] && missing_vars+=("SMTP_PORT")
    [[ -z "${SMTP_USERNAME:-}" ]] && missing_vars+=("SMTP_USERNAME")
    [[ -z "${SMTP_PASSWORD:-}" ]] && missing_vars+=("SMTP_PASSWORD")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "Missing email configuration: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}

generate_hardware_change_email_subject() {
    local old_specs="$1"
    local new_specs="$2"
    
    # Get domain prefix dynamically
    local full_domain="${NGINX_SERVER_NAME:-$(hostname -d 2>/dev/null || echo 'server')}"
    local domain_name="${full_domain%%.*}"  # Extract just the domain name without TLD
    
    echo "[${domain_name}] Hardware Change Detected"
}

generate_hardware_change_email_body() {
    local old_specs="$1"
    local new_specs="$2"
    
    local old_cpu old_memory old_disk
    local new_cpu new_memory new_disk
    
    # Extract values from JSON specs
    old_cpu=$(echo "$old_specs" | grep -o '"cpu_cores": *[0-9]*' | grep -o '[0-9]*$')
    old_memory=$(echo "$old_specs" | grep -o '"memory_gb": *[0-9]*' | grep -o '[0-9]*$')
    old_disk=$(echo "$old_specs" | grep -o '"disk_gb": *[0-9]*' | grep -o '[0-9]*$')
    
    new_cpu=$(echo "$new_specs" | grep -o '"cpu_cores": *[0-9]*' | grep -o '[0-9]*$')
    new_memory=$(echo "$new_specs" | grep -o '"memory_gb": *[0-9]*' | grep -o '[0-9]*$')
    new_disk=$(echo "$new_specs" | grep -o '"disk_gb": *[0-9]*' | grep -o '[0-9]*$')
    
    cat << EOF
Hardware change detected on n8n server:

Previous Hardware:
- CPU cores: ${old_cpu}
- Memory: ${old_memory}GB
- Disk: ${old_disk}GB

New Hardware:
- CPU cores: ${new_cpu}
- Memory: ${new_memory}GB
- Disk: ${new_disk}GB

Changes:
- CPU cores: ${old_cpu} → ${new_cpu}
- Memory: ${old_memory}GB → ${new_memory}GB
- Disk: ${old_disk}GB → ${new_disk}GB

Automatic optimization will be triggered shortly.

Server: $(hostname)
Timestamp: $(date)
EOF
}

generate_optimization_email_subject() {
    local status="$1"
    
    # Get domain prefix dynamically
    local full_domain="${NGINX_SERVER_NAME:-$(hostname -d 2>/dev/null || echo 'server')}"
    local domain_name="${full_domain%%.*}"  # Extract just the domain name without TLD
    
    case "$status" in
        "completed")
            echo "[${domain_name}] Hardware Optimization Completed"
            ;;
        "failed")
            echo "[${domain_name}] Hardware Optimization Failed"
            ;;
        *)
            echo "[${domain_name}] Hardware Optimization Update"
            ;;
    esac
}

generate_optimization_email_body() {
    local message="$1"
    
    cat << EOF
n8n Server Hardware Optimization Update:

$message

Server: $(hostname)
Timestamp: $(date)

For detailed information, check the optimization logs at:
/opt/n8n/logs/

Dashboard: https://$(hostname)/netdata/
EOF
}

# =============================================================================
# Email Cooldown Management Functions
# =============================================================================

# Unified cooldown function supporting both new and legacy modes
check_email_cooldown() {
    # If called with parameters, use new system
    if [[ $# -gt 0 ]]; then
        local notification_type="${1:-default}"
        local cooldown_file="/tmp/n8n_email_cooldown/${notification_type}"
        local cooldown_hours="${EMAIL_COOLDOWN_HOURS:-24}"
        local cooldown_seconds=$((cooldown_hours * 3600))
        
        # Check if cooldown file exists
        if [ ! -f "$cooldown_file" ]; then
            if declare -f log_debug >/dev/null 2>&1; then
                log_debug "No cooldown file found for $notification_type"
            else
                echo "DEBUG: No cooldown file found for $notification_type" >&2
            fi
            return 0  # No cooldown active - can send email
        fi
        
        # Get the timestamp from cooldown file
        local last_sent=$(cat "$cooldown_file" 2>/dev/null)
        if [ -z "$last_sent" ] || ! [[ "$last_sent" =~ ^[0-9]+$ ]]; then
            if declare -f log_warn >/dev/null 2>&1; then
                log_warn "Invalid cooldown file for $notification_type, removing"
            else
                echo "WARNING: Invalid cooldown file for $notification_type, removing" >&2
            fi
            rm -f "$cooldown_file"
            return 0  # No valid cooldown - can send email
        fi
        
        # Calculate time elapsed
        local current_time=$(date +%s)
        local time_elapsed=$((current_time - last_sent))
        
        echo "DEBUG: Email cooldown check: $time_elapsed seconds elapsed, cooldown is $cooldown_seconds seconds" >&2
        
        # Check if cooldown period has expired
        if [ "$time_elapsed" -ge "$cooldown_seconds" ]; then
            if declare -f log_debug >/dev/null 2>&1; then
                log_debug "Cooldown period expired for $notification_type"
            else
                echo "DEBUG: Cooldown period expired for $notification_type" >&2
            fi
            rm -f "$cooldown_file"  # Remove expired cooldown file
            return 0  # Cooldown expired - can send email
        else
            local remaining=$((cooldown_seconds - time_elapsed))
            local remaining_hours=$((remaining / 3600))
            if declare -f log_debug >/dev/null 2>&1; then
                log_debug "Cooldown active for $notification_type: $remaining_hours hours remaining"
            else
                echo "DEBUG: Cooldown active for $notification_type: $remaining_hours hours remaining" >&2
            fi
            return 1  # Cooldown still active - cannot send email
        fi
    else
        # Legacy mode: no parameters, use old system for backward compatibility
        local cooldown_file="/opt/n8n/data/last_email_notification"
        local cooldown_hours="${EMAIL_COOLDOWN_HOURS:-24}"
        local cooldown_seconds=$((cooldown_hours * 3600))
        
        # Ensure directory exists
        mkdir -p "/opt/n8n/data"
        
        # Check if cooldown file exists
        if [ ! -f "$cooldown_file" ]; then
            # Create cooldown file with current timestamp
            echo "$(date +%s)" > "$cooldown_file"
            return 0  # First call - no cooldown active
        fi
        
        # Get the timestamp from cooldown file
        local last_sent=$(cat "$cooldown_file" 2>/dev/null)
        if [ -z "$last_sent" ] || ! [[ "$last_sent" =~ ^[0-9]+$ ]]; then
            # Invalid file, recreate it
            echo "$(date +%s)" > "$cooldown_file"
            return 0  # Recreated file - no cooldown active
        fi
        
        # Calculate time elapsed
        local current_time=$(date +%s)
        local time_elapsed=$((current_time - last_sent))
        
        # Check if cooldown period has expired
        if [ "$time_elapsed" -ge "$cooldown_seconds" ]; then
            # Update timestamp for new cooldown period
            echo "$current_time" > "$cooldown_file"
            return 0  # Cooldown expired - can send email
        else
            # Still in cooldown period
            return 1  # Cooldown still active - cannot send email
        fi
    fi
}

set_email_cooldown() {
    local notification_type="${1:-default}"
    local cooldown_file="/tmp/n8n_email_cooldown/${notification_type}"
    local current_time=$(date +%s)
    
    # Ensure cooldown directory exists
    mkdir -p "/tmp/n8n_email_cooldown"
    echo "$current_time" > "$cooldown_file"
    echo "DEBUG: Email cooldown set for $notification_type until $(date -d "@$((current_time + EMAIL_COOLDOWN_HOURS * 3600))")" >&2
    return 0
}

record_email_sent() {
    local notification_type="${1:-default}"
    set_email_cooldown "$notification_type"
}



send_email_notification() {
    local notification_type="$1"
    local message="$2"
    local subject body temp_file
    
    # Validate email configuration
    if ! validate_email_configuration >/dev/null 2>&1; then
        echo "Email configuration missing"
        return 1
    fi
    
    # Check email cooldown
    if ! check_email_cooldown "$notification_type"; then
        echo "DEBUG: Email notification skipped due to cooldown" >&2
        return 0
    fi
    
    # Generate subject and body based on notification type
    case "$notification_type" in
        "test")
            local full_domain="${NGINX_SERVER_NAME:-$(hostname -d 2>/dev/null || echo 'server')}"
            local domain_name="${full_domain%%.*}"  # Extract just the domain name without TLD
            subject="[${domain_name}] Test Email"
            body="$message"
            ;;
        "hardware_change")
            subject=$(generate_hardware_change_email_subject "$message" "")
            body=$(generate_hardware_change_email_body "$message" "")
            ;;
        "optimization_completed")
            subject=$(generate_optimization_email_subject "completed")
            body=$(generate_optimization_email_body "$message")
            ;;
        *)
            echo "Invalid notification type: $notification_type"
            return 1
            ;;
    esac
    
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
        if msmtp "$EMAIL_RECIPIENT" < "$temp_file" >/dev/null 2>&1; then
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
        echo "Email notification sent successfully"
        set_email_cooldown "$notification_type"
        return 0
    else
        echo "Failed to send email notification"
        return 1
    fi
}

send_hardware_change_notification() {
    local notification_type="$1"
    
    # Check email cooldown before sending
    if ! check_email_cooldown "$notification_type"; then
        echo "DEBUG: Email notification skipped due to cooldown" >&2
        return 0
    fi
    
    case "$notification_type" in
        "detected")
            local message="Hardware changes detected and optimization will begin shortly."
            if send_email_notification "hardware_change" "$PREVIOUS_HARDWARE_SPECS" >/dev/null 2>&1; then
                log_info "Hardware change notification sent successfully"
            else
                log_warn "Failed to send hardware change notification"
            fi
            ;;
        "optimized")
            local message="Hardware optimization completed successfully. System has been reconfigured for optimal performance."
            if send_email_notification "optimization_completed" "$message" >/dev/null 2>&1; then
                log_info "Optimization completion notification sent successfully"
            else
                log_warn "Failed to send optimization completion notification"
            fi
            ;;
        *)
            log_warn "Unknown notification type: $notification_type"
            return 1
            ;;
    esac
    
    return 0
}

test_email_functionality() {
    log_info "Testing email functionality..."
    
    # Load environment configuration
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        source "$PROJECT_ROOT/conf/user.env"
        log_info "Loaded email configuration from user.env"
    elif [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        source "$PROJECT_ROOT/conf/default.env"
        log_info "Loaded email configuration from default.env"
    else
        log_error "No environment configuration found"
        return 1
    fi
    
    # Validate email configuration
    if validate_email_configuration; then
        log_info "✓ Email configuration is valid"
    else
        log_error "✗ Email configuration is invalid or incomplete"
        return 1
    fi
    
    # Send test email
    local test_message="This is a test email from the n8n hardware change detector.

Email Test Scope: HARDWARE_CHANGE_DETECTION
Test Type: Hardware monitoring and change notification system
Component: Hardware change detector and email notification

Test details:
- Server: $(hostname)
- Timestamp: $(date)
- User: $(whoami)
- Script: $0
- Purpose: Verify hardware change detection email notifications

If you receive this email, the email notification system is working correctly."
    
    log_info "Sending test email to $EMAIL_RECIPIENT..."
    
    if send_email_notification "test" "$test_message"; then
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
    
    # Wait for system to stabilize (skip in test mode)
    if [[ "${TEST_MODE:-false}" != "true" ]]; then
        log_info "Waiting ${OPTIMIZATION_DELAY_SECONDS} seconds for system to stabilize..."
        sleep "$OPTIMIZATION_DELAY_SECONDS"
    else
        log_info "Test mode enabled - skipping stabilization delay"
    fi
    
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
# Hardware Specs Backup and Restore Functions
# =============================================================================

backup_hardware_specs() {
    local specs_file="$1"
    local backup_dir="$2"
    
    if [ ! -f "$specs_file" ]; then
        log_warn "Hardware specs file not found: $specs_file"
        return 1
    fi
    
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir" || {
            log_error "Failed to create backup directory: $backup_dir"
            return 1
        }
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/hardware_specs_${timestamp}.json"
    
    if cp "$specs_file" "$backup_file"; then
        log_info "Hardware specs backed up to: $backup_file"
        return 0
    else
        log_error "Failed to backup hardware specs"
        return 1
    fi
}

restore_hardware_specs() {
    local specs_file="$1"
    local backup_dir="$2"
    
    if [ ! -d "$backup_dir" ]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi
    
    # Find the most recent backup file
    local latest_backup=$(ls -t "$backup_dir"/hardware_specs_*.json 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ]; then
        log_error "No backup files found in: $backup_dir"
        return 1
    fi
    
    if cp "$latest_backup" "$specs_file"; then
        log_info "Hardware specs restored from: $latest_backup"
        return 0
    else
        log_error "Failed to restore hardware specs"
        return 1
    fi
}

# =============================================================================
# Systemd Service Management Functions
# =============================================================================

create_hardware_detector_service() {
    log_info "Creating hardware change detector systemd service..."
    
    local service_file="/etc/systemd/system/n8n-hardware-detector.service"
    local script_path="$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Create systemd service file
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=n8n Hardware Change Detector
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$script_path --daemon
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=n8n-hardware-detector

# Environment variables
Environment=PROJECT_ROOT=$PROJECT_ROOT
Environment=HARDWARE_SPEC_FILE=/opt/n8n/hardware_specs.json
Environment=CHECK_INTERVAL_MINUTES=${HARDWARE_CHECK_INTERVAL_MINUTES:-60}
Environment=EMAIL_COOLDOWN_HOURS=${EMAIL_COOLDOWN_HOURS:-24}

[Install]
WantedBy=multi-user.target
EOF
    
    # Set proper permissions
    sudo chmod 644 "$service_file"
    
    # Reload systemd daemon
    sudo systemctl daemon-reload
    
    log_info "Hardware change detector service created: $service_file"
    return 0
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
# Performance Testing Functions with Resource Limits  
# =============================================================================

test_change_detection_performance() {
    log_info "Testing change detection performance with resource limits..."
    
    # Set resource limits to prevent system overload
    ulimit -v 524288   # Limit virtual memory to 512MB
    ulimit -t 20       # Limit CPU time to 20 seconds
    
    local start_time end_time duration
    local test_iterations=20
    local max_duration=8  # Maximum 8 seconds
    
    start_time=$(date +%s.%N)
    
    # Create test hardware specs files
    local test_specs_1="/tmp/test_hardware_specs_1.json"
    local test_specs_2="/tmp/test_hardware_specs_2.json"
    
    echo '{"cpu_cores": 2, "memory_gb": 4, "disk_gb": 100}' > "$test_specs_1"
    echo '{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 200}' > "$test_specs_2"
    
    # Run change detection tests with timeout
    for i in $(seq 1 $test_iterations); do
        local current_time=$(date +%s.%N)
        local elapsed=$(echo "$current_time - $start_time" | bc -l 2>/dev/null || echo "0")
        
        if (( $(echo "$elapsed > $max_duration" | bc -l 2>/dev/null || echo "0") )); then
            log_warn "Change detection test stopped early (${elapsed}s elapsed)"
            break
        fi
        
        # Lightweight change detection test
        timeout 1 compare_hardware_specs "$test_specs_1" "$test_specs_2" >/dev/null 2>&1 || true
        
        # Add small delay to prevent CPU spike
        sleep 0.05
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    log_info "Change detection performance test completed in ${duration}s"
    
    # Cleanup test files
    rm -f "$test_specs_1" "$test_specs_2"
    
    # Reset resource limits
    ulimit -v unlimited 2>/dev/null || true
    ulimit -t unlimited 2>/dev/null || true
    
    return 0
}

test_hardware_detection_performance() {
    log_info "Testing hardware detection performance with resource limits..."
    
    # Set resource limits
    ulimit -v 262144   # Limit virtual memory to 256MB
    ulimit -t 10       # Limit CPU time to 10 seconds
    
    local start_time end_time duration
    local test_iterations=5
    local max_duration=3  # Maximum 3 seconds
    
    start_time=$(date +%s.%N)
    
    # Run hardware detection with timeout
    for i in $(seq 1 $test_iterations); do
        local current_time=$(date +%s.%N)
        local elapsed=$(echo "$current_time - $start_time" | bc -l 2>/dev/null || echo "0")
        
        if (( $(echo "$elapsed > $max_duration" | bc -l 2>/dev/null || echo "0") )); then
            log_warn "Hardware detection test stopped early (${elapsed}s elapsed)"
            break
        fi
        
        # Lightweight hardware detection
        timeout 1 get_current_hardware_specs >/dev/null 2>&1 || true
        sleep 0.2
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    log_info "Hardware detection performance test completed in ${duration}s"
    
    # Reset resource limits
    ulimit -v unlimited 2>/dev/null || true
    ulimit -t unlimited 2>/dev/null || true
    
    return 0
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
            create_hardware_detector_service
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