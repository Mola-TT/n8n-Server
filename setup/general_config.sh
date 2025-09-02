#!/bin/bash
# general_config.sh - General system configuration functions
# Part of Milestone 1

# Script directory - using unique variable name to avoid conflicts
GENERAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        
        # Upgrade packages with retry logic for apt lock issues
        local upgrade_log="/tmp/apt_upgrade_$$.log"
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
                log_debug "Attempting to fix common package manager issues..."
                
                # Kill any hanging package manager processes
                pkill -9 apt-get 2>/dev/null || true
                pkill -9 dpkg 2>/dev/null || true
                
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