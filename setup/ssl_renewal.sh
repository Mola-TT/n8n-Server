#!/bin/bash

# =============================================================================
# SSL Certificate Renewal Script for n8n Server - Milestone 5
# =============================================================================
# This script manages SSL certificate renewal for both production and development
# environments, handling Let's Encrypt certificates and self-signed certificates
# =============================================================================

# Source required libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/utilities.sh"

# =============================================================================
# Configuration and Constants
# =============================================================================

# SSL certificate paths
SSL_CERT_DIR="/etc/nginx/ssl"
SSL_CERT_PATH="$SSL_CERT_DIR/certificate.crt"
SSL_KEY_PATH="$SSL_CERT_DIR/private.key"
SSL_BACKUP_DIR="/opt/n8n/ssl/backups"
SSL_LOG_FILE="/var/log/ssl_renewal.log"

# Let's Encrypt paths
LETSENCRYPT_DIR="/etc/letsencrypt"
LETSENCRYPT_LIVE_DIR="$LETSENCRYPT_DIR/live"
LETSENCRYPT_LOG_FILE="/var/log/letsencrypt/letsencrypt.log"

# Renewal configuration
RENEWAL_LOCK_FILE="/var/lock/ssl_renewal.lock"
RENEWAL_SUCCESS_FILE="/var/log/ssl_renewal_last_success"

# =============================================================================
# Utility Functions
# =============================================================================

log_ssl() {
    local level="$1"
    shift
    local message="$*"
    
    # Log to both main logger and SSL-specific log
    case "$level" in
        "INFO")
            log_info "$message"
            ;;
        "WARN")
            log_warn "$message"
            ;;
        "ERROR")
            log_error "$message"
            ;;
        "DEBUG")
            log_debug "$message"
            ;;
    esac
    
    # Also log to SSL-specific log file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$SSL_LOG_FILE"
}

create_lock_file() {
    if [ -f "$RENEWAL_LOCK_FILE" ]; then
        local lock_pid=$(cat "$RENEWAL_LOCK_FILE" 2>/dev/null)
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log_ssl "ERROR" "SSL renewal already in progress (PID: $lock_pid)"
            return 1
        else
            log_ssl "WARN" "Removing stale lock file"
            rm -f "$RENEWAL_LOCK_FILE"
        fi
    fi
    
    echo $$ > "$RENEWAL_LOCK_FILE"
    log_ssl "DEBUG" "Created lock file with PID: $$"
    return 0
}

remove_lock_file() {
    if [ -f "$RENEWAL_LOCK_FILE" ]; then
        rm -f "$RENEWAL_LOCK_FILE"
        log_ssl "DEBUG" "Removed lock file"
    fi
}

backup_certificates() {
    log_ssl "INFO" "Creating certificate backup..."
    
    # Create backup directory
    sudo mkdir -p "$SSL_BACKUP_DIR"
    
    # Create timestamped backup
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_dir="$SSL_BACKUP_DIR/backup_$backup_timestamp"
    
    if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
        sudo mkdir -p "$backup_dir"
        sudo cp "$SSL_CERT_PATH" "$backup_dir/certificate.crt"
        sudo cp "$SSL_KEY_PATH" "$backup_dir/private.key"
        
        log_ssl "INFO" "Certificates backed up to: $backup_dir"
        
        # Keep only last 10 backups
        local backup_count=$(ls -1 "$SSL_BACKUP_DIR" | grep "^backup_" | wc -l)
        if [ "$backup_count" -gt 10 ]; then
            local old_backups=$(ls -1t "$SSL_BACKUP_DIR" | grep "^backup_" | tail -n +11)
            for old_backup in $old_backups; do
                sudo rm -rf "$SSL_BACKUP_DIR/$old_backup"
                log_ssl "DEBUG" "Removed old backup: $old_backup"
            done
        fi
        
        return 0
    else
        log_ssl "WARN" "No existing certificates to backup"
        return 1
    fi
}

validate_certificate() {
    local cert_path="$1"
    local key_path="$2"
    
    if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
        log_ssl "ERROR" "Certificate files not found: $cert_path, $key_path"
        return 1
    fi
    
    # Check certificate validity
    local cert_info=$(openssl x509 -in "$cert_path" -noout -dates 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_ssl "ERROR" "Invalid certificate format: $cert_path"
        return 1
    fi
    
    # Check if certificate and key match
    local cert_modulus=$(openssl x509 -noout -modulus -in "$cert_path" 2>/dev/null | openssl md5)
    local key_modulus=$(openssl rsa -noout -modulus -in "$key_path" 2>/dev/null | openssl md5)
    
    if [ "$cert_modulus" != "$key_modulus" ]; then
        log_ssl "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    # Check expiration
    local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log_ssl "INFO" "Certificate expires in $days_until_expiry days ($expiry_date)"
    
    if [ "$days_until_expiry" -lt 0 ]; then
        log_ssl "ERROR" "Certificate has already expired"
        return 1
    elif [ "$days_until_expiry" -lt 30 ]; then
        log_ssl "WARN" "Certificate expires in less than 30 days"
        return 2
    fi
    
    log_ssl "INFO" "Certificate validation successful"
    return 0
}

# =============================================================================
# Let's Encrypt Functions
# =============================================================================

install_certbot() {
    log_ssl "INFO" "Installing/updating Certbot..."
    
    # Check if certbot is already installed
    if command -v certbot >/dev/null 2>&1; then
        local certbot_version=$(certbot --version 2>&1 | head -1)
        log_ssl "INFO" "Certbot already installed: $certbot_version"
        return 0
    fi
    
    # Install certbot with retry logic
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_ssl "INFO" "Installing Certbot (attempt $attempt/$max_attempts)..."
        
        if execute_silently "sudo apt-get update" && \
           execute_silently "sudo apt-get install -y certbot python3-certbot-nginx"; then
            log_ssl "INFO" "Certbot installed successfully"
            
            # Verify installation
            if command -v certbot >/dev/null 2>&1; then
                local certbot_version=$(certbot --version 2>&1 | head -1)
                log_ssl "INFO" "Certbot verification successful: $certbot_version"
                return 0
            else
                log_ssl "ERROR" "Certbot installation verification failed"
            fi
        else
            log_ssl "WARN" "Certbot installation attempt $attempt failed"
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            log_ssl "INFO" "Waiting 10 seconds before retry..."
            sleep 10
        fi
    done
    
    log_ssl "ERROR" "Failed to install Certbot after $max_attempts attempts"
    return 1
}

obtain_letsencrypt_certificate() {
    local domain="$1"
    local email="$2"
    local staging="${3:-false}"
    
    log_ssl "INFO" "Obtaining Let's Encrypt certificate for domain: $domain"
    
    # Install certbot if needed
    if ! install_certbot; then
        log_ssl "ERROR" "Failed to install Certbot"
        return 1
    fi
    
    # Prepare certbot command
    local certbot_cmd="certbot certonly --nginx"
    certbot_cmd="$certbot_cmd --non-interactive --agree-tos"
    certbot_cmd="$certbot_cmd --email $email"
    certbot_cmd="$certbot_cmd --domains $domain"
    
    # Add staging flag for testing
    if [ "$staging" = "true" ]; then
        certbot_cmd="$certbot_cmd --staging"
        log_ssl "INFO" "Using Let's Encrypt staging environment"
    fi
    
    # Execute certbot
    log_ssl "INFO" "Executing: $certbot_cmd"
    if sudo $certbot_cmd; then
        log_ssl "INFO" "Let's Encrypt certificate obtained successfully"
        
        # Copy certificates to Nginx SSL directory
        local le_cert_path="$LETSENCRYPT_LIVE_DIR/$domain/fullchain.pem"
        local le_key_path="$LETSENCRYPT_LIVE_DIR/$domain/privkey.pem"
        
        if [ -f "$le_cert_path" ] && [ -f "$le_key_path" ]; then
            sudo cp "$le_cert_path" "$SSL_CERT_PATH"
            sudo cp "$le_key_path" "$SSL_KEY_PATH"
            
            # Set proper permissions
            sudo chmod 644 "$SSL_CERT_PATH"
            sudo chmod 600 "$SSL_KEY_PATH"
            sudo chown root:www-data "$SSL_CERT_PATH" "$SSL_KEY_PATH"
            
            log_ssl "INFO" "Certificates copied to Nginx SSL directory"
            return 0
        else
            log_ssl "ERROR" "Let's Encrypt certificate files not found after generation"
            return 1
        fi
    else
        log_ssl "ERROR" "Failed to obtain Let's Encrypt certificate"
        return 1
    fi
}

renew_letsencrypt_certificate() {
    log_ssl "INFO" "Renewing Let's Encrypt certificates..."
    
    # Check if certbot is available
    if ! command -v certbot >/dev/null 2>&1; then
        log_ssl "ERROR" "Certbot not found - cannot renew Let's Encrypt certificates"
        return 1
    fi
    
    # Perform dry run first
    log_ssl "INFO" "Performing renewal dry run..."
    if sudo certbot renew --dry-run --quiet; then
        log_ssl "INFO" "Renewal dry run successful"
    else
        log_ssl "WARN" "Renewal dry run failed - proceeding with caution"
    fi
    
    # Perform actual renewal
    log_ssl "INFO" "Performing certificate renewal..."
    if sudo certbot renew --quiet; then
        log_ssl "INFO" "Certificate renewal completed successfully"
        
        # Update timestamp
        echo "$(date '+%Y-%m-%d %H:%M:%S')" | sudo tee "$RENEWAL_SUCCESS_FILE" >/dev/null
        
        return 0
    else
        log_ssl "ERROR" "Certificate renewal failed"
        return 1
    fi
}

# =============================================================================
# Self-Signed Certificate Functions
# =============================================================================

generate_self_signed_certificate() {
    local domain="$1"
    local days="${2:-365}"
    
    log_ssl "INFO" "Generating self-signed certificate for domain: $domain"
    
    # Create SSL directory
    sudo mkdir -p "$SSL_CERT_DIR"
    
    # Generate private key
    log_ssl "INFO" "Generating private key..."
    if sudo openssl genrsa -out "$SSL_KEY_PATH" 2048; then
        log_ssl "INFO" "Private key generated successfully"
    else
        log_ssl "ERROR" "Failed to generate private key"
        return 1
    fi
    
    # Generate certificate
    log_ssl "INFO" "Generating self-signed certificate..."
    local openssl_cmd="openssl req -new -x509 -key $SSL_KEY_PATH -out $SSL_CERT_PATH -days $days"
    openssl_cmd="$openssl_cmd -subj '/C=US/ST=State/L=City/O=Organization/CN=$domain'"
    
    if sudo $openssl_cmd; then
        log_ssl "INFO" "Self-signed certificate generated successfully"
    else
        log_ssl "ERROR" "Failed to generate self-signed certificate"
        return 1
    fi
    
    # Set proper permissions
    sudo chmod 644 "$SSL_CERT_PATH"
    sudo chmod 600 "$SSL_KEY_PATH"
    sudo chown root:www-data "$SSL_CERT_PATH" "$SSL_KEY_PATH"
    
    log_ssl "INFO" "Certificate permissions set correctly"
    
    # Validate the generated certificate
    if validate_certificate "$SSL_CERT_PATH" "$SSL_KEY_PATH"; then
        log_ssl "INFO" "Self-signed certificate validation successful"
        return 0
    else
        log_ssl "ERROR" "Self-signed certificate validation failed"
        return 1
    fi
}

renew_self_signed_certificate() {
    local domain="$1"
    local days="${2:-365}"
    
    log_ssl "INFO" "Renewing self-signed certificate..."
    
    # Check if renewal is needed
    if validate_certificate "$SSL_CERT_PATH" "$SSL_KEY_PATH"; then
        local validation_result=$?
        if [ $validation_result -eq 0 ]; then
            log_ssl "INFO" "Self-signed certificate is still valid, renewal not needed"
            return 0
        elif [ $validation_result -eq 2 ]; then
            log_ssl "INFO" "Self-signed certificate expires soon, proceeding with renewal"
        fi
    fi
    
    # Backup existing certificates
    backup_certificates
    
    # Generate new certificate
    if generate_self_signed_certificate "$domain" "$days"; then
        log_ssl "INFO" "Self-signed certificate renewed successfully"
        
        # Update timestamp
        echo "$(date '+%Y-%m-%d %H:%M:%S')" | sudo tee "$RENEWAL_SUCCESS_FILE" >/dev/null
        
        return 0
    else
        log_ssl "ERROR" "Failed to renew self-signed certificate"
        return 1
    fi
}

# =============================================================================
# Service Management Functions
# =============================================================================

restart_services() {
    log_ssl "INFO" "Restarting services after certificate renewal..."
    
    local services_restarted=0
    local services_failed=0
    
    # Restart Nginx
    log_ssl "INFO" "Restarting Nginx..."
    if sudo systemctl reload nginx; then
        log_ssl "INFO" "Nginx reloaded successfully"
        services_restarted=$((services_restarted + 1))
    else
        log_ssl "ERROR" "Failed to reload Nginx"
        services_failed=$((services_failed + 1))
        
        # Try full restart if reload fails
        log_ssl "INFO" "Attempting full Nginx restart..."
        if sudo systemctl restart nginx; then
            log_ssl "INFO" "Nginx restarted successfully"
            services_restarted=$((services_restarted + 1))
        else
            log_ssl "ERROR" "Failed to restart Nginx"
        fi
    fi
    
    # Restart Netdata if it exists and is running
    if systemctl is-active netdata >/dev/null 2>&1; then
        log_ssl "INFO" "Restarting Netdata..."
        if sudo systemctl reload netdata; then
            log_ssl "INFO" "Netdata reloaded successfully"
            services_restarted=$((services_restarted + 1))
        else
            log_ssl "WARN" "Failed to reload Netdata, but continuing"
            services_failed=$((services_failed + 1))
        fi
    fi
    
    log_ssl "INFO" "Service restart summary: $services_restarted successful, $services_failed failed"
    
    if [ $services_failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

test_certificate_access() {
    log_ssl "INFO" "Testing certificate accessibility..."
    
    # Test Nginx configuration
    if sudo nginx -t >/dev/null 2>&1; then
        log_ssl "INFO" "Nginx configuration test passed"
    else
        log_ssl "ERROR" "Nginx configuration test failed"
        return 1
    fi
    
    # Test HTTPS connectivity
    local domain="${NGINX_SERVER_NAME:-localhost}"
    local test_url="https://$domain"
    
    log_ssl "INFO" "Testing HTTPS connectivity to: $test_url"
    if curl -k -s --connect-timeout 10 "$test_url" >/dev/null 2>&1; then
        log_ssl "INFO" "HTTPS connectivity test passed"
        return 0
    else
        log_ssl "WARN" "HTTPS connectivity test failed (this may be normal for self-signed certificates)"
        return 1
    fi
}

# =============================================================================
# Main Renewal Functions
# =============================================================================

perform_certificate_renewal() {
    local force_renewal="${1:-false}"
    
    log_ssl "INFO" "Starting SSL certificate renewal process..."
    
    # Create lock file
    if ! create_lock_file; then
        return 1
    fi
    
    # Ensure cleanup on exit
    trap remove_lock_file EXIT
    
    # Load environment variables
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env" ]; then
        set -o allexport
        source "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env"
        set +o allexport
    fi
    
    # Load defaults if user env doesn't exist
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/../conf/default.env" ]; then
        set -o allexport
        source "$(dirname "${BASH_SOURCE[0]}")/../conf/default.env"
        set +o allexport
    fi
    
    local domain="${NGINX_SERVER_NAME:-localhost}"
    local email="${EMAIL_SENDER:-admin@localhost}"
    local production="${PRODUCTION:-false}"
    
    log_ssl "INFO" "Configuration: domain=$domain, production=$production, force=$force_renewal"
    
    # Determine renewal strategy based on production mode
    if [ "$production" = "true" ]; then
        log_ssl "INFO" "Production mode: Using Let's Encrypt certificates"
        
        # Check if Let's Encrypt certificates exist
        local le_cert_path="$LETSENCRYPT_LIVE_DIR/$domain/fullchain.pem"
        if [ -f "$le_cert_path" ]; then
            # Renew existing Let's Encrypt certificate
            if renew_letsencrypt_certificate; then
                log_ssl "INFO" "Let's Encrypt certificate renewal successful"
            else
                log_ssl "ERROR" "Let's Encrypt certificate renewal failed"
                return 1
            fi
        else
            # Obtain new Let's Encrypt certificate
            log_ssl "INFO" "No existing Let's Encrypt certificate found, obtaining new one"
            if obtain_letsencrypt_certificate "$domain" "$email" "false"; then
                log_ssl "INFO" "New Let's Encrypt certificate obtained successfully"
            else
                log_ssl "ERROR" "Failed to obtain new Let's Encrypt certificate"
                return 1
            fi
        fi
    else
        log_ssl "INFO" "Development mode: Using self-signed certificates"
        
        if [ "$force_renewal" = "true" ]; then
            log_ssl "INFO" "Force renewal requested for self-signed certificate"
            if renew_self_signed_certificate "$domain" 365; then
                log_ssl "INFO" "Self-signed certificate renewal successful"
            else
                log_ssl "ERROR" "Self-signed certificate renewal failed"
                return 1
            fi
        else
            # Check if renewal is needed
            if validate_certificate "$SSL_CERT_PATH" "$SSL_KEY_PATH"; then
                local validation_result=$?
                if [ $validation_result -eq 0 ]; then
                    log_ssl "INFO" "Self-signed certificate is valid, no renewal needed"
                elif [ $validation_result -eq 2 ]; then
                    log_ssl "INFO" "Self-signed certificate expires soon, renewing"
                    if renew_self_signed_certificate "$domain" 365; then
                        log_ssl "INFO" "Self-signed certificate renewal successful"
                    else
                        log_ssl "ERROR" "Self-signed certificate renewal failed"
                        return 1
                    fi
                fi
            else
                log_ssl "INFO" "Self-signed certificate validation failed, generating new one"
                if generate_self_signed_certificate "$domain" 365; then
                    log_ssl "INFO" "New self-signed certificate generated successfully"
                else
                    log_ssl "ERROR" "Failed to generate new self-signed certificate"
                    return 1
                fi
            fi
        fi
    fi
    
    # Restart services
    if restart_services; then
        log_ssl "INFO" "Services restarted successfully"
    else
        log_ssl "WARN" "Some services failed to restart"
    fi
    
    # Test certificate access
    test_certificate_access
    
    log_ssl "INFO" "SSL certificate renewal process completed"
    return 0
}

setup_renewal_cron() {
    log_ssl "INFO" "Setting up automatic certificate renewal..."
    
    # Create renewal script in system location
    local renewal_script="/usr/local/bin/ssl-renewal"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    sudo tee "$renewal_script" >/dev/null << EOF
#!/bin/bash
# Automatic SSL certificate renewal script
cd "$script_dir"
./ssl_renewal.sh --renew
EOF
    
    sudo chmod +x "$renewal_script"
    log_ssl "INFO" "Created renewal script: $renewal_script"
    
    # Add cron job for automatic renewal
    local cron_entry="0 2 * * 0 $renewal_script >/dev/null 2>&1"
    
    # Check if cron entry already exists
    if crontab -l 2>/dev/null | grep -q "$renewal_script"; then
        log_ssl "INFO" "Cron job for SSL renewal already exists"
    else
        # Add cron job
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log_ssl "INFO" "Added weekly cron job for SSL certificate renewal"
    fi
    
    return 0
}

# =============================================================================
# Main Script Logic
# =============================================================================

setup_ssl_certificate_management() {
    log_ssl "INFO" "Setting up SSL certificate management..."
    
    # Load environment variables
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env" ]; then
        set -o allexport
        source "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env"
        set +o allexport
    fi
    
    # Load defaults if user env doesn't exist
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/../conf/default.env" ]; then
        set -o allexport
        source "$(dirname "${BASH_SOURCE[0]}")/../conf/default.env"
        set +o allexport
    fi
    
    local domain="${NGINX_SERVER_NAME:-localhost}"
    local email="${EMAIL_SENDER:-admin@localhost}"
    local production="${PRODUCTION:-false}"
    
    log_ssl "INFO" "SSL configuration: domain=$domain, production=$production"
    
    # Create SSL directories
    sudo mkdir -p "$SSL_CERT_DIR"
    sudo mkdir -p "$SSL_BACKUP_DIR"
    
    # Set up initial certificates based on production mode
    if [ "$production" = "true" ]; then
        log_ssl "INFO" "Production mode: Setting up Let's Encrypt certificates"
        
        # Check if Let's Encrypt certificates already exist
        local le_cert_path="$LETSENCRYPT_LIVE_DIR/$domain/fullchain.pem"
        if [ -f "$le_cert_path" ]; then
            log_ssl "INFO" "Existing Let's Encrypt certificates found, copying to Nginx directory"
            local le_key_path="$LETSENCRYPT_LIVE_DIR/$domain/privkey.pem"
            
            sudo cp "$le_cert_path" "$SSL_CERT_PATH"
            sudo cp "$le_key_path" "$SSL_KEY_PATH"
            
            # Set proper permissions
            sudo chmod 644 "$SSL_CERT_PATH"
            sudo chmod 600 "$SSL_KEY_PATH"
            sudo chown root:www-data "$SSL_CERT_PATH" "$SSL_KEY_PATH"
            
            log_ssl "INFO" "Existing Let's Encrypt certificates configured"
        else
            log_ssl "INFO" "No existing Let's Encrypt certificates found"
            log_ssl "INFO" "Generating temporary self-signed certificate for initial setup"
            
            # Generate temporary self-signed certificate for initial setup
            if generate_self_signed_certificate "$domain" 30; then
                log_ssl "INFO" "Temporary self-signed certificate generated"
                log_ssl "INFO" "Run 'setup/ssl_renewal.sh --renew' after DNS is configured to obtain Let's Encrypt certificate"
            else
                log_ssl "ERROR" "Failed to generate temporary certificate"
                return 1
            fi
        fi
    else
        log_ssl "INFO" "Development mode: Setting up self-signed certificates"
        
        # Generate self-signed certificate for development
        if generate_self_signed_certificate "$domain" 365; then
            log_ssl "INFO" "Self-signed certificate generated for development"
        else
            log_ssl "ERROR" "Failed to generate self-signed certificate"
            return 1
        fi
    fi
    
    # Set up automatic renewal
    log_ssl "INFO" "Setting up automatic certificate renewal..."
    if setup_renewal_cron; then
        log_ssl "INFO" "Automatic renewal configured successfully"
    else
        log_ssl "WARN" "Failed to set up automatic renewal, but continuing"
    fi
    
    # Validate certificate setup
    if validate_certificate "$SSL_CERT_PATH" "$SSL_KEY_PATH"; then
        log_ssl "INFO" "Certificate validation successful"
    else
        log_ssl "ERROR" "Certificate validation failed"
        return 1
    fi
    
    # Test certificate access
    test_certificate_access
    
    log_ssl "INFO" "SSL certificate management setup completed"
    return 0
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "SSL Certificate Renewal Script for n8n Server"
    echo ""
    echo "OPTIONS:"
    echo "  --renew              Perform certificate renewal"
    echo "  --force              Force certificate renewal even if not needed"
    echo "  --setup-cron         Setup automatic renewal cron job"
    echo "  --validate           Validate existing certificates"
    echo "  --generate-self      Generate new self-signed certificate"
    echo "  --help               Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 --renew          # Renew certificates if needed"
    echo "  $0 --force          # Force certificate renewal"
    echo "  $0 --validate       # Check certificate validity"
    echo ""
}

main() {
    # Initialize logging
    sudo mkdir -p "$(dirname "$SSL_LOG_FILE")"
    sudo touch "$SSL_LOG_FILE"
    sudo chmod 644 "$SSL_LOG_FILE"
    
    log_ssl "INFO" "SSL Certificate Renewal Script started"
    log_ssl "INFO" "Script version: Milestone 5"
    
    # Parse command line arguments
    case "${1:-}" in
        --renew)
            perform_certificate_renewal false
            ;;
        --force)
            perform_certificate_renewal true
            ;;
        --setup-cron)
            setup_renewal_cron
            ;;
        --validate)
            validate_certificate "$SSL_CERT_PATH" "$SSL_KEY_PATH"
            ;;
        --generate-self)
            # Load environment for domain
            if [ -f "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env" ]; then
                set -o allexport
                source "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env"
                set +o allexport
            fi
            generate_self_signed_certificate "${NGINX_SERVER_NAME:-localhost}" 365
            ;;
        --help|"")
            show_usage
            ;;
        *)
            echo "Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
    
    local exit_code=$?
    log_ssl "INFO" "SSL Certificate Renewal Script completed with exit code: $exit_code"
    
    return $exit_code
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 