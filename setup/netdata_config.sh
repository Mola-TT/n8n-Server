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
# Netdata Installation Functions
# =============================================================================

install_netdata() {
    log_info "Installing Netdata system monitoring..."
    
    # Check if Netdata is already installed
    if command -v netdata &> /dev/null; then
        local netdata_version=$(netdata -W version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "unknown")
        log_info "Netdata is already installed: version $netdata_version"
        return 0
    fi
    
    # Update package index
    if ! execute_silently "apt-get update"; then
        log_error "Failed to update package index"
        return 1
    fi
    
    # Install required packages
    log_info "Installing Netdata dependencies..."
    if ! execute_silently "apt-get install -y curl wget gnupg"; then
        log_error "Failed to install dependencies"
        return 1
    fi
    
    # Download and install Netdata using official installer
    log_info "Downloading Netdata installer..."
    local installer_url="https://my-netdata.io/kickstart.sh"
    
    if ! execute_silently "wget -O /tmp/netdata-installer.sh '$installer_url'"; then
        log_error "Failed to download Netdata installer"
        return 1
    fi
    
    # Make installer executable
    chmod +x /tmp/netdata-installer.sh
    
    # Install Netdata with non-interactive options
    log_info "Installing Netdata (this may take a few minutes)..."
    if execute_silently "/tmp/netdata-installer.sh --dont-wait --disable-telemetry --auto-update"; then
        log_info "Netdata installed successfully"
    else
        log_error "Failed to install Netdata"
        return 1
    fi
    
    # Clean up installer
    rm -f /tmp/netdata-installer.sh
    
    # Verify installation using multiple methods
    log_info "Verifying Netdata installation..."
    
    # Method 1: Check if netdata command is available
    if command -v netdata &> /dev/null; then
        local netdata_version=$(netdata -W version 2>/dev/null | head -1 | cut -d' ' -f2 2>/dev/null || echo "")
        if [ -n "$netdata_version" ]; then
            log_info "Netdata verification successful: version $netdata_version"
        else
            log_info "Netdata command found but version check failed (normal after installation)"
        fi
    # Method 2: Check if netdata service/binary exists in common locations
    elif [ -f "/usr/sbin/netdata" ] || [ -f "/usr/bin/netdata" ] || [ -f "/opt/netdata/bin/netdata" ]; then
        log_info "Netdata binary found in system paths"
    # Method 3: Check if netdata configuration directory exists
    elif [ -d "/etc/netdata" ]; then
        log_info "Netdata configuration directory found"
    # Method 4: Check if netdata systemd service exists
    elif systemctl list-unit-files | grep -q "netdata.service"; then
        log_info "Netdata systemd service found"
    else
        log_error "Netdata installation verification failed - no evidence of installation found"
        return 1
    fi
    
    log_info "Netdata installation verification completed successfully"
    return 0
}

# =============================================================================
# Netdata Configuration Functions
# =============================================================================

configure_netdata_security() {
    log_info "Configuring Netdata security settings..."
    
    local netdata_conf="/etc/netdata/netdata.conf"
    local backup_conf="/etc/netdata/netdata.conf.backup"
    
    # Create backup of original configuration
    if [ -f "$netdata_conf" ] && [ ! -f "$backup_conf" ]; then
        cp "$netdata_conf" "$backup_conf"
        log_info "Created backup: $backup_conf"
    fi
    
    # Configure Netdata to bind only to localhost for security
    log_info "Configuring Netdata to listen only on localhost..."
    
    # Detect actual Netdata installation paths
    local cache_dir="/var/cache/netdata"
    local lib_dir="/var/lib/netdata" 
    local log_dir="/var/log/netdata"
    local run_dir="/var/run/netdata"
    local web_dir="/usr/share/netdata/web"
    
    # Check if Netdata is installed in /opt/netdata (official installer)
    if [ -d "/opt/netdata" ]; then
        cache_dir="/opt/netdata/var/cache/netdata"
        lib_dir="/opt/netdata/var/lib/netdata"
        log_dir="/opt/netdata/var/log/netdata"
        run_dir="/opt/netdata/var/run/netdata"
        web_dir="/opt/netdata/usr/share/netdata/web"
        log_info "Detected official Netdata installation in /opt/netdata"
    fi
    
    # Create or update configuration - fix binding issue
    cat > "$netdata_conf" << EOF
# Netdata Configuration - Milestone 4
# Generated by n8n server initialization

[global]
    # Default update frequency (seconds)
    update every = 1
    
    # Memory mode
    memory mode = save
    
    # Disable registry for privacy
    registry enabled = ${NETDATA_REGISTRY_ENABLED:-no}
    
    # Disable anonymous statistics
    anonymous statistics = ${NETDATA_ANONYMOUS_STATISTICS:-no}
    
    # Set directories
    cache directory = ${NETDATA_CACHE_DIR:-$cache_dir}
    lib directory = ${NETDATA_LIB_DIR:-$lib_dir}
    log directory = ${NETDATA_LOG_DIR:-$log_dir}
    run directory = ${NETDATA_RUN_DIR:-$run_dir}
    web files directory = ${NETDATA_WEB_DIR:-$web_dir}

[web]
    # Web server configuration - CRITICAL: bind to localhost only
    mode = static-threaded
    listen backlog = 4096
    default port = ${NETDATA_PORT:-19999}
    bind to = ${NETDATA_BIND_IP:-127.0.0.1}
    
    # Security headers
    enable gzip compression = yes
    web files group = netdata
    web files owner = netdata

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
    script to execute on alarm = /usr/libexec/netdata/plugins.d/alarm-notify.sh
    
EOF
    
    log_info "Netdata configuration updated successfully"
    
    # Restart Netdata service to apply localhost-only binding
    log_info "Restarting Netdata service to apply security configuration..."
    if execute_silently "systemctl restart netdata"; then
        log_info "Netdata service restarted successfully"
        
        # Wait for service to start and verify binding
        sleep 5
        
        # Check if Netdata is now properly bound to localhost
        if ss -tlnp | grep -q "127.0.0.1:${NETDATA_PORT:-19999}"; then
            log_info "Netdata is now properly bound to localhost only"
        else
            log_warn "Netdata may not be bound to localhost - check configuration"
        fi
    else
        log_error "Failed to restart Netdata service"
        return 1
    fi
    
    return 0
}

configure_netdata_health_alerts() {
    log_info "Configuring Netdata health monitoring alerts..."
    
    local health_dir="/etc/netdata/health.d"
    local notification_script="/usr/libexec/netdata/plugins.d/alarm-notify.sh"
    
    # Create health.d directory if it doesn't exist
    mkdir -p "$health_dir"
    
    # Configure CPU usage alerts
    cat > "$health_dir/cpu_usage.conf" << EOF
# CPU Usage Alert Configuration - Milestone 4

 alarm: cpu_usage_high
    on: system.cpu
lookup: average -3m unaligned of user,system,softirq,irq,guest
 units: %
 every: 10s
  warn: \$this > ${NETDATA_CPU_THRESHOLD:-80}
  crit: \$this > 95
 delay: down 15m multiplier 1.5 max 1h
  info: Average CPU utilization over the last 3 minutes
    to: sysadmin

EOF
    
    # Configure RAM usage alerts
    cat > "$health_dir/ram_usage.conf" << EOF
# RAM Usage Alert Configuration - Milestone 4

 alarm: ram_usage_high
    on: system.ram
lookup: average -3m unaligned of used
  calc: \$this * 100 / (\$this + \$avail)
 units: %
 every: 10s
  warn: \$this > ${NETDATA_RAM_THRESHOLD:-80}
  crit: \$this > 95
 delay: down 15m multiplier 1.5 max 1h
  info: RAM utilization over the last 3 minutes
    to: sysadmin

EOF
    
    # Configure disk usage alerts
    cat > "$health_dir/disk_usage.conf" << EOF
# Disk Usage Alert Configuration - Milestone 4

 alarm: disk_space_usage_high
    on: disk_space.used
lookup: average -1m unaligned of used
  calc: \$this
 units: %
 every: 10s
  warn: \$this > ${NETDATA_DISK_THRESHOLD:-80}
  crit: \$this > 95
 delay: down 15m multiplier 1.5 max 1h
  info: Disk space utilization
    to: sysadmin

EOF
    
    # Configure load average alerts
    cat > "$health_dir/load_average.conf" << EOF
# Load Average Alert Configuration - Milestone 4

 alarm: load_average_high
    on: system.load
lookup: average -3m unaligned of load1
 units: load
 every: 10s
  warn: \$this > ${NETDATA_LOAD_THRESHOLD:-3.0}
  crit: \$this > 5.0
 delay: down 15m multiplier 1.5 max 1h
  info: System load average over the last 3 minutes
    to: sysadmin

EOF
    
    # Configure email notifications if enabled
    if [ "${NETDATA_EMAIL_ALERTS:-true}" = "true" ]; then
        configure_netdata_email_notifications
    fi
    
    log_info "Health monitoring alerts configured successfully"
    return 0
}

configure_netdata_email_notifications() {
    log_info "Configuring Netdata email notifications..."
    
    local health_alarm_notify="/etc/netdata/health_alarm_notify.conf"
    
    # Create notification configuration
    cat > "$health_alarm_notify" << EOF
# Netdata Health Alarm Notification Configuration - Milestone 4

# Enable sending emails
SEND_EMAIL="YES"

# Default recipient for all alarms
DEFAULT_RECIPIENT_EMAIL="${NETDATA_ALERT_EMAIL_RECIPIENT:-root}"

# Email settings
EMAIL_SENDER="${NETDATA_ALERT_EMAIL_SENDER:-netdata@localhost}"
SMTP_SERVER="${SMTP_SERVER:-localhost}"
SMTP_PORT="${SMTP_PORT:-25}"

# Role configurations
role_recipients_email[sysadmin]="${NETDATA_ALERT_EMAIL_RECIPIENT:-root}"

# Silent period for repeated notifications (in seconds)
DEFAULT_RECIPIENT_EMAIL_SILENT_PERIOD=3600

# Custom email subject
EMAIL_SUBJECT="[Netdata Alert] \${host} \${alarm} \${status}"

EOF
    
    # Set proper permissions
    chown netdata:netdata "$health_alarm_notify"
    chmod 640 "$health_alarm_notify"
    
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
        echo "${NETDATA_NGINX_AUTH_PASSWORD}" | htpasswd -ci "$auth_file" "${NETDATA_NGINX_AUTH_USER}"
    else
        # Install apache2-utils for htpasswd
        if execute_silently "apt-get install -y apache2-utils"; then
            echo "${NETDATA_NGINX_AUTH_PASSWORD}" | htpasswd -ci "$auth_file" "${NETDATA_NGINX_AUTH_USER}"
        else
            log_error "Failed to install apache2-utils for password generation"
            return 1
        fi
    fi
    
    if [ -f "$auth_file" ]; then
        chmod 640 "$auth_file"
        chown root:www-data "$auth_file"
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
        chown root:www-data "$ssl_key_path"
        log_info "Fixed SSL private key permissions: $ssl_key_path"
    else
        log_error "SSL private key not found: $ssl_key_path"
        return 1
    fi
    
    if [ -f "$ssl_cert_path" ]; then
        chmod 644 "$ssl_cert_path"
        chown root:www-data "$ssl_cert_path"
        log_info "SSL certificate permissions verified: $ssl_cert_path"
    else
        log_error "SSL certificate not found: $ssl_cert_path"
        return 1
    fi
    
    # Create Nginx configuration for Netdata
    local server_name="${NETDATA_NGINX_SUBDOMAIN}.${NGINX_SERVER_NAME:-localhost}"
    
    cat > "$netdata_conf" << EOF
# Netdata Nginx Configuration - Milestone 4
# Secure HTTPS proxy for Netdata dashboard

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name $server_name;
    
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
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    
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
    }
    
    # Access and error logs
    access_log ${NETDATA_NGINX_ACCESS_LOG};
    error_log ${NETDATA_NGINX_ERROR_LOG};
}
EOF
    
    # Enable the configuration
    if [ ! -L "$nginx_enabled_dir/netdata" ]; then
        ln -sf "$netdata_conf" "$nginx_enabled_dir/netdata"
        log_info "Netdata Nginx configuration enabled"
    else
        log_info "Netdata Nginx configuration already enabled"
    fi
    
    # Test Nginx configuration
    if nginx -t &>/dev/null; then
        log_info "Nginx configuration test successful"
        
        # Reload Nginx
        if execute_silently "systemctl reload nginx"; then
            log_info "Nginx reloaded successfully"
        else
            log_warn "Failed to reload Nginx - manual restart may be required"
        fi
    else
        log_error "Nginx configuration test failed"
        log_error "Running nginx -t for detailed error information..."
        nginx -t
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
        
        # Explicitly deny external access to Netdata port
        if execute_silently "ufw deny ${NETDATA_PORT:-19999}/tcp"; then
            log_info "Direct access to Netdata port blocked via firewall"
        else
            log_warn "Failed to block Netdata port via firewall"
        fi
    fi
    
    # Ensure HTTP and HTTPS are still allowed for Nginx proxy
    if execute_silently "ufw allow 80/tcp" && execute_silently "ufw allow 443/tcp"; then
        log_info "HTTP/HTTPS access confirmed for Nginx proxy"
    else
        log_warn "Failed to ensure HTTP/HTTPS access"
    fi
    
    # Display current firewall status
    local firewall_status=$(ufw status 2>/dev/null | head -1)
    if [[ "$firewall_status" == *"active"* ]]; then
        # Count the rules for summary
        local ssh_rules=$(ufw status numbered 2>/dev/null | grep -c "22/tcp" || echo "0")
        local http_rules=$(ufw status numbered 2>/dev/null | grep -c "80/tcp" || echo "0") 
        local https_rules=$(ufw status numbered 2>/dev/null | grep -c "443/tcp" || echo "0")
        
        log_info "UFW firewall is active"
        log_info "Firewall rules: SSH ($ssh_rules), HTTP ($http_rules), HTTPS ($https_rules)"
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
        if systemctl is-active netdata &>/dev/null; then
            log_info "Netdata service is running"
            break
        fi
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    # Final service status check
    if systemctl is-active netdata &>/dev/null; then
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
        systemctl status netdata --no-pager -l 2>/dev/null | head -10 | while read line; do
            log_error "Service status: $line"
        done
        return 1
    fi
    
    return 0
}

# =============================================================================
# Main Setup Function
# =============================================================================

setup_netdata_infrastructure() {
    log_info "Setting up Netdata monitoring infrastructure..."
    
    # Check if Netdata is enabled
    if [ "${NETDATA_ENABLED:-true}" != "true" ]; then
        log_info "Netdata is disabled - skipping setup"
        return 0
    fi
    
    # Install Netdata
    if ! install_netdata; then
        log_error "Failed to install Netdata"
        return 1
    fi
    
    # Configure Netdata security
    if ! configure_netdata_security; then
        log_error "Failed to configure Netdata security"
        return 1
    fi
    
    # Configure health monitoring
    if ! configure_netdata_health_alerts; then
        log_error "Failed to configure health monitoring"
        return 1
    fi
    
    # Start Netdata service
    if ! start_netdata_service; then
        log_error "Failed to start Netdata service"
        return 1
    fi
    
    # Configure Nginx proxy
    if ! configure_netdata_nginx_proxy; then
        log_error "Failed to configure Nginx proxy for Netdata"
        return 1
    fi
    
    # Configure firewall
    if ! configure_netdata_firewall; then
        log_error "Failed to configure firewall for Netdata"
        return 1
    fi
    
    log_info "Netdata monitoring infrastructure setup completed successfully"
    
    # Add local hosts entry for testing if not in production
    local server_name="${NETDATA_NGINX_SUBDOMAIN}.${NGINX_SERVER_NAME:-localhost}"
    if [ "${PRODUCTION:-false}" != "true" ] && [ "$server_name" != "monitoring.localhost" ]; then
        log_info "Adding local hosts entry for testing: $server_name"
        if ! grep -q "$server_name" /etc/hosts; then
            echo "127.0.0.1 $server_name" >> /etc/hosts
            log_info "Added hosts entry: 127.0.0.1 $server_name"
        else
            log_info "Hosts entry already exists for $server_name"
        fi
    fi
    
    # Display access information
    echo "-----------------------------------------------"
    echo "NETDATA ACCESS INFORMATION"
    echo "-----------------------------------------------"
    log_info "Dashboard URL: https://$server_name"
    log_info "Username: ${NETDATA_NGINX_AUTH_USER}"
    log_info "Password: [configured]"
    log_info "Local access: http://${NETDATA_BIND_IP}:${NETDATA_PORT} (localhost only)"
    echo "-----------------------------------------------"
    
    return 0
} 