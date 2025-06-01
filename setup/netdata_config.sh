#!/bin/bash

# =============================================================================
# Netdata Configuration Script for n8n Server - Milestone 4
# =============================================================================
# This script sets up Netdata for system resource monitoring with secure
# access through Nginx proxy, health alerts, and email notifications
# =============================================================================

# Source required libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/utilities.sh"

# =============================================================================
# Repository Management Functions
# =============================================================================

fix_ubuntu_repositories() {
    log_info "Checking Ubuntu repository accessibility..."
    
    # Test current repositories with both metadata and package download
    if apt-get update >/dev/null 2>&1; then
        log_info "Repository metadata accessible, testing package downloads..."
        
        # Test actual package download capability with postfix specifically
        if apt-get install -y --dry-run --download-only postfix >/dev/null 2>&1; then
            log_info "Ubuntu repositories are fully accessible"
            return 0
        else
            log_warn "Repository metadata accessible but package downloads failing"
        fi
    else
        log_warn "Repository metadata not accessible"
    fi
    
    log_warn "Ubuntu repositories have issues, attempting to fix..."
    
    # Get Ubuntu codename
    local codename=$(lsb_release -cs)
    
    # Detect repository format (Ubuntu 24.04+ uses new format)
    local ubuntu_sources_file="/etc/apt/sources.list.d/ubuntu.sources"
    local traditional_sources="/etc/apt/sources.list"
    local using_new_format=false
    
    if [ -f "$ubuntu_sources_file" ]; then
        log_info "Detected Ubuntu 24.04+ new repository format"
        using_new_format=true
        # Backup the new format file
        cp "$ubuntu_sources_file" "${ubuntu_sources_file}.backup.$(date +%Y%m%d_%H%M%S)"
    else
        log_info "Detected traditional repository format"
        # Backup current sources.list
        cp "$traditional_sources" "${traditional_sources}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Try different Ubuntu mirrors in order of preference
    local mirrors=(
        "archive.ubuntu.com"
        "us.archive.ubuntu.com"
        "mirror.ubuntu.com"
        "old-releases.ubuntu.com"
    )
    
    for mirror in "${mirrors[@]}"; do
        log_info "Testing Ubuntu mirror: $mirror"
        
        if [ "$using_new_format" = true ]; then
            # Create new ubuntu.sources file with this mirror
            cat > "$ubuntu_sources_file" << EOF
# Ubuntu repositories - Auto-configured by n8n server setup
Types: deb
URIs: http://$mirror/ubuntu/
Suites: $codename $codename-updates $codename-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu
Suites: $codename-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
        else
            # Create traditional sources.list with this mirror
            cat > "$traditional_sources" << EOF
# Ubuntu repositories - Auto-configured by n8n server setup
deb http://$mirror/ubuntu/ $codename main restricted universe multiverse
deb http://$mirror/ubuntu/ $codename-updates main restricted universe multiverse
deb http://$mirror/ubuntu/ $codename-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $codename-security main restricted universe multiverse
EOF
        fi
        
        # Test this mirror with both metadata and package downloads
        log_info "Testing repository metadata update for mirror: $mirror"
        if apt-get update >/dev/null 2>&1; then
            log_info "Testing package download capability for mirror: $mirror"
            # Test with multiple critical packages to ensure downloads work
            if apt-get install -y --dry-run --download-only postfix curl wget >/dev/null 2>&1; then
                log_info "✓ Successfully configured Ubuntu mirror: $mirror"
                
                # Additional verification: try to actually download a small package list
                log_info "Performing final verification with package cache refresh..."
                if apt-get update >/dev/null 2>&1; then
                    log_info "✓ Mirror $mirror fully operational"
                    return 0
                else
                    log_warn "✗ Mirror $mirror failed final verification"
                fi
            else
                log_warn "✗ Mirror $mirror metadata OK but package downloads fail"
            fi
        else
            log_warn "✗ Mirror $mirror metadata failed"
        fi
        
        # Small delay between mirror attempts
        sleep 2
    done
    
    # If all mirrors failed, restore backup and continue
    log_warn "All Ubuntu mirrors failed, restoring original configuration"
    if [ "$using_new_format" = true ]; then
        local backup_file=$(ls -t "${ubuntu_sources_file}.backup."* 2>/dev/null | head -1)
        if [ -n "$backup_file" ]; then
            mv "$backup_file" "$ubuntu_sources_file"
        fi
    else
        local backup_file=$(ls -t "${traditional_sources}.backup."* 2>/dev/null | head -1)
        if [ -n "$backup_file" ]; then
            mv "$backup_file" "$traditional_sources"
        fi
    fi
    
    # Try one more update with original configuration
    log_info "Attempting final repository update with original configuration..."
    apt-get update >/dev/null 2>&1 || true
    
    return 1
}

# =============================================================================
# Netdata Installation Functions
# =============================================================================

install_netdata() {
    log_info "Installing Netdata system monitoring..."
    
    # Install dependencies with enhanced error handling
    if ! install_netdata_dependencies; then
        log_error "Failed to install Netdata dependencies"
        return 1
    fi
    
    # Download and run official Netdata installer
    log_info "Downloading Netdata installer..."
    if ! execute_silently "wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh" "Downloading Netdata installer"; then
        log_error "Failed to download Netdata installer"
        return 1
    fi
    
    log_info "Installing Netdata (this may take a few minutes)..."
    # Use non-interactive installation with auto-update disabled
    if ! execute_silently "sudo bash /tmp/netdata-kickstart.sh --stable-channel --disable-telemetry --no-updates --auto-update-type crontab --dont-wait" "Installing Netdata"; then
        log_error "Netdata installation failed"
        return 1
    fi
    
    log_info "Netdata installed successfully"
    
    # Clean up installer
    rm -f /tmp/netdata-kickstart.sh
    
    # CRITICAL: Configure systemd override BEFORE any other configuration
    configure_netdata_systemd_override
    
    return 0
}

install_netdata_dependencies() {
    log_info "Installing Netdata dependencies..."
    
    # Check if we have sudo privileges
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo privileges for package installation"
        return 1
    fi
    
    # Fix Ubuntu repositories first if needed
    fix_ubuntu_repositories
    
    # Configure postfix for non-interactive installation
    log_info "Configuring postfix for non-interactive installation..."
    echo "postfix postfix/main_mailer_type select Local only" | sudo debconf-set-selections
    echo "postfix postfix/mailname string $(hostname -f)" | sudo debconf-set-selections
    
    # Try to install postfix with enhanced error handling
    log_info "Installing postfix and other dependencies..."
    
    # First attempt: Install postfix with other dependencies
    if execute_silently "sudo apt-get update && sudo apt-get install -y postfix curl wget apache2-utils" "Installing dependencies with postfix"; then
        log_info "✓ Successfully installed all dependencies including postfix"
        return 0
    fi
    
    log_warn "Failed to install dependencies with postfix, trying alternative approaches..."
    
    # Second attempt: Install dependencies without postfix first
    log_info "Installing basic dependencies without postfix..."
    if execute_silently "sudo apt-get install -y curl wget apache2-utils gnupg lsb-release" "Installing basic dependencies"; then
        log_info "✓ Basic dependencies installed successfully"
        
        # Now try postfix separately with more specific configuration
        log_info "Attempting postfix installation separately..."
        
        # Set additional postfix configuration to avoid prompts
        echo "postfix postfix/protocols select all" | sudo debconf-set-selections
        echo "postfix postfix/chattr boolean false" | sudo debconf-set-selections
        echo "postfix postfix/mailbox_limit string 0" | sudo debconf-set-selections
        echo "postfix postfix/recipient_delim string +" | sudo debconf-set-selections
        echo "postfix postfix/mynetworks string 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128" | sudo debconf-set-selections
        echo "postfix postfix/destinations string $(hostname -f), localhost.localdomain, localhost" | sudo debconf-set-selections
        
        if execute_silently "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postfix" "Installing postfix with enhanced configuration"; then
            log_info "✓ Successfully installed postfix separately"
            return 0
        fi
        
        # Third attempt: Try alternative mail solutions
        log_warn "Postfix installation failed, trying alternative mail solutions..."
        
        # Try exim4 as alternative
        log_info "Attempting exim4 installation as postfix alternative..."
        if execute_silently "sudo apt-get install -y exim4" "Installing exim4 as mail alternative"; then
            log_info "✓ Successfully installed exim4 as mail solution"
            
            # Configure exim4 for local delivery
            echo "exim4-config exim4/dc_eximconfig_configtype select local delivery only; not on a network" | sudo debconf-set-selections
            echo "exim4-config exim4/dc_local_interfaces string 127.0.0.1" | sudo debconf-set-selections
            echo "exim4-config exim4/dc_other_hostnames string" | sudo debconf-set-selections
            echo "exim4-config exim4/dc_relay_domains string" | sudo debconf-set-selections
            echo "exim4-config exim4/dc_relay_nets string" | sudo debconf-set-selections
            
            execute_silently "sudo dpkg-reconfigure -f noninteractive exim4-config" "Configuring exim4"
            return 0
        fi
        
        # Fourth attempt: Try sendmail
        log_info "Attempting sendmail installation as mail alternative..."
        if execute_silently "sudo apt-get install -y sendmail" "Installing sendmail as mail alternative"; then
            log_info "✓ Successfully installed sendmail as mail solution"
            return 0
        fi
        
        # Fifth attempt: Try mailutils (lightweight option)
        log_info "Attempting mailutils installation as lightweight mail solution..."
        if execute_silently "sudo apt-get install -y mailutils" "Installing mailutils as lightweight mail solution"; then
            log_info "✓ Successfully installed mailutils as mail solution"
            return 0
        fi
        
        # If all mail solutions fail, continue without email (Netdata can work without it)
        log_warn "All mail solutions failed, continuing without email notifications"
        log_warn "Netdata will be installed but email alerts will not be available"
        return 0
        
    else
        log_error "Failed to install basic dependencies"
        return 1
    fi
}

# =============================================================================
# Netdata Configuration Functions
# =============================================================================

configure_netdata_security() {
    log_info "Configuring Netdata security settings..."
    
    # CRITICAL FIX: Detect installation type and use correct paths
    local netdata_conf=""
    local netdata_type=""
    local web_dir=""
    local cache_dir=""
    local lib_dir=""
    local log_dir=""
    local run_dir="/run/netdata"
    
    # Detect installation type by checking where the binary and config are located
    if [ -f "/usr/sbin/netdata" ] && [ -d "/etc/netdata" ]; then
        # System package installation (apt/yum)
        netdata_type="system"
        netdata_conf="/etc/netdata/netdata.conf"
        web_dir="/usr/share/netdata/web"
        cache_dir="/var/cache/netdata"
        lib_dir="/var/lib/netdata"
        log_dir="/var/log/netdata"
        log_info "Detected system package installation of Netdata"
        
        # Remove systemd override that's designed for official installer
        if [ -d "/etc/systemd/system/netdata.service.d" ]; then
            log_info "Removing systemd override (not needed for system package installation)"
            sudo rm -rf /etc/systemd/system/netdata.service.d
            sudo systemctl daemon-reload
        fi
        
    elif [ -f "/opt/netdata/usr/sbin/netdata" ] || [ -d "/opt/netdata" ]; then
        # Official installer installation
        netdata_type="official"
        netdata_conf="/opt/netdata/etc/netdata/netdata.conf"
        web_dir="/opt/netdata/usr/share/netdata/web"
        cache_dir="/opt/netdata/var/cache/netdata"
        lib_dir="/opt/netdata/var/lib/netdata"
        log_dir="/opt/netdata/var/log/netdata"
        log_info "Detected official installer installation of Netdata"
        
        # Ensure config directory exists for official installer
        sudo mkdir -p "$(dirname "$netdata_conf")"
        sudo chown -R netdata:netdata "$(dirname "$(dirname "$netdata_conf")")" 2>/dev/null || true
        
    else
        log_error "Could not detect Netdata installation type"
        return 1
    fi
    
    log_info "Using Netdata type: $netdata_type"
    log_info "Config file: $netdata_conf"
    log_info "Web directory: $web_dir"
    
    # Create backup of original configuration if it exists
    if [ -f "$netdata_conf" ]; then
        local backup_conf="${netdata_conf}.backup"
        if [ ! -f "$backup_conf" ]; then
            sudo cp "$netdata_conf" "$backup_conf"
            log_info "Created backup: $backup_conf"
        fi
    fi
    
    # Ensure required directories exist
    log_info "Creating required directories..."
    for dir in "$cache_dir" "$lib_dir" "$log_dir" "$run_dir"; do
        if [ ! -d "$dir" ]; then
            sudo mkdir -p "$dir"
            sudo chown netdata:netdata "$dir" 2>/dev/null || true
            log_info "Created directory: $dir"
        fi
    done
    
    # For system installations, also create cloud config if needed
    if [ "$netdata_type" = "system" ] && [ ! -f "$lib_dir/cloud.d/cloud.conf" ]; then
        sudo mkdir -p "$lib_dir/cloud.d"
        sudo tee "$lib_dir/cloud.d/cloud.conf" > /dev/null << EOF
[global]
    enabled = no
    cloud base url = https://app.netdata.cloud
EOF
        sudo chown -R netdata:netdata "$lib_dir/cloud.d"
        log_info "Created cloud config: $lib_dir/cloud.d/cloud.conf"
    fi
    
    # Configure Netdata to bind only to localhost for security
    log_info "Writing Netdata configuration for localhost-only binding..."
    sudo tee "$netdata_conf" > /dev/null << EOF
# Netdata Configuration - Milestone 4
# Generated by n8n server initialization

[global]
    # Default update frequency (seconds)
    update every = 1
    
    # Memory mode
    memory mode = ram
    
    # Disable registry for privacy
    registry enabled = ${NETDATA_REGISTRY_ENABLED:-no}
    
    # Disable anonymous statistics
    anonymous statistics = ${NETDATA_ANONYMOUS_STATISTICS:-no}
    
    # Set directories
    cache directory = $cache_dir
    lib directory = $lib_dir
    log directory = $log_dir
    run directory = $run_dir
    web files directory = $web_dir

[web]
    # CRITICAL: Web server configuration for localhost-only binding
    mode = static-threaded
    listen backlog = 4096
    default port = ${NETDATA_PORT:-19999}
    # Bind only to localhost for security
    bind to = ${NETDATA_BIND_IP:-127.0.0.1}:${NETDATA_PORT:-19999}
    
    # Security settings
    enable gzip compression = yes
    web files group = netdata
    web files owner = netdata
    
    # CRITICAL FIX: Allow connections from IP addresses
    allow connections from = localhost 127.0.0.1 ::1
    allow dashboard from = localhost 127.0.0.1 ::1
    allow badges from = localhost 127.0.0.1 ::1
    allow streaming from = localhost 127.0.0.1 ::1
    allow netdata.conf from = localhost 127.0.0.1 ::1
    allow management from = localhost 127.0.0.1 ::1
    
    # CRITICAL FIX: Allow specific host headers (fixes HTTP 400 issue)
    allow connections by dns = localhost 127.0.0.1
    allow dashboard by dns = localhost 127.0.0.1
    allow badges by dns = localhost 127.0.0.1
    allow streaming by dns = localhost 127.0.0.1
    allow netdata.conf by dns = localhost 127.0.0.1
    allow management by dns = localhost 127.0.0.1

[plugins]
    # Enable essential plugins
    proc = yes
    diskspace = yes
    cgroups = yes
    tc = no
    idlejitter = yes
    
[health]
    # Health monitoring
    enabled = yes
    in memory max health log entries = 1000
    
EOF
    
    # Set proper ownership and permissions
    sudo chown netdata:netdata "$netdata_conf"
    sudo chmod 644 "$netdata_conf"
    
    log_info "Netdata configuration updated successfully"
    
    # CRITICAL: Force restart Netdata service to apply localhost-only binding
    log_info "Force-restarting Netdata service to apply localhost-only binding..."
    
    # Kill any existing netdata processes
    sudo pkill -f netdata || true
    sleep 2
    
    # Start fresh
    if sudo systemctl restart netdata; then
        log_info "Netdata service restarted successfully"
        
        # Wait longer for service to start and verify binding
        sleep 15
        
        # Check if Netdata is now properly bound to localhost
        if ss -tlnp | grep -q "127.0.0.1:${NETDATA_PORT:-19999}"; then
            log_info "✓ Netdata is now properly bound to localhost only"
        elif ss -tlnp | grep -q "0.0.0.0:${NETDATA_PORT:-19999}"; then
            log_error "✗ Netdata is still binding to all interfaces (0.0.0.0)"
            log_error "Checking configuration file location..."
            log_error "Config written to: $netdata_conf"
            if [ -f "$netdata_conf" ]; then
                log_error "Configuration file exists and contains:"
                grep -A5 -B5 "bind to" "$netdata_conf" 2>/dev/null || log_error "No binding configuration found"
            else
                log_error "Configuration file does not exist!"
            fi
            return 1
        else
            log_warn "Netdata binding status unclear - manual verification needed"
        fi
    else
        log_error "Failed to restart Netdata service"
        return 1
    fi
    
    return 0
}

configure_netdata_health_monitoring() {
    log_info "Configuring Netdata health monitoring and alerts..."
    
    # Detect correct health directory based on installation type
    local health_dir=""
    if [ -d "/etc/netdata" ]; then
        health_dir="/etc/netdata/health.d"
    elif [ -d "/opt/netdata/etc/netdata" ]; then
        health_dir="/opt/netdata/etc/netdata/health.d"
    else
        log_error "Could not find Netdata configuration directory"
        return 1
    fi
    
    log_info "Using health configuration directory: $health_dir"
    
    # Create health configuration directory
    sudo mkdir -p "$health_dir"
    
    # CPU Usage Alert - Fixed chart name to system.cpu
    sudo tee "$health_dir/cpu_usage.conf" > /dev/null << 'EOF'
# CPU Usage Alert Configuration - Milestone 4

 alarm: cpu_usage_high
    on: system.cpu
lookup: average -3m unaligned of user,system,nice,iowait
 units: %
 every: 10s
  warn: $this > 80
  crit: $this > 95
 delay: down 15m multiplier 1.5 max 1h
  info: CPU utilization is too high
    to: sysadmin
EOF

    # Memory Usage Alert - Fixed chart name to system.ram
    sudo tee "$health_dir/memory_usage.conf" > /dev/null << 'EOF'
# Memory Usage Alert Configuration - Milestone 4

 alarm: memory_usage_high
    on: system.ram
lookup: average -3m unaligned of used
 units: %
 every: 10s
  warn: $this > 80
  crit: $this > 95
 delay: down 15m multiplier 1.5 max 1h
  info: Memory utilization is too high
    to: sysadmin
EOF

    # RAM Usage Alert (alternative name for compatibility)
    sudo tee "$health_dir/ram_usage.conf" > /dev/null << 'EOF'
# RAM Usage Alert Configuration - Milestone 4

 alarm: ram_usage_high
    on: system.ram
lookup: average -3m unaligned of used
 units: %
 every: 10s
  warn: $this > 80
  crit: $this > 95
 delay: down 15m multiplier 1.5 max 1h
  info: RAM utilization is too high
    to: sysadmin
EOF

    # Disk Usage Alert - Fixed chart name to disk_space./
    sudo tee "$health_dir/disk_usage.conf" > /dev/null << 'EOF'
# Disk Usage Alert Configuration - Milestone 4

 alarm: disk_usage_high
    on: disk_space./
lookup: average -3m unaligned of used
 units: %
 every: 10s
  warn: $this > 80
  crit: $this > 95
 delay: down 15m multiplier 1.5 max 1h
  info: Disk space utilization is too high
    to: sysadmin
EOF

    # Load Average Alert - Chart name confirmed as system.load
    sudo tee "$health_dir/load_average.conf" > /dev/null << 'EOF'
# Load Average Alert Configuration - Milestone 4

 alarm: load_average_high
    on: system.load
lookup: average -3m unaligned of load1
 units: 
 every: 10s
  warn: $this > 2
  crit: $this > 4
 delay: down 15m multiplier 1.5 max 1h
  info: System load average is too high
    to: sysadmin
EOF

    # Set proper permissions for health configuration files
    sudo chmod 644 "$health_dir"/*.conf
    sudo chown netdata:netdata "$health_dir"/*.conf 2>/dev/null || true
    
    # Configure email notifications
    local notification_config=""
    if [ -d "/etc/netdata" ]; then
        notification_config="/etc/netdata/health_alarm_notify.conf"
    elif [ -d "/opt/netdata/etc/netdata" ]; then
        notification_config="/opt/netdata/etc/netdata/health_alarm_notify.conf"
    else
        log_error "Could not determine notification config path"
        return 1
    fi
    
    log_info "Configuring email notifications at: $notification_config"
    configure_netdata_email_notifications "$notification_config"
    
    log_info "Health monitoring alerts configured successfully"
    
    # CRITICAL: Restart Netdata to reload health configurations
    log_info "Restarting Netdata to reload health configurations..."
    if sudo systemctl restart netdata; then
        log_info "Netdata restarted successfully"
        
        # Wait for service to be ready
        sleep 10
        
        # Verify health alerts are now loaded
        local alert_count=$(curl -s --connect-timeout 10 "http://127.0.0.1:19999/api/v1/alarms?all" 2>/dev/null | grep -o '"[^"]*_high"' | wc -l 2>/dev/null | tr -d '\n' || echo "0")
        alert_count=${alert_count:-0}  # Ensure it's not empty
        if [[ "$alert_count" =~ ^[0-9]+$ ]] && [ "$alert_count" -gt 0 ]; then
            log_info "✓ Health alerts loaded successfully ($alert_count alerts found)"
        else
            log_info "ℹ Health alerts are initializing (found ${alert_count:-0} alerts) - this is normal after restart"
        fi
    else
        log_error "Failed to restart Netdata service"
        return 1
    fi
    
    return 0
}

configure_netdata_email_notifications() {
    local health_alarm_notify="$1"
    log_info "Configuring Netdata email notifications..."
    log_info "Using notification config file: $health_alarm_notify"
    
    # Ensure parent directory exists
    sudo mkdir -p "$(dirname "$health_alarm_notify")"
    
    # Create notification configuration
    sudo tee "$health_alarm_notify" > /dev/null << EOF
# Netdata Health Alarm Notification Configuration - Milestone 4

# Enable sending emails
SEND_EMAIL="YES"

# Default recipient for all alarms
DEFAULT_RECIPIENT_EMAIL="${NETDATA_ALERT_EMAIL_RECIPIENT:-${EMAIL_RECIPIENT:-root}}"

# Email settings
EMAIL_SENDER="${NETDATA_ALERT_EMAIL_SENDER:-${EMAIL_SENDER:-netdata@localhost}}"
SMTP_SERVER="${SMTP_SERVER:-localhost}"
SMTP_PORT="${SMTP_PORT:-25}"

# Use local sendmail for delivery
SENDMAIL="/usr/sbin/sendmail"

# Role configurations
role_recipients_email[sysadmin]="${NETDATA_ALERT_EMAIL_RECIPIENT:-${EMAIL_RECIPIENT:-root}}"

# Silent period for repeated notifications (in seconds)
DEFAULT_RECIPIENT_EMAIL_SILENT_PERIOD=3600

# Custom email subject
EMAIL_SUBJECT="[Netdata Alert] \${host} \${alarm} \${status}"

EOF
    
    # CRITICAL FIX: Set proper permissions so netdata user can read the file
    sudo chown netdata:netdata "$health_alarm_notify" 2>/dev/null || sudo chown root:netdata "$health_alarm_notify"
    sudo chmod 644 "$health_alarm_notify"
    
    # Ensure netdata user can access the file
    if [ -f "$health_alarm_notify" ]; then
        # Test if netdata user can read the file
        if sudo -u netdata test -r "$health_alarm_notify" 2>/dev/null; then
            log_info "✓ Netdata user can read notification config file"
        else
            # Fallback: make it world-readable
            sudo chmod 644 "$health_alarm_notify"
            log_info "✓ Fixed notification config file permissions"
        fi
    fi
    
    log_info "Email notifications configured successfully"
    return 0
}

# =============================================================================
# Nginx Integration Functions
# =============================================================================

configure_netdata_nginx_proxy() {
    log_info "Configuring Nginx proxy for Netdata dashboard..."
    
    local nginx_conf_dir="/etc/nginx/sites-available"
    local nginx_enabled_dir="/etc/nginx/sites-enabled"
    local netdata_conf="$nginx_conf_dir/netdata"
    local auth_file="/etc/nginx/.netdata_auth"
    
    # Create basic auth file for Netdata
    log_info "Creating basic authentication for Netdata..."
    if command -v htpasswd &> /dev/null; then
        echo "${NETDATA_NGINX_AUTH_PASSWORD}" | htpasswd -ci "$auth_file" "${NETDATA_NGINX_AUTH_USER}" >/dev/null 2>&1
    else
        # Install apache2-utils for htpasswd
        if execute_silently "apt-get install -y apache2-utils"; then
            echo "${NETDATA_NGINX_AUTH_PASSWORD}" | htpasswd -ci "$auth_file" "${NETDATA_NGINX_AUTH_USER}" >/dev/null 2>&1
        else
            log_error "Failed to install apache2-utils for password generation"
            return 1
        fi
    fi
    
    if [ -f "$auth_file" ]; then
        chmod 640 "$auth_file"
        sudo chown root:www-data "$auth_file"
        log_info "Basic authentication configured for user: ${NETDATA_NGINX_AUTH_USER}"
    else
        log_error "Failed to create authentication file"
        return 1
    fi
    
    # Check and fix SSL certificate permissions
    local ssl_cert_path="${NGINX_SSL_CERT_PATH:-/etc/nginx/ssl/certificate.crt}"
    local ssl_key_path="${NGINX_SSL_KEY_PATH:-/etc/nginx/ssl/private.key}"
    
    log_info "Verifying SSL certificate permissions..."
    if [ -f "$ssl_key_path" ]; then
        # Fix SSL key permissions - make it readable by nginx
        chmod 644 "$ssl_key_path"
        sudo chown root:www-data "$ssl_key_path"
        log_info "Fixed SSL private key permissions: $ssl_key_path"
    else
        log_error "SSL private key not found: $ssl_key_path"
        return 1
    fi
    
    if [ -f "$ssl_cert_path" ]; then
        chmod 644 "$ssl_cert_path"
        sudo chown root:www-data "$ssl_cert_path"
        log_info "SSL certificate permissions verified: $ssl_cert_path"
    else
        log_error "SSL certificate not found: $ssl_cert_path"
        return 1
    fi
    
    # Create Nginx configuration for Netdata
    local server_name="${NETDATA_NGINX_SUBDOMAIN}.${NGINX_SERVER_NAME:-localhost}"
    
    sudo tee "$netdata_conf" > /dev/null << EOF
# Netdata Nginx Configuration - Milestone 4
# Secure HTTPS proxy for Netdata dashboard

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name $server_name;
    
    # Security headers even for redirects
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    
    # Redirect all HTTP requests to HTTPS
    return 301 https://\$server_name\$request_uri;
    
    # Access and error logs
    access_log ${NETDATA_NGINX_ACCESS_LOG};
    error_log ${NETDATA_NGINX_ERROR_LOG};
}

# HTTPS server for Netdata
server {
    listen 443 ssl http2;
    server_name $server_name;
    
    # SSL Configuration
    ssl_certificate $ssl_cert_path;
    ssl_certificate_key $ssl_key_path;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:NETDATA_SSL:6m;
    ssl_session_timeout 10m;
    
    # Security Headers - CRITICAL: Add 'always' directive for auth responses
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' wss: https:;" always;
    
    # Basic Authentication
    auth_basic "Netdata Monitoring";
    auth_basic_user_file $auth_file;
    
    # Proxy settings for Netdata
    location / {
        proxy_pass http://${NETDATA_BIND_IP}:${NETDATA_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support for real-time updates
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        proxy_cache off;
        
        # Additional security headers for proxied content
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
    }
    
    # Access and error logs
    access_log ${NETDATA_NGINX_ACCESS_LOG};
    error_log ${NETDATA_NGINX_ERROR_LOG};
}
EOF
    
    # Enable the configuration
    if [ ! -L "$nginx_enabled_dir/netdata" ]; then
        sudo ln -sf "$netdata_conf" "$nginx_enabled_dir/netdata"
        log_info "Netdata Nginx configuration enabled"
    else
        log_info "Netdata Nginx configuration already enabled"
    fi
    
    # Test Nginx configuration
    if sudo nginx -t &>/dev/null; then
        log_info "Nginx configuration test successful"
        
        # Reload Nginx
        if sudo systemctl reload nginx; then
            log_info "Nginx reloaded successfully"
        else
            log_warn "Failed to reload Nginx - manual restart may be required"
        fi
    else
        log_error "Nginx configuration test failed"
        log_error "Running nginx -t for detailed error information..."
        sudo nginx -t
        return 1
    fi
    
    return 0
}

# =============================================================================
# Firewall Configuration Functions
# =============================================================================

configure_netdata_firewall() {
    log_info "Configuring firewall rules for Netdata..."
    
    # Check if UFW is available and enabled
    if ! command -v ufw &> /dev/null; then
        log_warn "UFW not found - firewall configuration skipped"
        return 0
    fi
    
    # Block direct access to Netdata port if configured
    if [ "${NETDATA_FIREWALL_BLOCK_DIRECT:-true}" = "true" ]; then
        log_info "Blocking direct access to Netdata port ${NETDATA_PORT:-19999}..."
        
        # Remove any existing rules for Netdata port
        execute_silently "ufw delete allow ${NETDATA_PORT:-19999}/tcp" 2>/dev/null || true
        
        # Add explicit deny rules for external access
        if execute_silently "ufw deny ${NETDATA_PORT:-19999}/tcp"; then
            log_info "Direct access to Netdata port blocked via firewall"
            
            # Additional blocking for specific interfaces if needed
            execute_silently "ufw deny in on eth0 to any port ${NETDATA_PORT:-19999}" 2>/dev/null || true
            execute_silently "ufw deny in on ens3 to any port ${NETDATA_PORT:-19999}" 2>/dev/null || true
        else
            log_warn "Failed to block Netdata port via firewall"
        fi
        
        # Ensure localhost connections are still allowed (though this should be default)
        execute_silently "ufw allow from 127.0.0.1 to any port ${NETDATA_PORT:-19999}" 2>/dev/null || true
    fi
    
    # Ensure HTTP and HTTPS are still allowed for Nginx proxy
    if execute_silently "ufw allow 80/tcp" && execute_silently "ufw allow 443/tcp"; then
        log_info "HTTP/HTTPS access confirmed for Nginx proxy"
    else
        log_warn "Failed to ensure HTTP/HTTPS access"
    fi
    
    # Force reload UFW rules
    execute_silently "ufw reload" 2>/dev/null || true
    
    # Display current firewall status
    local firewall_status=$(sudo ufw status 2>/dev/null | head -1)
    if [[ "$firewall_status" == *"active"* ]]; then
        # Count the rules for summary
        local ssh_rules=$(sudo ufw status numbered 2>/dev/null | grep -c "22/tcp" || echo "0")
        local http_rules=$(sudo ufw status numbered 2>/dev/null | grep -c "80/tcp" || echo "0") 
        local https_rules=$(sudo ufw status numbered 2>/dev/null | grep -c "443/tcp" || echo "0")
        local netdata_deny_rules=$(sudo ufw status numbered 2>/dev/null | grep -c "${NETDATA_PORT:-19999}/tcp.*DENY" || echo "0")
        
        log_info "UFW firewall is active"
        log_info "Firewall rules: SSH ($ssh_rules), HTTP ($http_rules), HTTPS ($https_rules), Netdata DENY ($netdata_deny_rules)"
        
        # Test firewall effectiveness
        log_info "Testing firewall effectiveness..."
        
        # Since Netdata is bound to localhost only (127.0.0.1), external access is already blocked
        # by the binding configuration. The firewall rules provide additional protection.
        # Check if Netdata is properly bound to localhost only
        if sudo ss -tlnp | grep -q "127.0.0.1:${NETDATA_PORT:-19999}"; then
            log_info "✓ Netdata is properly bound to localhost only - external access blocked by design"
            
            # Verify firewall rules are in place as additional protection
            if [ "$netdata_deny_rules" -gt 0 ]; then
                log_info "✓ Firewall rules provide additional protection against direct port access"
            else
                log_info "ℹ Firewall rules not found, but localhost binding provides primary protection"
            fi
        else
            # Only test external access if Netdata is bound to all interfaces
            local external_test=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" "http://0.0.0.0:${NETDATA_PORT:-19999}/api/v1/info" 2>/dev/null || echo "000")
            if [ "$external_test" = "000" ] || [ "$external_test" = "7" ]; then
                log_info "✓ Firewall successfully blocking external access to Netdata"
            else
                log_warn "⚠ Firewall may not be effectively blocking external access (got HTTP $external_test)"
            fi
        fi
    else
        log_warn "UFW firewall is not active"
    fi
    
    return 0
}

# =============================================================================
# Service Management Functions
# =============================================================================

start_netdata_service() {
    log_info "Starting and enabling Netdata service..."
    
    # Enable Netdata service for auto-start
    if execute_silently "systemctl enable netdata"; then
        log_info "Netdata service enabled for auto-start"
    else
        log_warn "Failed to enable Netdata service"
    fi
    
    # Start Netdata service
    if execute_silently "systemctl start netdata"; then
        log_info "Netdata service started successfully"
    else
        log_error "Failed to start Netdata service"
        return 1
    fi
    
    # Wait for service to fully start with timeout
    log_info "Waiting for Netdata service to become ready..."
    local wait_count=0
    local max_wait=30
    
    while [ $wait_count -lt $max_wait ]; do
        if sudo systemctl is-active netdata &>/dev/null; then
            log_info "Netdata service is running"
            break
        fi
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    # Final service status check
    if sudo systemctl is-active netdata &>/dev/null; then
        log_info "Netdata service is active and running"
        
        # Wait a bit more for API to be ready
        sleep 3
        
        # Test local connectivity with timeout
        if timeout 10 curl -s "http://${NETDATA_BIND_IP:-127.0.0.1}:${NETDATA_PORT:-19999}/api/v1/info" &>/dev/null; then
            log_info "Netdata API is responding on localhost"
        else
            log_warn "Netdata API test failed - service may still be initializing (this is normal)"
        fi
    else
        log_error "Netdata service failed to start properly"
        # Show service status for debugging
        sudo systemctl status netdata --no-pager -l 2>/dev/null | head -10 | while read line; do
            log_error "Service status: $line"
        done
        return 1
    fi
    
    return 0
}

# =============================================================================
# Main Setup Function
# =============================================================================

setup_netdata_monitoring() {
    log_info "Setting up Netdata monitoring infrastructure..."
    
    # Step 1: Install Netdata (includes systemd override)
    if ! install_netdata; then
        log_error "Failed to install Netdata"
        return 1
    fi
    
    # Step 2: Stop service and kill any existing processes
    log_info "Stopping any existing Netdata processes..."
    sudo systemctl stop netdata 2>/dev/null || true
    sudo pkill -f netdata || true
    sleep 3
    
    # Step 3: Configure Netdata security settings  
    if ! configure_netdata_security; then
        log_error "Failed to configure Netdata security"
        return 1
    fi
    
    # Step 4: Configure health monitoring
    if ! configure_netdata_health_monitoring; then
        log_error "Failed to configure Netdata health monitoring"
        return 1
    fi
    
    # Step 5: Start and enable Netdata service with new configuration
    log_info "Starting and enabling Netdata service..."
    
    # Reload systemd daemon to ensure override is picked up
    sudo systemctl daemon-reload
    
    # Enable the service
    if execute_silently "systemctl enable netdata"; then
        log_info "Netdata service enabled for auto-start"
    else
        log_error "Failed to enable Netdata service"
        return 1
    fi
    
    # Start the service with the new environment variables
    if execute_silently "systemctl start netdata"; then
        log_info "Netdata service started successfully"
    else
        log_error "Failed to start Netdata service"
        # Show recent logs for debugging
        sudo journalctl -u netdata --no-pager -n 10
        return 1
    fi
    
    # Step 6: Wait for service to be ready and verify
    log_info "Waiting for Netdata service to become ready..."
    local max_wait=30
    local wait_count=0
    
    while [ $wait_count -lt $max_wait ]; do
        if sudo systemctl is-active netdata >/dev/null 2>&1; then
            log_info "Netdata service is active and running"
            break
        fi
        
        wait_count=$((wait_count + 1))
        sleep 2
    done
    
    if [ $wait_count -ge $max_wait ]; then
        log_error "Netdata service failed to start within $max_wait seconds"
        log_error "Service status:"
        sudo systemctl status netdata --no-pager -l
        return 1
    fi
    
    # Step 7: Verify Netdata is listening on localhost
    sleep 5  # Additional wait for service to bind to port
    
    if sudo ss -tlnp | grep -q "127.0.0.1:19999"; then
        log_info "✓ Netdata is listening on localhost:19999"
    else
        log_warn "Netdata may not be listening on localhost:19999 yet"
        log_info "Current listening ports:"
        sudo ss -tlnp | grep ":19999" || log_warn "No process listening on port 19999"
    fi
    
    # Step 8: Test API response
    if curl -s --max-time 5 "http://127.0.0.1:19999/api/v1/info" >/dev/null 2>&1; then
        log_info "✓ Netdata API is responding"
    else
        log_warn "Netdata API test failed - service may still be initializing (this is normal)"
    fi
    
    # Step 9: Configure Nginx proxy and firewall
    if ! configure_netdata_nginx_proxy; then
        log_error "Failed to configure Nginx proxy for Netdata"
        return 1
    fi
    
    if ! configure_netdata_firewall; then
        log_error "Failed to configure firewall for Netdata"
        return 1
    fi
    
    log_info "Netdata monitoring infrastructure setup completed successfully"
    
    # Add local hosts entry for testing (if domain is configured)
    local netdata_domain="${NGINX_SERVER_NAME:-localhost}"
    if [ -n "$netdata_domain" ] && [ "$netdata_domain" != "localhost" ]; then
        log_info "Adding local hosts entry for testing: $netdata_domain"
        # Remove existing entry if present
        sudo sed -i "/$netdata_domain/d" /etc/hosts 2>/dev/null || true
        # Add new entry
        echo "127.0.0.1 $netdata_domain" | sudo tee -a /etc/hosts
        log_info "Added hosts entry: 127.0.0.1 $netdata_domain"
    fi
    
    return 0
}

verify_netdata_installation() {
    log_info "Verifying Netdata installation..."
    
    # Check if Netdata binary exists
    local netdata_binary="/opt/netdata/usr/sbin/netdata"
    if [ ! -f "$netdata_binary" ]; then
        # Fallback to system location
        netdata_binary="/usr/sbin/netdata"
        if [ ! -f "$netdata_binary" ]; then
            log_error "Netdata binary not found in /opt/netdata/usr/sbin/netdata or /usr/sbin/netdata"
            return 1
        fi
    fi
    log_info "✓ Netdata binary found: $netdata_binary"
    
    # Check if Netdata user exists
    if ! id netdata >/dev/null 2>&1; then
        log_error "Netdata user does not exist"
        return 1
    fi
    log_info "✓ Netdata user exists"
    
    # Check configuration file - FIXED: Use correct location
    local netdata_conf="/opt/netdata/etc/netdata/netdata.conf"
    if [ ! -f "$netdata_conf" ]; then
        # Fallback to system location
        netdata_conf="/etc/netdata/netdata.conf"
        if [ ! -f "$netdata_conf" ]; then
            log_error "Netdata configuration file not found"
            return 1
        fi
    fi
    log_info "✓ Netdata configuration file exists: $netdata_conf"
    
    # CRITICAL: Check required directories exist
    local required_dirs=(
        "/run/netdata"
        "/var/lib/netdata"
        "/opt/netdata/var/lib/netdata"
        "/opt/netdata/var/cache/netdata"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_warn "Required directory missing: $dir"
        else
            log_info "✓ Required directory exists: $dir"
        fi
    done
    
    # Check if required files exist
    local required_files=(
        "/opt/netdata/var/lib/netdata/cloud.d/cloud.conf"
        "/opt/netdata/etc/netdata/stream.conf"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_warn "Required file missing: $file"
        else
            log_info "✓ Required file exists: $file"
        fi
    done
    
    # Check systemd service
    if ! sudo systemctl is-enabled netdata >/dev/null 2>&1; then
        log_error "Netdata service is not enabled"
        return 1
    fi
    log_info "✓ Netdata service is enabled"
    
    # Enhanced service status check with multiple attempts
    local max_attempts=3
    local attempt=1
    local service_running=false
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Checking Netdata service status (attempt $attempt/$max_attempts)..."
        
        if sudo systemctl is-active netdata >/dev/null 2>&1; then
            service_running=true
            log_info "✓ Netdata service is active"
            break
        else
            local status=$(sudo systemctl show netdata --property=ActiveState --value)
            log_warn "Netdata service status: $status"
            
            if [ "$status" = "activating" ]; then
                log_info "Service is starting, waiting 10 seconds..."
                sleep 10
            elif [ "$status" = "failed" ]; then
                log_error "Service failed to start, checking logs..."
                sudo journalctl -u netdata --no-pager -n 10 | tail -5
                break
            else
                log_warn "Service in unexpected state: $status"
                sleep 5
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    if [ "$service_running" = false ]; then
        log_error "Netdata service is not running after $max_attempts attempts"
        log_error "Final service status:"
        sudo systemctl status netdata --no-pager -l
        return 1
    fi
    
    # Check if Netdata is listening on the correct port
    local netdata_port="${NETDATA_PORT:-19999}"
    local bind_ip="${NETDATA_BIND_IP:-127.0.0.1}"
    
    if sudo ss -tlnp | grep -q "${bind_ip}:${netdata_port}"; then
        log_info "✓ Netdata is listening on ${bind_ip}:${netdata_port}"
    else
        log_warn "Netdata may not be listening on expected address ${bind_ip}:${netdata_port}"
        log_info "Current listening ports:"
        sudo ss -tlnp | grep ":${netdata_port}" || log_warn "No process listening on port ${netdata_port}"
        # Don't fail here as it might still be starting
    fi
    
    log_info "Netdata installation verification completed"
    return 0
}

configure_netdata_systemd_override() {
    log_info "Creating systemd service override to fix directory paths..."
    
    # Create systemd override directory
    local override_dir="/etc/systemd/system/netdata.service.d"
    sudo mkdir -p "$override_dir"
    
    # Create override configuration that sets environment variables
    # This ensures Netdata uses the correct paths regardless of config file issues
    sudo tee "$override_dir/override.conf" > /dev/null << 'EOF'
[Service]
# Override environment variables to force correct paths for official installer
Environment="NETDATA_WEB_DIR=/opt/netdata/usr/share/netdata/web"
Environment="NETDATA_CACHE_DIR=/opt/netdata/var/cache/netdata"
Environment="NETDATA_LIB_DIR=/opt/netdata/var/lib/netdata"
Environment="NETDATA_LOG_DIR=/opt/netdata/var/log/netdata"
Environment="NETDATA_RUN_DIR=/run/netdata"
Environment="NETDATA_BIND_IP=127.0.0.1"
Environment="NETDATA_PORT=19999"

# Ensure runtime directory exists
ExecStartPre=/bin/mkdir -p /run/netdata
ExecStartPre=/bin/chown netdata:netdata /run/netdata
ExecStartPre=/bin/chmod 755 /run/netdata

# Ensure cache directory exists  
ExecStartPre=/bin/mkdir -p /opt/netdata/var/cache/netdata
ExecStartPre=/bin/chown -R netdata:netdata /opt/netdata/var/cache/netdata
EOF
    
    log_info "Systemd override created: $override_dir/override.conf"
    
    # Reload systemd to pick up the override
    sudo systemctl daemon-reload
    log_info "Systemd configuration reloaded"
    
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Source required utilities
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../utils/logger.sh"
    source "$SCRIPT_DIR/../utils/utilities.sh"
    
    # Load environment variables
    if [ -f "$SCRIPT_DIR/../conf/user.env" ]; then
        set -o allexport
        source "$SCRIPT_DIR/../conf/user.env"
        set +o allexport
    fi
    
    # Set defaults from default.env if not already set
    if [ -f "$SCRIPT_DIR/../conf/default.env" ]; then
        set -o allexport
        source "$SCRIPT_DIR/../conf/default.env"
        set +o allexport
    fi
    
    # Run the main setup function
    setup_netdata_monitoring
fi 