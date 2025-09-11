#!/bin/bash
# general_config.sh - General system configuration functions
# Part of Milestone 1

# Script directory - using unique variable name to avoid conflicts
GENERAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Perform attended upgrade with progress reporting
perform_attended_upgrade() {
    local upgrade_log="$1"
    local progress_log="$2"
    
    # Create named pipes for real-time progress monitoring
    local upgrade_pipe="/tmp/apt_upgrade_pipe_$$"
    mkfifo "$upgrade_pipe" 2>/dev/null || {
        log_warn "Failed to create named pipe, falling back to standard upgrade"
        return 1
    }
    
    # Start upgrade process in background
    {
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Progress-Fancy="false" \
            -o APT::Status-Fd=3 3>"$upgrade_pipe" > "$upgrade_log" 2>&1
        echo $? > "${upgrade_log}.exitcode"
    } &
    local upgrade_pid=$!
    
    # Monitor progress from the pipe
    {
        local last_status=""
        local last_download_status=""
        local package_count=0
        local total_packages=""
        local last_progress_time=0
        local progress_interval=30  # Log progress every 30 seconds
        
        while IFS= read -r line < "$upgrade_pipe" 2>/dev/null; do
            local current_time=$(date +%s)
            
            if [[ "$line" =~ ^dlstatus: ]]; then
                # Download status: dlstatus:1:0.0000:Downloading package
                local status_part="${line#dlstatus:}"
                local current_pkg="${status_part##*:}"
                
                # Only log download progress every 30 seconds or when package changes
                if [[ "$current_pkg" != "$last_download_status" ]]; then
                    # New package - log immediately
                    log_info "Downloading: $current_pkg"
                    last_download_status="$current_pkg"
                    last_progress_time="$current_time"
                elif [[ $((current_time - last_progress_time)) -ge $progress_interval ]]; then
                    # Same package - only log every 30 seconds
                    log_info "Downloading: $current_pkg"
                    last_progress_time="$current_time"
                fi
            elif [[ "$line" =~ ^pmstatus: ]]; then
                # Package manager status: pmstatus:package:percentage:description
                local status_part="${line#pmstatus:}"
                local pkg_name="${status_part%%:*}"
                local rest="${status_part#*:}"
                local percentage="${rest%%:*}"
                local description="${rest#*:}"
                
                if [[ "$description" != "$last_status" ]]; then
                    if [[ -n "$percentage" && "$percentage" != "0.0000" ]]; then
                        log_info "Processing $pkg_name: $description (${percentage%.*}%)"
                    else
                        log_info "Processing $pkg_name: $description"
                    fi
                    last_status="$description"
                fi
            elif [[ "$line" =~ ^processing: ]]; then
                # Processing status: processing:package:action
                local status_part="${line#processing:}"
                local pkg_name="${status_part%%:*}"
                local action="${status_part#*:}"
                log_info "Installing: $pkg_name ($action)"
            else
                # Suppress any other frequent status messages that don't match expected patterns
                # Only log unexpected messages with throttling to avoid spam
                if [[ $((current_time - last_progress_time)) -ge $progress_interval ]]; then
                    # Check if this looks like a progress/download message
                    if [[ "$line" =~ (Retrieving|Downloading|file.*of.*remaining) ]]; then
                        log_info "Download progress: $(echo "$line" | cut -c1-80)..."
                        # Don't update last_progress_time here to avoid interference with dlstatus timing
                    fi
                fi
            fi
        done
    } &
    local monitor_pid=$!
    
    # Wait for upgrade to complete
    wait $upgrade_pid
    local exit_code
    if [[ -f "${upgrade_log}.exitcode" ]]; then
        exit_code=$(cat "${upgrade_log}.exitcode")
        rm -f "${upgrade_log}.exitcode"
    else
        exit_code=1
    fi
    
    # Clean up monitoring
    kill $monitor_pid 2>/dev/null || true
    rm -f "$upgrade_pipe" 2>/dev/null || true
    
    return $exit_code
}

# Update system packages silently
update_system() {
    if [ "$SYSTEM_UPDATE" = true ]; then
        log_info "Updating system packages silently. This may take a while..."
        
        # Clear logs
        clear_logs
        
        # Update package lists silently with retry logic
        if ! apt_update_with_retry 5 45; then
            log_error "Failed to update package lists after multiple retries"
            return 1
        fi
        
        # Handle unattended-upgrades - stop it for attended upgrade or wait
        if pgrep -f "unattended-upgr" >/dev/null; then
            if [[ "${FORCE_ATTENDED_UPGRADE:-false}" == "true" ]]; then
                log_info "Detected unattended-upgrades running, stopping for attended upgrade..."
                systemctl stop unattended-upgrades 2>/dev/null || true
                pkill -f "unattended-upgr" 2>/dev/null || true
                sleep 5  # Brief wait for cleanup
                log_info "Unattended-upgrades stopped, proceeding with attended upgrade"
            else
                log_info "Detected unattended-upgrades running, waiting for completion..."
                local wait_count=0
                while pgrep -f "unattended-upgr" >/dev/null && [ $wait_count -lt 1200 ]; do
                    sleep 60
                    wait_count=$((wait_count + 60))
                    log_info "Still waiting for unattended-upgrades... ($((wait_count / 60)) minutes elapsed)"
                done
                
                if pgrep -f "unattended-upgr" >/dev/null; then
                    log_warn "Unattended-upgrades still running after 20 minutes, proceeding with caution..."
                else
                    log_info "Unattended-upgrades completed, proceeding with manual upgrade"
                fi
            fi
        fi

        # Upgrade packages with retry logic for apt lock issues
        local upgrade_log="/tmp/apt_upgrade_$$.log"
        local upgrade_progress_log="/tmp/apt_upgrade_progress_$$.log"
        
        # Choose upgrade method based on FORCE_ATTENDED_UPGRADE setting
        if [[ "${FORCE_ATTENDED_UPGRADE:-false}" == "true" ]]; then
            log_info "Starting attended system package upgrade with progress reporting..."
            
            # Start upgrade in background with progress monitoring
            if ! perform_attended_upgrade "$upgrade_log" "$upgrade_progress_log"; then
                local retry_count=0
                local max_retries=5
                
                # Log the initial error
                log_warn "Attended upgrade failed. Error details:"
                head -5 "$upgrade_log" | while read -r line; do
                    log_warn "  $line"
                done
                
                # Retry with standard method
                while [ $retry_count -lt $max_retries ]; do
                    log_warn "Retrying with standard upgrade method (retry $((retry_count+1))/$max_retries)..."
                    
                    # Clear log file for retry
                    > "$upgrade_log"
                    if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq > "$upgrade_log" 2>&1; then
                        log_info "System packages upgraded successfully on attended retry $retry_count"
                        rm -f "$upgrade_log" "$upgrade_progress_log"
                        break
                    fi
                    
                    retry_count=$((retry_count + 1))
                    if [ $retry_count -ge $max_retries ]; then
                        log_error "Failed to upgrade packages after $max_retries attended retries"
                        rm -f "$upgrade_log" "$upgrade_progress_log"
                        return 1
                    fi
                    sleep 30
                done
            else
                log_info "Attended system package upgrade completed successfully"
                rm -f "$upgrade_log" "$upgrade_progress_log"
            fi
        else
            # Standard unattended upgrade (original logic)
            if ! DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq > "$upgrade_log" 2>&1; then
                local retry_count=0
                local max_retries=5
                
                # Log the initial error
                log_warn "Initial upgrade failed. Error details:"
                head -5 "$upgrade_log" | while read -r line; do
                    log_warn "  $line"
                done
                
                while [ $retry_count -lt $max_retries ]; do
                log_warn "Failed to upgrade packages, retrying in 45 seconds (retry $((retry_count+1))/$max_retries)..."
                
                # Try to fix common issues before retrying
                log_debug "Attempting to fix package manager lock issues..."
                
                # Handle unattended-upgrades during retry
                if pgrep -f "unattended-upgr" >/dev/null; then
                    if [[ "${FORCE_ATTENDED_UPGRADE:-false}" == "true" ]]; then
                        log_info "Killing unattended-upgrades for attended upgrade retry..."
                        systemctl stop unattended-upgrades 2>/dev/null || true
                        pkill -9 -f "unattended-upgr" 2>/dev/null || true
                        sleep 3
                    else
                        log_info "Waiting for unattended-upgrades to complete..."
                        # Wait up to 20 minutes for unattended-upgrades to finish
                        local wait_count=0
                        while pgrep -f "unattended-upgr" >/dev/null && [ $wait_count -lt 1200 ]; do
                            sleep 60
                            wait_count=$((wait_count + 60))
                            log_info "Still waiting for unattended-upgrades... ($((wait_count / 60)) minutes elapsed)"
                        done
                        
                        if pgrep -f "unattended-upgr" >/dev/null; then
                            log_warn "Unattended-upgrades still running after 20 minutes, force killing..."
                            pkill -9 -f "unattended-upgr" 2>/dev/null || true
                        else
                            log_info "Unattended-upgrades completed successfully"
                        fi
                    fi
                fi
                
                # Kill any other hanging package manager processes
                pkill -9 apt-get 2>/dev/null || true
                pkill -9 dpkg 2>/dev/null || true
                pkill -9 apt 2>/dev/null || true
                
                # Wait a moment for processes to clean up
                sleep 2
                
                # Remove lock files
                rm -f /var/lib/dpkg/lock* 2>/dev/null || true
                rm -f /var/lib/apt/lists/lock* 2>/dev/null || true
                rm -f /var/cache/apt/archives/lock* 2>/dev/null || true
                
                # Try to configure any interrupted packages
                dpkg --configure -a 2>/dev/null || true
                
                # Update package lists again
                apt-get update -qq 2>/dev/null || true
                
                sleep 45
                retry_count=$((retry_count + 1))
                
                # Clear log file for retry
                > "$upgrade_log"
                if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq > "$upgrade_log" 2>&1; then
                    log_info "System packages upgraded successfully on retry $retry_count"
                    rm -f "$upgrade_log"
                    break
                fi
                
                # Log retry error details
                log_warn "Retry $retry_count failed. Error details:"
                head -5 "$upgrade_log" | while read -r line; do
                    log_warn "  $line"
                done
                
                if [ $retry_count -ge $max_retries ]; then
                    log_error "Failed to upgrade packages after $max_retries retries"
                    log_error "Final error details:"
                    head -10 "$upgrade_log" | while read -r line; do
                        log_error "  $line"
                    done
                    rm -f "$upgrade_log"
                    return 1
                fi
            done
            else
                rm -f "$upgrade_log"
            fi
        fi
        
        log_info "System packages updated successfully"
    else
        log_info "System update skipped as per configuration"
    fi
}

# Set timezone
set_timezone() {
    # Use SERVER_TIMEZONE if defined, otherwise fallback to UTC
    local timezone="${SERVER_TIMEZONE:-UTC}"
        
    execute_silently "timedatectl set-timezone \"$timezone\"" \
        "Timezone set to $timezone" \
        "Failed to set timezone to $timezone" || return 1
    
    # Get current timezone
    current_tz=$(timedatectl | grep "Time zone" | awk '{print $3}')
    export TIMEZONE="$timezone"  # Set TIMEZONE for backward compatibility
}

# Export functions
export -f update_system
export -f set_timezone
export -f apt_install_with_retry
export -f apt_update_with_retry 