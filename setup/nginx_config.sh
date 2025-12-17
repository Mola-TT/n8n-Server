#!/bin/bash

# ==============================================================================
# Nginx Configuration Script for n8n Server - Milestone 3
# ==============================================================================
# This script sets up Nginx as a secure reverse proxy for n8n server
# including SSL configuration, firewall rules, and security features
# ==============================================================================

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# ==============================================================================
# Nginx Installation Functions
# ==============================================================================

install_nginx() {
    log_info "Installing Nginx web server..."
    
    # Check if Nginx is already installed
    if command -v nginx &> /dev/null; then
        local nginx_version=$(nginx -v 2>&1 | cut -d' ' -f3 | cut -d'/' -f2)
        log_info "Nginx is already installed: version $nginx_version"
        return 0
    fi
    
    # Update package index
    if ! execute_silently "apt-get update"; then
        log_error "Failed to update package index"
        return 1
    fi
    
    # Install Nginx
    log_info "Installing Nginx package..."
    if ! execute_silently "apt-get install -y nginx"; then
        log_error "Failed to install Nginx"
        return 1
    fi
    
    # Verify installation
    if nginx -v &>/dev/null; then
        local nginx_version=$(nginx -v 2>&1 | cut -d' ' -f3 | cut -d'/' -f2)
        log_info "Nginx installed successfully: version $nginx_version"
    else
        log_error "Nginx installation verification failed"
        return 1
    fi
    
    # Enable and start Nginx service
    if execute_silently "systemctl enable nginx"; then
        log_info "Nginx service enabled for auto-start"
    else
        log_warn "Failed to enable Nginx service"
    fi
    
    if execute_silently "systemctl start nginx"; then
        log_info "Nginx service started successfully"
    else
        log_warn "Failed to start Nginx service"
    fi
    
    return 0
}

install_certbot() {
    log_info "Installing Certbot for Let's Encrypt SSL certificates..."
    
    # Check if certbot is already installed
    if command -v certbot &> /dev/null; then
        local certbot_version=$(certbot --version 2>&1 | cut -d' ' -f2)
        log_info "Certbot is already installed: version $certbot_version"
        return 0
    fi
    
    # Install snapd if not present (required for certbot)
    if ! command -v snap &> /dev/null; then
        log_info "Installing snapd..."
        if ! execute_silently "apt-get install -y snapd"; then
            log_error "Failed to install snapd"
            return 1
        fi
    fi
    
    # Install certbot via snap (recommended method)
    log_info "Installing Certbot via snap..."
    if execute_silently "snap install core; snap refresh core"; then
        if execute_silently "snap install --classic certbot"; then
            # Create symlink for easy access
            execute_silently "ln -sf /snap/bin/certbot /usr/bin/certbot"
            log_info "Certbot installed successfully"
        else
            log_warn "Failed to install Certbot via snap, trying apt..."
            # Fallback to apt installation
            if execute_silently "apt-get install -y certbot python3-certbot-nginx"; then
                log_info "Certbot installed via apt"
            else
                log_error "Failed to install Certbot"
                return 1
            fi
        fi
    else
        log_warn "Snap installation failed, trying apt..."
        if execute_silently "apt-get install -y certbot python3-certbot-nginx"; then
            log_info "Certbot installed via apt"
        else
            log_error "Failed to install Certbot"
            return 1
        fi
    fi
    
    return 0
}

# ==============================================================================
# SSL Certificate Functions
# ==============================================================================

generate_self_signed_nginx_certificate() {
    log_info "Generating self-signed SSL certificate for Nginx (development mode)..."
    
    local ssl_dir="/etc/nginx/ssl"
    local private_key="$ssl_dir/private.key"
    local certificate="$ssl_dir/certificate.crt"
    
    # Create SSL directory
    if ! execute_silently "mkdir -p '$ssl_dir'"; then
        log_error "Failed to create Nginx SSL directory"
        return 1
    fi
    
    # Generate private key
    if execute_silently "openssl genrsa -out '$private_key' 2048"; then
        log_info "Generated Nginx private key: $private_key"
    else
        log_error "Failed to generate Nginx private key"
        return 1
    fi
    
    # Generate self-signed certificate
    local subject="/C=US/ST=Development/L=Development/O=n8n-nginx/OU=IT/CN=${NGINX_SERVER_NAME:-localhost}"
    if execute_silently "openssl req -new -x509 -key '$private_key' -out '$certificate' -days 365 -subj '$subject'"; then
        log_info "Generated Nginx self-signed certificate: $certificate"
    else
        log_error "Failed to generate Nginx self-signed certificate"
        return 1
    fi
    
    # Set proper permissions
    execute_silently "chmod 600 '$private_key'"
    execute_silently "chmod 644 '$certificate'"
    execute_silently "chown -R root:root '$ssl_dir'"
    
    log_info "Nginx SSL certificate generated successfully"
    
    # Create placeholder SSL renewal script for future implementation
    create_ssl_renewal_placeholder
    
    return 0
}

setup_letsencrypt_certificate() {
    log_info "Setting up Let's Encrypt SSL certificate for production..."
    
    local domain="${NGINX_SERVER_NAME:-localhost}"
    
    if [[ "$domain" == "localhost" || "$domain" == "your-domain.com" ]]; then
        log_error "Please set a valid domain name in NGINX_SERVER_NAME for Let's Encrypt"
        log_error "Using self-signed certificate instead..."
        generate_self_signed_nginx_certificate
        return 0
    fi
    
    # Install certbot if not present
    install_certbot || return 1
    
    # Stop Nginx temporarily for standalone certificate generation
    log_info "Stopping Nginx temporarily for certificate generation..."
    execute_silently "systemctl stop nginx"
    
    # Generate certificate
    log_info "Generating Let's Encrypt certificate for domain: $domain"
    if execute_silently "certbot certonly --standalone -d $domain --non-interactive --agree-tos --email admin@$domain"; then
        log_info "Let's Encrypt certificate generated successfully"
        
        # Copy certificates to Nginx location
        local ssl_dir="/etc/nginx/ssl"
        execute_silently "mkdir -p '$ssl_dir'"
        
        if execute_silently "cp /etc/letsencrypt/live/$domain/privkey.pem $ssl_dir/private.key" && \
           execute_silently "cp /etc/letsencrypt/live/$domain/fullchain.pem $ssl_dir/certificate.crt"; then
            log_info "Certificates copied to Nginx SSL directory"
            
            # Set proper permissions
            execute_silently "chmod 600 $ssl_dir/private.key"
            execute_silently "chmod 644 $ssl_dir/certificate.crt"
            execute_silently "chown -R root:root '$ssl_dir'"
            
            log_info "SSL certificates configured successfully"
            
            # Create placeholder SSL renewal script for future implementation
            create_ssl_renewal_placeholder
        else
            log_error "Failed to copy certificates"
            return 1
        fi
    else
        log_error "Failed to generate Let's Encrypt certificate"
        log_info "Falling back to self-signed certificate..."
        generate_self_signed_nginx_certificate
    fi
    
    # Restart Nginx
    execute_silently "systemctl start nginx"
    
    return 0
}

create_ssl_renewal_placeholder() {
    log_info "Creating SSL renewal script placeholder..."
    
    local renewal_script="/opt/n8n/scripts/ssl-renew.sh"
    cat > "$renewal_script" << 'EOF'
#!/bin/bash

# SSL Certificate Renewal Script - Placeholder
# This is a placeholder script for future SSL auto-renewal implementation
# SSL auto-renewal will be implemented in a later milestone

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log "SSL Certificate Renewal - Not Implemented Yet"
log "This is a placeholder script for future implementation"
log "SSL auto-renewal will be added in a later milestone"
log "For now, SSL certificates need to be renewed manually"

exit 0
EOF

    chmod +x "$renewal_script"
    log_info "SSL renewal placeholder script created: $renewal_script"
    
    return 0
}

configure_ssl_certificates() {
    log_info "Configuring SSL certificates for Nginx..."
    
    # Load environment to check PRODUCTION setting
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    if [[ -f "$script_dir/../conf/user.env" ]]; then
        source "$script_dir/../conf/user.env"
    else
        source "$script_dir/../conf/default.env"
    fi
    
    if [[ "${PRODUCTION,,}" == "true" ]]; then
        log_info "Production mode detected - setting up Let's Encrypt SSL"
        setup_letsencrypt_certificate
    else
        log_info "Development mode detected - generating self-signed certificate"
        generate_self_signed_nginx_certificate
    fi
    
    return 0
}

# ==============================================================================
# Nginx Configuration Functions
# ==============================================================================

create_nginx_configuration() {
    log_info "Creating Nginx configuration for n8n with multi-user and iframe support..."
    
    # Load environment variables
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    if [[ -f "$script_dir/../conf/user.env" ]]; then
        source "$script_dir/../conf/user.env"
    else
        source "$script_dir/../conf/default.env"
    fi
    # Derive WEBAPP_* URLs from WEBAPP_SERVER_IP if not set
    derive_webapp_urls "http"
    
    local config_file="/etc/nginx/sites-available/n8n"
    
    # Remove default Nginx site
    if [[ -f "/etc/nginx/sites-enabled/default" ]]; then
        execute_silently "rm -f /etc/nginx/sites-enabled/default"
        log_info "Removed default Nginx site"
    fi
    
    # Create multi-user nginx configuration
    create_multiuser_nginx_config "$config_file"
}

create_multiuser_nginx_config() {
    local config_file="$1"
    
    # Build CSP frame-ancestors based on PRODUCTION flag
    local cors_primary="${WEBAPP_DOMAIN:-https://app.example.com}"
    local cors_secondary="${WEBAPP_DOMAIN_ALT:-https://webapp.example.com}"
    local csp_frame_base="'self' ${cors_primary} ${cors_secondary}"
    if [[ "${PRODUCTION:-false}" == "false" ]]; then
        # Development mode: include localhost domains
        local csp_frame_dev="${CSP_FRAME_ANCESTORS_DEV:-http://localhost:3000 http://localhost:8080 http://127.0.0.1:3000 http://host.docker.internal:3000}"
        local csp_frame_full="$csp_frame_base $csp_frame_dev"
        log_info "Development mode: Adding localhost domains to CSP frame-ancestors"
    else
        # Production mode: only production domains
        local csp_frame_full="$csp_frame_base"
        log_info "Production mode: Using production-only CSP frame-ancestors"
    fi
    
    # Create n8n site configuration with multi-user and iframe support
    cat > "$config_file" << EOF
# Nginx configuration for n8n - Milestone 7 Multi-User
# Generated automatically by nginx_config.sh with multi-user and iframe support

# Rate limiting zones (configurable via environment)
# NGINX_RATE_LIMIT_GLOBAL: requests per second for general access (default: 50r/s)
# NGINX_RATE_LIMIT_USER: requests per second per user (default: 100r/s)
limit_req_zone \$binary_remote_addr zone=n8n_limit:10m rate=${NGINX_RATE_LIMIT_GLOBAL:-50r/s};
limit_req_zone \$http_x_user_id zone=user_limit:10m rate=${NGINX_RATE_LIMIT_USER:-100r/s};

# Map for user routing
map \$request_uri \$user_id {
    ~^/user/(?<id>[^/]+) \$id;
    default "";
}

# Map for iframe embedding - default allows embedding (CSP frame-ancestors handles security)
map \$http_x_frame_options \$iframe_allowed {
    default "";
    "DENY" "DENY";
    "SAMEORIGIN" "SAMEORIGIN";
}

# Custom log format for user tracking
log_format user_access '\$remote_addr - \$user_id [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

# Upstream for load balancing (can be extended for multiple instances)
upstream n8n_backend {
    server localhost:5678;
    keepalive 32;
}

# HTTP server block (redirects to HTTPS)
server {
    listen ${NGINX_HTTP_PORT:-80};
    server_name ${NGINX_SERVER_NAME:-localhost};
    
    # Security headers for HTTP (iframe-friendly)
    add_header X-Frame-Options \$iframe_allowed always;
    add_header X-Content-Type-Options nosniff always;
    
    # Redirect all HTTP traffic to HTTPS
    return 301 https://\$host\$request_uri;
}

# HTTPS server block (main configuration)
server {
    listen ${NGINX_HTTPS_PORT:-443} ssl http2;
    server_name ${NGINX_SERVER_NAME:-localhost};
    
    # SSL Configuration
    ssl_certificate ${NGINX_SSL_CERT_PATH:-/etc/nginx/ssl/certificate.crt};
    ssl_certificate_key ${NGINX_SSL_KEY_PATH:-/etc/nginx/ssl/private.key};
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security Headers (iframe-friendly)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options \$iframe_allowed always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Content Security Policy tailored for iframe embedding
    set \$csp_default "default-src 'self'";
    set \$csp_script "script-src 'self' 'unsafe-inline' 'unsafe-eval'";
    set \$csp_style "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com";
    set \$csp_img "img-src 'self' data: https:";
    set \$csp_font "font-src 'self' https://fonts.gstatic.com";
    set \$csp_connect "connect-src 'self' wss: https: ${cors_primary} ${cors_secondary}";
    set \$csp_frame_ancestors "frame-ancestors ${csp_frame_full}";
    add_header Content-Security-Policy "\$csp_default; \$csp_script; \$csp_style; \$csp_img; \$csp_font; \$csp_connect; \$csp_frame_ancestors;" always;

    # CORS headers for embedded web app
    set \$cors_origin "${cors_primary}";
    if (\$http_origin = "${cors_secondary}") { set \$cors_origin "\$http_origin"; }
    if (\$http_origin = "${cors_primary}") { set \$cors_origin "\$http_origin"; }
    add_header Access-Control-Allow-Origin \$cors_origin always;
    add_header Access-Control-Allow-Credentials "true" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Max-Age "86400" always;

    if (\$request_method = OPTIONS) {
        return 204;
    }
    
    # Rate limiting (general and per-user)
    # Burst allows initial page load with many assets (~150 files)
    limit_req zone=n8n_limit burst=${NGINX_RATE_BURST_GLOBAL:-200} nodelay;
    limit_req zone=user_limit burst=${NGINX_RATE_BURST_USER:-300} nodelay;
    
    # Client settings
    client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE:-100M};
    
    # Proxy settings
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    
    # Multi-user headers
    proxy_set_header X-User-ID \$user_id;
    proxy_set_header X-Original-URI \$request_uri;
    proxy_set_header X-Iframe-Allowed \$iframe_allowed;
    
    # Timeout settings
    proxy_connect_timeout ${NGINX_PROXY_TIMEOUT:-300s};
    proxy_send_timeout ${NGINX_PROXY_TIMEOUT:-300s};
    proxy_read_timeout ${NGINX_PROXY_TIMEOUT:-300s};
    send_timeout ${NGINX_PROXY_TIMEOUT:-300s};
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # User-specific routing
    location ~ ^/user/([^/]+)/(.*) {
        set \$requested_user \$1;
        set \$path \$2;
        
        # Add user context headers
        proxy_set_header X-User-ID \$requested_user;
        proxy_set_header X-User-Path /\$path;
        
        # Per-user rate limiting
        limit_req zone=user_limit burst=${NGINX_RATE_BURST_USER:-300} nodelay;
        
        proxy_pass http://n8n_backend/\$path\$is_args\$args;
        
        # Additional proxy settings
        proxy_buffering off;
        proxy_cache off;
        proxy_redirect off;
    }
    
    # API endpoints for user management
    location /api/user/ {
        # API rate limiting (more restrictive for API calls)
        limit_req zone=n8n_limit burst=${NGINX_RATE_BURST_API:-50} nodelay;
        
        # Add API headers
        proxy_set_header X-API-Request "true";
        
        proxy_pass http://n8n_backend;
        
        proxy_buffering off;
        proxy_cache off;
        proxy_redirect off;
    }
    
    # Main location block (for non-user-specific access)
    location / {
        proxy_pass http://n8n_backend;
        
        # Additional proxy settings
        proxy_buffering off;
        proxy_cache off;
        proxy_redirect off;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # User metrics endpoint
    location /metrics/user/ {
        # Restrict access to monitoring
        allow 127.0.0.1;
        allow ::1;
        deny all;
        
        proxy_pass http://n8n_backend;
        proxy_buffering off;
        proxy_cache off;
    }
    
    # Netdata monitoring proxy
    location /netdata/ {
        proxy_pass http://127.0.0.1:19999/;
        proxy_set_header Host 127.0.0.1:19999;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Original-URI \$request_uri;
        
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
        
        # Basic authentication for Netdata
        auth_basic "Netdata Monitoring";
        auth_basic_user_file /etc/nginx/.netdata_auth;
    }
    
    # Security: Block access to sensitive files
    location ~ /\\.ht {
        deny all;
    }
    
    location ~ /\\.(env|git|svn) {
        deny all;
    }
    
    # Security: Block direct access to user directories
    location ~ ^/opt/n8n/users/ {
        deny all;
    }
    
    # Logging with user context
    access_log ${NGINX_ACCESS_LOG:-/var/log/nginx/n8n_access.log} user_access;
    error_log ${NGINX_ERROR_LOG:-/var/log/nginx/n8n_error.log};
}
EOF

    if [[ -f "$config_file" ]]; then
        log_info "Multi-user Nginx configuration created: $config_file"
        
        # Enable the site
        if execute_silently "ln -sf $config_file /etc/nginx/sites-enabled/n8n"; then
            log_info "Nginx site enabled"
        else
            log_error "Failed to enable Nginx site"
            return 1
        fi
        
        # Test configuration
        if execute_silently "nginx -t"; then
            log_info "Nginx configuration test passed"
        else
            log_error "Nginx configuration test failed"
            return 1
        fi
        
        return 0
    else
        log_error "Failed to create Nginx configuration"
        return 1
    fi
}

# ==============================================================================
# Firewall Configuration Functions
# ==============================================================================

configure_nginx_firewall() {
    log_info "Configuring firewall rules for Nginx..."
    
    # Check if UFW is available
    if ! command -v ufw &> /dev/null; then
        log_info "Installing UFW (Uncomplicated Firewall)..."
        if ! execute_silently "apt-get install -y ufw"; then
            log_error "Failed to install UFW"
            return 1
        fi
    fi
    
    # Configure UFW rules for Nginx
    log_info "Setting up firewall rules..."
    
    # Allow SSH (important to maintain access)
    execute_silently "ufw allow ssh"
    
    # Allow HTTP and HTTPS
    execute_silently "ufw allow ${NGINX_HTTP_PORT:-80}/tcp"
    execute_silently "ufw allow ${NGINX_HTTPS_PORT:-443}/tcp"
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        log_info "Enabling UFW firewall..."
        execute_silently "ufw --force enable"
    fi
    
    # Show firewall status
    log_info "Firewall configuration completed"
    
    # Summarize firewall status
    if ufw status | grep -q "Status: active"; then
        log_info "UFW firewall is active"
        
        # Count and log allowed services
        local ssh_allowed=$(ufw status | grep -c "22/tcp.*ALLOW" || echo "0")
        local http_allowed=$(ufw status | grep -c "80/tcp.*ALLOW" || echo "0")
        local https_allowed=$(ufw status | grep -c "443/tcp.*ALLOW" || echo "0")
        
        log_info "Firewall rules: SSH ($ssh_allowed), HTTP ($http_allowed), HTTPS ($https_allowed)"
    else
        log_warn "UFW firewall is not active"
    fi
    
    return 0
}

# ==============================================================================
# Service Management Functions
# ==============================================================================

restart_nginx_service() {
    log_info "Restarting Nginx service..."
    
    # Reload Nginx configuration
    if execute_silently "systemctl reload nginx"; then
        log_info "Nginx configuration reloaded successfully"
    else
        log_warn "Failed to reload Nginx, attempting restart..."
        if execute_silently "systemctl restart nginx"; then
            log_info "Nginx service restarted successfully"
        else
            log_error "Failed to restart Nginx service"
            return 1
        fi
    fi
    
    # Verify service status
    if systemctl is-active nginx &>/dev/null; then
        log_info "Nginx service is running"
        
        # Check if Nginx is listening on configured ports
        local http_port="${NGINX_HTTP_PORT:-80}"
        local https_port="${NGINX_HTTPS_PORT:-443}"
        
        if netstat -tlnp 2>/dev/null | grep -q ":$http_port "; then
            log_info "Nginx is listening on port $http_port (HTTP)"
        fi
        
        if netstat -tlnp 2>/dev/null | grep -q ":$https_port "; then
            log_info "Nginx is listening on port $https_port (HTTPS)"
        fi
    else
        log_error "Nginx service is not running"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Main Setup Function
# ==============================================================================

setup_nginx_infrastructure() {
    log_info "Starting Nginx infrastructure setup..."
    
    # Check if Nginx is enabled
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    if [[ -f "$script_dir/../conf/user.env" ]]; then
        source "$script_dir/../conf/user.env"
    else
        source "$script_dir/../conf/default.env"
    fi
    
    if [[ "${NGINX_ENABLED,,}" != "true" ]]; then
        log_info "Nginx is disabled in configuration (NGINX_ENABLED=false)"
        return 0
    fi
    
    # Install Nginx
    install_nginx || return 1
    
    # Configure SSL certificates
    configure_ssl_certificates || return 1
    
    # Create Nginx configuration
    create_nginx_configuration || return 1
    
    # Configure firewall
    if [[ "${CONFIGURE_FIREWALL,,}" == "true" ]]; then
        configure_nginx_firewall || return 1
    else
        log_info "Firewall configuration skipped (CONFIGURE_FIREWALL=false)"
    fi
    
    # Restart Nginx service
    restart_nginx_service || return 1
    
    log_info "Nginx infrastructure setup completed successfully!"
    log_info "Nginx is now configured as a secure reverse proxy for n8n"
    log_info "Access n8n at: https://${NGINX_SERVER_NAME:-localhost}"
    
    return 0
} 