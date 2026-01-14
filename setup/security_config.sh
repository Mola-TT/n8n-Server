#!/bin/bash

# ==============================================================================
# Security Configuration Script for n8n Server - Milestone 9
# ==============================================================================
# This script sets up comprehensive security hardening including fail2ban,
# enhanced rate limiting, security headers, and monitoring
# ==============================================================================

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# ==============================================================================
# Default Configuration
# ==============================================================================

# Security feature toggles
SECURITY_ENABLED="${SECURITY_ENABLED:-true}"
FAIL2BAN_ENABLED="${FAIL2BAN_ENABLED:-true}"
GEO_BLOCKING_ENABLED="${GEO_BLOCKING_ENABLED:-false}"

# fail2ban settings
FAIL2BAN_BANTIME="${FAIL2BAN_BANTIME:-3600}"
FAIL2BAN_MAXRETRY="${FAIL2BAN_MAXRETRY:-5}"
FAIL2BAN_FINDTIME="${FAIL2BAN_FINDTIME:-600}"
FAIL2BAN_EMAIL_NOTIFY="${FAIL2BAN_EMAIL_NOTIFY:-true}"

# Whitelist (comma-separated IPs)
SECURITY_WHITELIST_IPS="${SECURITY_WHITELIST_IPS:-}"

# Rate limiting settings
RATE_LIMIT_WEBHOOK="${RATE_LIMIT_WEBHOOK:-10r/s}"
RATE_LIMIT_API="${RATE_LIMIT_API:-30r/s}"
RATE_LIMIT_UI="${RATE_LIMIT_UI:-100r/s}"

# Security alert settings
SECURITY_ALERT_THRESHOLD="${SECURITY_ALERT_THRESHOLD:-10}"
SECURITY_REPORT_SCHEDULE="${SECURITY_REPORT_SCHEDULE:-0 6 * * *}"

# Paths
SECURITY_LOG_FILE="/var/log/n8n_security.log"
SECURITY_SCRIPTS_DIR="/opt/n8n/scripts"
FAIL2BAN_FILTER_DIR="/etc/fail2ban/filter.d"
FAIL2BAN_JAIL_DIR="/etc/fail2ban/jail.d"

# ==============================================================================
# Logging Functions
# ==============================================================================

log_security() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO") log_info "$message" ;;
        "WARN") log_warn "$message" ;;
        "ERROR") log_error "$message" ;;
        "DEBUG") log_debug "$message" ;;
    esac
    
    # Also log to security-specific log file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$SECURITY_LOG_FILE"
}

# ==============================================================================
# fail2ban Installation and Configuration
# ==============================================================================

install_fail2ban() {
    log_info "Installing fail2ban..."
    
    # Check if fail2ban is already installed
    if command -v fail2ban-client &> /dev/null; then
        local version=$(fail2ban-client --version 2>&1 | head -1)
        log_info "fail2ban is already installed: $version"
        return 0
    fi
    
    # Install fail2ban
    if ! execute_silently "apt-get update"; then
        log_error "Failed to update package index"
        return 1
    fi
    
    if ! execute_silently "apt-get install -y fail2ban"; then
        log_error "Failed to install fail2ban"
        return 1
    fi
    
    # Verify installation
    if command -v fail2ban-client &> /dev/null; then
        log_info "fail2ban installed successfully"
    else
        log_error "fail2ban installation verification failed"
        return 1
    fi
    
    return 0
}

configure_fail2ban_base() {
    log_info "Configuring fail2ban base settings..."
    
    # Create jail.local with base configuration
    cat > /etc/fail2ban/jail.local << EOF
# ==============================================================================
# fail2ban Configuration for n8n Server - Milestone 9
# ==============================================================================

[DEFAULT]
# Ban settings
bantime = ${FAIL2BAN_BANTIME}
findtime = ${FAIL2BAN_FINDTIME}
maxretry = ${FAIL2BAN_MAXRETRY}

# Email notifications
destemail = ${EMAIL_RECIPIENT:-root@localhost}
sender = ${EMAIL_SENDER:-fail2ban@localhost}
mta = sendmail

# Action: ban and send email
action = %(action_mwl)s

# Whitelist IPs (localhost always whitelisted)
ignoreip = 127.0.0.1/8 ::1 ${SECURITY_WHITELIST_IPS//,/ }

# Backend
backend = systemd

# Log encoding
logencoding = utf-8
EOF

    log_info "fail2ban base configuration created"
    return 0
}

configure_fail2ban_ssh() {
    log_info "Configuring fail2ban SSH protection..."
    
    # Create SSH jail configuration
    cat > "${FAIL2BAN_JAIL_DIR}/n8n-sshd.conf" << EOF
# SSH protection for n8n server
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = ${FAIL2BAN_MAXRETRY}
bantime = ${FAIL2BAN_BANTIME}
findtime = ${FAIL2BAN_FINDTIME}

# Progressive banning for repeat offenders
[sshd-aggressive]
enabled = true
port = ssh
filter = sshd[mode=aggressive]
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
findtime = 3600
EOF

    log_info "SSH jail configuration created"
    return 0
}

configure_fail2ban_nginx() {
    log_info "Configuring fail2ban Nginx protection..."
    
    # Create Nginx authentication failure filter
    cat > "${FAIL2BAN_FILTER_DIR}/nginx-http-auth-n8n.conf" << 'EOF'
# Nginx HTTP authentication failure filter for n8n
[Definition]
failregex = ^<HOST> .* "(GET|POST|PUT|DELETE|PATCH)" (401|403)
            ^ \[error\] \d+#\d+: \*\d+ user ".*" was not found in ".*", client: <HOST>
            ^ \[error\] \d+#\d+: \*\d+ no user/password was provided for basic authentication, client: <HOST>
ignoreregex =
EOF

    # Create bad bot filter
    cat > "${FAIL2BAN_FILTER_DIR}/nginx-badbots-n8n.conf" << 'EOF'
# Bad bots and vulnerability scanner filter for n8n
[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD)" .* (sqlmap|nikto|nessus|nmap|masscan|ZmEu|w3af|Acunetix|havij|Netsparker)
            ^<HOST> .* "(GET|POST)" .*(\.\./|\.\.\\|%%2e%%2e|%%252e%%252e)
            ^<HOST> .* "(GET|POST)" .*(union.*select|select.*from|insert.*into|drop.*table|update.*set)
            ^<HOST> .* "(GET|POST)" .*(<script|javascript:|vbscript:|onclick=|onerror=)
            ^<HOST> .* "(GET|POST)" .*/wp-(admin|content|includes|login)
            ^<HOST> .* "(GET|POST)" .*/phpmyadmin
            ^<HOST> .* "(GET|POST)" .*/\.env
            ^<HOST> .* "(GET|POST)" .*/\.git
ignoreregex =
EOF

    # Create webhook abuse filter
    cat > "${FAIL2BAN_FILTER_DIR}/nginx-webhook-abuse.conf" << 'EOF'
# Webhook abuse and scanning filter for n8n
[Definition]
failregex = ^<HOST> .* "(GET|POST)" .*/webhook/.* 404
            ^<HOST> .* "(GET|POST)" .*/webhook-test/.* 404
            ^<HOST> .* "(GET|POST)" .*/rest/webhook/.* 404
ignoreregex =
EOF

    # Create Nginx jail configurations
    cat > "${FAIL2BAN_JAIL_DIR}/n8n-nginx.conf" << EOF
# Nginx authentication failure jail
[nginx-http-auth-n8n]
enabled = true
port = http,https
filter = nginx-http-auth-n8n
logpath = /var/log/nginx/n8n_access.log
          /var/log/nginx/access.log
maxretry = ${FAIL2BAN_MAXRETRY}
bantime = ${FAIL2BAN_BANTIME}
findtime = ${FAIL2BAN_FINDTIME}

# Bad bots and vulnerability scanners jail
[nginx-badbots-n8n]
enabled = true
port = http,https
filter = nginx-badbots-n8n
logpath = /var/log/nginx/n8n_access.log
          /var/log/nginx/access.log
maxretry = 2
bantime = 86400
findtime = 600

# Webhook abuse jail (scanning for webhooks)
[nginx-webhook-abuse]
enabled = true
port = http,https
filter = nginx-webhook-abuse
logpath = /var/log/nginx/n8n_access.log
          /var/log/nginx/access.log
maxretry = 10
bantime = 3600
findtime = 300
EOF

    log_info "Nginx jail configurations created"
    return 0
}

configure_fail2ban_api() {
    log_info "Configuring fail2ban User Management API protection..."
    
    # Create API brute-force filter
    cat > "${FAIL2BAN_FILTER_DIR}/n8n-api-auth.conf" << 'EOF'
# n8n User Management API authentication failure filter
[Definition]
failregex = ^<HOST> .* "(POST)" .*/api/auth/login.* 401
            ^<HOST> .* "(POST)" .*/api/users.* 401
            ^<HOST> .* "(GET|POST|PUT|DELETE)" .*/api/.* 403
ignoreregex =
EOF

    # Create API jail configuration
    cat > "${FAIL2BAN_JAIL_DIR}/n8n-api.conf" << EOF
# n8n User Management API protection
[n8n-api-auth]
enabled = true
port = http,https
filter = n8n-api-auth
logpath = /var/log/nginx/n8n_access.log
maxretry = 5
bantime = 7200
findtime = 600
EOF

    log_info "API jail configuration created"
    return 0
}

ensure_log_files_exist() {
    log_info "Ensuring required log files exist for fail2ban..."
    
    # Create nginx log directory if missing
    mkdir -p /var/log/nginx
    
    # Touch log files that fail2ban monitors (fail2ban fails if logs don't exist)
    local log_files=(
        "/var/log/nginx/n8n_access.log"
        "/var/log/nginx/access.log"
        "/var/log/nginx/error.log"
        "/var/log/nginx/webhook_access.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [[ ! -f "$log_file" ]]; then
            touch "$log_file"
            chmod 644 "$log_file"
            log_debug "Created log file: $log_file"
        fi
    done
    
    # Ensure auth.log exists (for SSH jail)
    if [[ ! -f "/var/log/auth.log" ]]; then
        touch /var/log/auth.log
        chmod 640 /var/log/auth.log
    fi
}

start_fail2ban() {
    log_info "Starting fail2ban service..."
    
    # Ensure log files exist before starting fail2ban
    ensure_log_files_exist
    
    # Test fail2ban configuration first
    if ! fail2ban-client -t &>/dev/null; then
        log_warn "fail2ban configuration has issues, checking details..."
        fail2ban-client -t 2>&1 | head -20
        log_warn "Attempting to start anyway..."
    fi
    
    # Enable and start fail2ban
    if execute_silently "systemctl enable fail2ban"; then
        log_info "fail2ban service enabled"
    else
        log_warn "Failed to enable fail2ban service"
    fi
    
    # Restart to apply new configuration
    if execute_silently "systemctl restart fail2ban"; then
        log_info "fail2ban service started successfully"
    else
        log_error "Failed to start fail2ban service"
        # Show why it failed
        journalctl -u fail2ban -n 10 --no-pager 2>/dev/null || true
        return 1
    fi
    
    # Verify status
    sleep 2
    if systemctl is-active fail2ban &>/dev/null; then
        log_info "fail2ban is running"
        
        # Show jail status summary
        local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//')
        log_info "Active jails: $jails"
    else
        log_error "fail2ban is not running"
        journalctl -u fail2ban -n 20 --no-pager 2>/dev/null || true
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Nginx Security Hardening
# ==============================================================================

create_nginx_security_config() {
    log_info "Creating Nginx security configuration..."
    
    local security_conf="/etc/nginx/conf.d/security.conf"
    
    cat > "$security_conf" << 'EOF'
# ==============================================================================
# Nginx Security Configuration for n8n Server - Milestone 9
# ==============================================================================

# Hide Nginx version
server_tokens off;

# Prevent clickjacking (can be overridden per-location for iframes)
# Note: X-Frame-Options is set in main config for iframe support

# Prevent MIME type sniffing
add_header X-Content-Type-Options "nosniff" always;

# XSS Protection
add_header X-XSS-Protection "1; mode=block" always;

# Referrer Policy
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# Permissions Policy (formerly Feature-Policy)
add_header Permissions-Policy "geolocation=(), midi=(), sync-xhr=(), microphone=(), camera=(), magnetometer=(), gyroscope=(), fullscreen=(self), payment=()" always;

# Request limits to prevent slowloris attacks
client_body_timeout 10s;
client_header_timeout 10s;
keepalive_timeout 65s;
send_timeout 10s;

# Limit request body size (can be overridden per-location)
client_max_body_size 100M;

# Limit request header size
large_client_header_buffers 4 16k;

# Connection limits per IP
limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;

# Map for common exploit detection (map is allowed in http context)
# Using simplified patterns that are Nginx-safe
map $query_string $block_common_exploits {
    default 0;
    ~*script 1;
    ~*%3Cscript 1;
    ~*GLOBALS= 1;
    ~*_REQUEST= 1;
    ~*proc/self/environ 1;
    ~*base64_encode 1;
    ~*base64_decode 1;
}
EOF

    log_info "Nginx security configuration created: $security_conf"
    return 0
}

create_nginx_bad_user_agents_config() {
    log_info "Creating Nginx bad user agents configuration..."
    
    local ua_conf="/etc/nginx/conf.d/bad_user_agents.conf"
    
    cat > "$ua_conf" << 'EOF'
# ==============================================================================
# Bad User Agent Blocking for n8n Server - Milestone 9
# ==============================================================================

# Map bad user agents to block
map $http_user_agent $bad_user_agent {
    default 0;
    
    # Vulnerability scanners
    ~*nikto 1;
    ~*sqlmap 1;
    ~*nessus 1;
    ~*openvas 1;
    ~*w3af 1;
    ~*acunetix 1;
    ~*netsparker 1;
    ~*qualys 1;
    ~*havij 1;
    
    # Bad bots
    ~*ZmEu 1;
    ~*masscan 1;
    ~*nmap 1;
    ~*^$ 1;
    
    # Scrapers
    ~*HTTrack 1;
    ~*wget 0;  # Allow wget (useful for health checks)
    ~*curl 0;  # Allow curl (useful for health checks)
    
    # Known malicious user agents
    ~*Morfeus 1;
    ~*DirBuster 1;
    ~*FHscan 1;
}

# Map suspicious request patterns
map $request_uri $suspicious_request {
    default 0;
    
    # WordPress probing (n8n is not WordPress)
    ~*wp-admin 1;
    ~*wp-login 1;
    ~*wp-content 1;
    ~*wp-includes 1;
    ~*xmlrpc.php 1;
    
    # phpMyAdmin probing
    ~*phpmyadmin 1;
    ~*pma 1;
    ~*myadmin 1;
    
    # Shell/config probing
    ~*\.env 1;
    ~*\.git 1;
    ~*\.htaccess 1;
    ~*\.htpasswd 1;
    ~*\.ssh 1;
    ~*\.bash 1;
    ~*config\.php 1;
    ~*\.sql 1;
    
    # Path traversal attempts
    ~*\.\./ 1;
    ~*%2e%2e 1;
}
EOF

    log_info "Bad user agents configuration created: $ua_conf"
    return 0
}

create_nginx_rate_limit_zones() {
    log_info "Creating Nginx rate limit zones configuration..."
    
    local rate_conf="/etc/nginx/conf.d/rate_limits.conf"
    
    cat > "$rate_conf" << EOF
# ==============================================================================
# Rate Limiting Zones for n8n Server - Milestone 9
# ==============================================================================

# Webhook rate limiting (more restrictive)
limit_req_zone \$binary_remote_addr zone=webhook_limit:10m rate=${RATE_LIMIT_WEBHOOK};

# API rate limiting
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=${RATE_LIMIT_API};

# UI rate limiting (more permissive for page loads)
limit_req_zone \$binary_remote_addr zone=ui_limit:10m rate=${RATE_LIMIT_UI};

# Login rate limiting (very restrictive)
limit_req_zone \$binary_remote_addr zone=login_limit:10m rate=5r/m;

# Connection rate limiting
limit_conn_zone \$binary_remote_addr zone=conn_per_ip:10m;
EOF

    log_info "Rate limit zones configuration created: $rate_conf"
    return 0
}

update_nginx_n8n_config_security() {
    log_info "Updating n8n Nginx configuration with security enhancements..."
    
    local n8n_conf="/etc/nginx/sites-available/n8n"
    
    # Check if n8n config exists
    if [[ ! -f "$n8n_conf" ]]; then
        log_warn "n8n Nginx configuration not found, skipping security updates"
        return 0
    fi
    
    # Create security snippet to be included
    local security_snippet="/etc/nginx/snippets/n8n-security.conf"
    mkdir -p /etc/nginx/snippets
    
    cat > "$security_snippet" << 'EOF'
# ==============================================================================
# n8n Security Snippet - Milestone 9
# ==============================================================================

# Block bad user agents
if ($bad_user_agent) {
    return 403;
}

# Block suspicious requests
if ($suspicious_request) {
    return 403;
}

# Block common exploits (set in security.conf)
if ($block_common_exploits) {
    return 403;
}

# Webhook endpoint protection
location ~ ^/(webhook|webhook-test|rest/webhook)/ {
    # Apply webhook rate limiting
    limit_req zone=webhook_limit burst=10 nodelay;
    limit_conn conn_per_ip 10;
    
    # Log all webhook access for security audit
    access_log /var/log/nginx/webhook_access.log;
    
    # Limit request body size for webhooks
    client_max_body_size 10M;
    
    proxy_pass http://n8n_backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

# Login endpoint protection
location ~ ^/(rest/)?login {
    # Very restrictive rate limiting for login
    limit_req zone=login_limit burst=3 nodelay;
    
    proxy_pass http://n8n_backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
EOF

    log_info "Security snippet created: $security_snippet"
    log_info "Note: Include 'include /etc/nginx/snippets/n8n-security.conf;' in n8n server block for full protection"
    
    return 0
}

reload_nginx() {
    log_info "Reloading Nginx configuration..."
    
    # Test configuration
    if ! nginx -t &>/dev/null; then
        log_error "Nginx configuration test failed"
        nginx -t  # Show error details
        return 1
    fi
    
    # Reload Nginx
    if execute_silently "systemctl reload nginx"; then
        log_info "Nginx reloaded successfully"
    else
        log_error "Failed to reload Nginx"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Security Monitoring Script Creation
# ==============================================================================

create_security_monitor_script() {
    log_info "Creating security monitoring script..."
    
    local monitor_script="${SECURITY_SCRIPTS_DIR}/security_monitor.sh"
    
    mkdir -p "$SECURITY_SCRIPTS_DIR"
    
    cat > "$monitor_script" << 'MONITOR_SCRIPT'
#!/bin/bash

# ==============================================================================
# Security Monitor Script for n8n Server - Milestone 9
# ==============================================================================

# Configuration
SECURITY_LOG="/var/log/n8n_security.log"
ALERT_THRESHOLD="${SECURITY_ALERT_THRESHOLD:-10}"
EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-root@localhost}"
EMAIL_SENDER="${EMAIL_SENDER:-security@localhost}"

# Initialize counters
NGINX_AUTH_FAILURES=0
SSH_AUTH_FAILURES=0
BANNED_IPS=0
SUSPICIOUS_REQUESTS=0

log_monitor() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MONITOR] $1" >> "$SECURITY_LOG"
}

# Check fail2ban status
check_fail2ban() {
    if ! systemctl is-active fail2ban &>/dev/null; then
        log_monitor "WARNING: fail2ban is not running!"
        return 1
    fi
    
    # Get banned IP count
    BANNED_IPS=$(fail2ban-client status 2>/dev/null | grep -oP 'Currently banned:\s+\K\d+' | awk '{s+=$1} END {print s+0}')
    log_monitor "Currently banned IPs: $BANNED_IPS"
    
    return 0
}

# Check recent auth failures in Nginx logs
check_nginx_auth() {
    local log_file="/var/log/nginx/n8n_access.log"
    
    if [[ -f "$log_file" ]]; then
        # Count 401/403 responses in last hour
        local one_hour_ago=$(date -d '1 hour ago' '+%d/%b/%Y:%H')
        NGINX_AUTH_FAILURES=$(grep -c " 40[13] " "$log_file" 2>/dev/null | tail -1000 | wc -l)
        log_monitor "Nginx auth failures (last 1000 entries): $NGINX_AUTH_FAILURES"
    fi
}

# Check SSH auth failures
check_ssh_auth() {
    local auth_log="/var/log/auth.log"
    
    if [[ -f "$auth_log" ]]; then
        # Count failed SSH attempts in last hour
        SSH_AUTH_FAILURES=$(grep -c "Failed password" "$auth_log" 2>/dev/null | tail -100 | wc -l)
        log_monitor "SSH auth failures (recent): $SSH_AUTH_FAILURES"
    fi
}

# Check for suspicious patterns in logs
check_suspicious_patterns() {
    local log_file="/var/log/nginx/n8n_access.log"
    
    if [[ -f "$log_file" ]]; then
        # Check for scanning patterns
        SUSPICIOUS_REQUESTS=$(grep -cE "(wp-admin|phpmyadmin|\.env|\.git|sqlmap|nikto)" "$log_file" 2>/dev/null | tail -500 | wc -l)
        log_monitor "Suspicious requests detected: $SUSPICIOUS_REQUESTS"
    fi
}

# Send alert email
send_alert() {
    local subject="$1"
    local body="$2"
    
    if command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" -r "$EMAIL_SENDER" "$EMAIL_RECIPIENT"
        log_monitor "Alert sent: $subject"
    elif command -v sendmail &>/dev/null; then
        {
            echo "From: $EMAIL_SENDER"
            echo "To: $EMAIL_RECIPIENT"
            echo "Subject: $subject"
            echo ""
            echo "$body"
        } | sendmail -t
        log_monitor "Alert sent via sendmail: $subject"
    else
        log_monitor "Cannot send alert - no mail tool available"
    fi
}

# Generate security summary
generate_summary() {
    local summary="n8n Security Monitor Report - $(date '+%Y-%m-%d %H:%M:%S')

=== SECURITY STATUS ===
fail2ban Status: $(systemctl is-active fail2ban 2>/dev/null || echo 'unknown')
Currently Banned IPs: $BANNED_IPS
Nginx Auth Failures: $NGINX_AUTH_FAILURES
SSH Auth Failures: $SSH_AUTH_FAILURES
Suspicious Requests: $SUSPICIOUS_REQUESTS

=== FAIL2BAN JAILS ===
$(fail2ban-client status 2>/dev/null || echo 'fail2ban not running')

=== RECENT BANS ===
$(grep -h "Ban " /var/log/fail2ban.log 2>/dev/null | tail -10 || echo 'No recent bans')
"
    
    echo "$summary"
}

# Main monitoring logic
main() {
    log_monitor "Starting security check..."
    
    check_fail2ban
    check_nginx_auth
    check_ssh_auth
    check_suspicious_patterns
    
    # Calculate total incidents
    local total_incidents=$((NGINX_AUTH_FAILURES + SSH_AUTH_FAILURES + SUSPICIOUS_REQUESTS))
    
    # Check if alert threshold exceeded
    if [[ $total_incidents -gt $ALERT_THRESHOLD ]]; then
        local alert_body=$(generate_summary)
        send_alert "[n8n Security Alert] High incident count: $total_incidents" "$alert_body"
    fi
    
    # Check if fail2ban is down
    if ! systemctl is-active fail2ban &>/dev/null; then
        send_alert "[n8n Security Alert] fail2ban is down!" "fail2ban service is not running. Please investigate immediately."
    fi
    
    log_monitor "Security check completed. Total incidents: $total_incidents"
}

# Handle command line arguments
case "${1:-}" in
    --summary)
        generate_summary
        ;;
    --status)
        check_fail2ban
        echo "Banned IPs: $BANNED_IPS"
        fail2ban-client status 2>/dev/null
        ;;
    --check)
        main
        ;;
    *)
        main
        ;;
esac
MONITOR_SCRIPT

    chmod +x "$monitor_script"
    log_info "Security monitoring script created: $monitor_script"
    
    return 0
}

# ==============================================================================
# Security Monitoring Systemd Service
# ==============================================================================

create_security_monitor_service() {
    log_info "Creating security monitoring systemd service..."
    
    # Create systemd service
    cat > /etc/systemd/system/n8n-security-monitor.service << EOF
[Unit]
Description=n8n Security Monitor
After=network.target fail2ban.service nginx.service

[Service]
Type=oneshot
ExecStart=${SECURITY_SCRIPTS_DIR}/security_monitor.sh --check
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer
    cat > /etc/systemd/system/n8n-security-monitor.timer << EOF
[Unit]
Description=n8n Security Monitor Timer

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable and start timer
    execute_silently "systemctl daemon-reload"
    execute_silently "systemctl enable n8n-security-monitor.timer"
    execute_silently "systemctl start n8n-security-monitor.timer"
    
    log_info "Security monitoring service and timer created"
    return 0
}

# ==============================================================================
# Security Report Generation
# ==============================================================================

create_security_report_script() {
    log_info "Creating security report script..."
    
    local report_script="${SECURITY_SCRIPTS_DIR}/security_report.sh"
    
    cat > "$report_script" << 'REPORT_SCRIPT'
#!/bin/bash

# ==============================================================================
# Security Report Script for n8n Server - Milestone 9
# ==============================================================================

EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-root@localhost}"
EMAIL_SENDER="${EMAIL_SENDER:-security@localhost}"
EMAIL_SUBJECT_PREFIX="${EMAIL_SUBJECT_PREFIX:-[n8n]}"

generate_daily_report() {
    local report="
================================================================================
n8n Server Daily Security Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')
================================================================================

=== SYSTEM STATUS ===
Uptime: $(uptime)
Load Average: $(cat /proc/loadavg)

=== FAIL2BAN STATUS ===
$(fail2ban-client status 2>/dev/null || echo 'Not running')

=== BANNED IPs (Last 24h) ===
$(grep -h "Ban " /var/log/fail2ban.log 2>/dev/null | grep "$(date '+%Y-%m-%d')" | wc -l) new bans today

Top banned IPs:
$(grep -h "Ban " /var/log/fail2ban.log 2>/dev/null | awk '{print $NF}' | sort | uniq -c | sort -rn | head -10)

=== NGINX ACCESS SUMMARY ===
Total requests: $(wc -l < /var/log/nginx/n8n_access.log 2>/dev/null || echo 'N/A')
4xx errors: $(grep -c ' 4[0-9][0-9] ' /var/log/nginx/n8n_access.log 2>/dev/null || echo '0')
5xx errors: $(grep -c ' 5[0-9][0-9] ' /var/log/nginx/n8n_access.log 2>/dev/null || echo '0')

=== SSH ACTIVITY ===
Failed logins: $(grep -c 'Failed password' /var/log/auth.log 2>/dev/null || echo '0')
Successful logins: $(grep -c 'Accepted' /var/log/auth.log 2>/dev/null || echo '0')

=== SECURITY EVENTS ===
$(tail -50 /var/log/n8n_security.log 2>/dev/null || echo 'No security log entries')

================================================================================
End of Report
================================================================================
"
    echo "$report"
}

send_report() {
    local report=$(generate_daily_report)
    local subject="${EMAIL_SUBJECT_PREFIX} Daily Security Report - $(date '+%Y-%m-%d')"
    
    if command -v mail &>/dev/null; then
        echo "$report" | mail -s "$subject" -r "$EMAIL_SENDER" "$EMAIL_RECIPIENT"
    elif command -v sendmail &>/dev/null; then
        {
            echo "From: $EMAIL_SENDER"
            echo "To: $EMAIL_RECIPIENT"
            echo "Subject: $subject"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo "$report"
        } | sendmail -t
    else
        echo "Cannot send report - no mail tool available"
        echo "$report"
    fi
}

case "${1:-}" in
    --send)
        send_report
        ;;
    *)
        generate_daily_report
        ;;
esac
REPORT_SCRIPT

    chmod +x "$report_script"
    log_info "Security report script created: $report_script"
    
    # Create daily report cron job
    local cron_entry="${SECURITY_REPORT_SCHEDULE} root ${report_script} --send"
    echo "$cron_entry" > /etc/cron.d/n8n-security-report
    
    log_info "Daily security report cron job created"
    return 0
}

# ==============================================================================
# IP Whitelist Management
# ==============================================================================

setup_ip_whitelist() {
    log_info "Setting up IP whitelist..."
    
    local whitelist_script="${SECURITY_SCRIPTS_DIR}/manage_whitelist.sh"
    
    cat > "$whitelist_script" << 'WHITELIST_SCRIPT'
#!/bin/bash

# ==============================================================================
# IP Whitelist Management for n8n Server - Milestone 9
# ==============================================================================

WHITELIST_FILE="/etc/n8n/security_whitelist.txt"
FAIL2BAN_JAIL_LOCAL="/etc/fail2ban/jail.local"

ensure_whitelist_file() {
    mkdir -p /etc/n8n
    touch "$WHITELIST_FILE"
}

add_ip() {
    local ip="$1"
    ensure_whitelist_file
    
    if grep -q "^${ip}$" "$WHITELIST_FILE" 2>/dev/null; then
        echo "IP $ip is already whitelisted"
        return 0
    fi
    
    echo "$ip" >> "$WHITELIST_FILE"
    echo "Added $ip to whitelist"
    
    update_fail2ban_whitelist
}

remove_ip() {
    local ip="$1"
    ensure_whitelist_file
    
    if grep -q "^${ip}$" "$WHITELIST_FILE" 2>/dev/null; then
        sed -i "/^${ip}$/d" "$WHITELIST_FILE"
        echo "Removed $ip from whitelist"
        update_fail2ban_whitelist
    else
        echo "IP $ip is not in whitelist"
    fi
}

list_ips() {
    ensure_whitelist_file
    echo "Whitelisted IPs:"
    cat "$WHITELIST_FILE"
}

update_fail2ban_whitelist() {
    local ips=$(tr '\n' ' ' < "$WHITELIST_FILE" 2>/dev/null)
    
    if [[ -f "$FAIL2BAN_JAIL_LOCAL" ]]; then
        # Update ignoreip in jail.local
        sed -i "s/^ignoreip = .*/ignoreip = 127.0.0.1\/8 ::1 $ips/" "$FAIL2BAN_JAIL_LOCAL"
        systemctl reload fail2ban 2>/dev/null
        echo "Updated fail2ban whitelist"
    fi
}

case "${1:-}" in
    add)
        add_ip "$2"
        ;;
    remove)
        remove_ip "$2"
        ;;
    list)
        list_ips
        ;;
    *)
        echo "Usage: $0 {add|remove|list} [IP]"
        exit 1
        ;;
esac
WHITELIST_SCRIPT

    chmod +x "$whitelist_script"
    
    # Initialize whitelist with configured IPs
    mkdir -p /etc/n8n
    if [[ -n "$SECURITY_WHITELIST_IPS" ]]; then
        echo "$SECURITY_WHITELIST_IPS" | tr ',' '\n' > /etc/n8n/security_whitelist.txt
        log_info "Initialized whitelist with: $SECURITY_WHITELIST_IPS"
    fi
    
    log_info "IP whitelist management script created: $whitelist_script"
    return 0
}

# ==============================================================================
# Main Setup Function
# ==============================================================================

setup_security() {
    log_info "Starting security configuration..."
    
    # Check if security is enabled
    if [[ "${SECURITY_ENABLED,,}" != "true" ]]; then
        log_info "Security features are disabled (SECURITY_ENABLED=false)"
        return 0
    fi
    
    # Create log file
    mkdir -p "$(dirname "$SECURITY_LOG_FILE")"
    touch "$SECURITY_LOG_FILE"
    
    # Create scripts directory
    mkdir -p "$SECURITY_SCRIPTS_DIR"
    
    # Setup fail2ban
    if [[ "${FAIL2BAN_ENABLED,,}" == "true" ]]; then
        log_info "Setting up fail2ban protection..."
        install_fail2ban || log_warn "fail2ban installation had issues"
        configure_fail2ban_base || log_warn "fail2ban base config had issues"
        configure_fail2ban_ssh || log_warn "fail2ban SSH config had issues"
        configure_fail2ban_nginx || log_warn "fail2ban Nginx config had issues"
        configure_fail2ban_api || log_warn "fail2ban API config had issues"
        start_fail2ban || log_warn "fail2ban start had issues"
    else
        log_info "fail2ban is disabled (FAIL2BAN_ENABLED=false)"
    fi
    
    # Setup Nginx security enhancements
    log_info "Setting up Nginx security enhancements..."
    create_nginx_security_config || log_warn "Nginx security config had issues"
    create_nginx_bad_user_agents_config || log_warn "Bad user agents config had issues"
    create_nginx_rate_limit_zones || log_warn "Rate limit zones config had issues"
    update_nginx_n8n_config_security || log_warn "n8n Nginx security update had issues"
    reload_nginx || log_warn "Nginx reload had issues"
    
    # Setup security monitoring
    log_info "Setting up security monitoring..."
    create_security_monitor_script || log_warn "Security monitor script had issues"
    create_security_monitor_service || log_warn "Security monitor service had issues"
    create_security_report_script || log_warn "Security report script had issues"
    
    # Setup IP whitelist management
    setup_ip_whitelist || log_warn "IP whitelist setup had issues"
    
    log_info "Security configuration completed!"
    log_info "Security log: $SECURITY_LOG_FILE"
    log_info "Security scripts: $SECURITY_SCRIPTS_DIR"
    
    return 0
}

# Export functions for use by other scripts
export -f setup_security

# Run setup if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_security "$@"
fi
