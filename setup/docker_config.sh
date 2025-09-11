#!/bin/bash

# =============================================================================
# Docker Configuration Script for n8n Server - Milestone 2
# =============================================================================
# This script sets up the complete Docker infrastructure for n8n server
# including Redis, PostgreSQL integration, and operational maintenance
# =============================================================================

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# =============================================================================
# Repository Management Functions
# =============================================================================

fix_ubuntu_repositories() {
    log_info "Checking Ubuntu repository accessibility..."
    
    # Test current repositories
    if apt-get update >/dev/null 2>&1; then
        log_info "Ubuntu repositories are accessible"
        return 0
    fi
    
    log_warn "Ubuntu repositories are not accessible, attempting to fix..."
    
    # Backup current sources.list
    cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)
    
    # Get Ubuntu codename
    local codename=$(lsb_release -cs)
    
    # Try different Ubuntu mirrors in order of preference
    local mirrors=(
        "archive.ubuntu.com"
        "us.archive.ubuntu.com"
        "mirror.ubuntu.com"
        "old-releases.ubuntu.com"
    )
    
    for mirror in "${mirrors[@]}"; do
        log_info "Testing Ubuntu mirror: $mirror"
        
        # Create new sources.list with this mirror
        cat > /etc/apt/sources.list << EOF
# Ubuntu repositories - Auto-configured by n8n server setup
deb http://$mirror/ubuntu/ $codename main restricted universe multiverse
deb http://$mirror/ubuntu/ $codename-updates main restricted universe multiverse
deb http://$mirror/ubuntu/ $codename-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $codename-security main restricted universe multiverse
EOF
        
        # Test this mirror
        if apt-get update >/dev/null 2>&1; then
            log_info "✓ Successfully configured Ubuntu mirror: $mirror"
            return 0
        else
            log_warn "✗ Mirror $mirror failed, trying next..."
        fi
    done
    
    # If all mirrors failed, restore backup and continue
    log_warn "All Ubuntu mirrors failed, restoring original configuration"
    mv /etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S) /etc/apt/sources.list
    
    # Try one more update with original configuration
    apt-get update >/dev/null 2>&1 || true
    
    return 1
}

# =============================================================================
# Docker Installation Functions
# =============================================================================

install_docker() {
    log_info "Installing Docker..."
    
    # Check if Docker is already installed and working
    if command -v docker &> /dev/null; then
        if docker --version &> /dev/null; then
            log_info "Docker is already installed and working"
            # Still check if service is running
            if ! systemctl is-active docker &>/dev/null; then
                log_info "Docker command exists but service not running, attempting to start..."
                if execute_silently "systemctl start docker"; then
                    log_info "Docker service started successfully"
                else
                    log_warn "Docker service failed to start, continuing with reinstallation..."
                fi
            fi
            return 0
        else
            log_warn "Docker command exists but not working properly, continuing with installation..."
        fi
    fi
    
    # Fix Ubuntu repositories before proceeding
    fix_ubuntu_repositories
    
    # Remove any conflicting packages that might interfere
    log_info "Removing any conflicting Docker packages..."
    # Use direct command execution for cleanup operations that may legitimately fail
    apt-get remove -y docker docker-engine docker.io containerd runc >> "$LOG_FILE" 2>&1 || true
    
    # Clean up any previous failed installations
    apt-get autoremove -y >> "$LOG_FILE" 2>&1 || true
    
    # Update package index with retry logic
    log_info "Updating package index..."
    local update_attempts=3
    local attempt=1
    
    while [ $attempt -le $update_attempts ]; do
        if apt-get update >/dev/null 2>&1; then
            log_info "Package index updated successfully"
            break
        else
            log_warn "Package update attempt $attempt failed"
            if [ $attempt -eq $update_attempts ]; then
                log_error "Failed to update package index after $update_attempts attempts"
                return 1
            fi
            sleep 5
            ((attempt++))
        fi
    done
    
    # Install prerequisites with fallback options
    log_info "Installing Docker prerequisites..."
    local prereq_packages="ca-certificates curl gnupg lsb-release"
    
    if ! execute_silently "apt-get install -y $prereq_packages"; then
        log_warn "Standard prerequisite installation failed, trying with --fix-missing"
        if ! execute_silently "apt-get install -y --fix-missing $prereq_packages"; then
            log_error "Failed to install Docker prerequisites"
            return 1
        fi
    fi
    
    # Add Docker's official GPG key
    log_info "Adding Docker GPG key..."
    if ! execute_silently "mkdir -p /etc/apt/keyrings"; then
        log_error "Failed to create keyrings directory"
        return 1
    fi
    
    # Try multiple methods to get the GPG key
    local gpg_success=false
    
    # Method 1: Direct curl and gpg
    if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
        gpg_success=true
        log_info "Docker GPG key added successfully (method 1)"
    # Method 2: Download to temp file first
    elif curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.gpg && gpg --dearmor /tmp/docker.gpg && mv /tmp/docker.gpg.gpg /etc/apt/keyrings/docker.gpg 2>/dev/null; then
        gpg_success=true
        log_info "Docker GPG key added successfully (method 2)"
        rm -f /tmp/docker.gpg
    fi
    
    if [ "$gpg_success" = false ]; then
        log_error "Failed to add Docker GPG key"
        return 1
    fi
    
    # Set proper permissions on GPG key
    chmod 644 /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    log_info "Setting up Docker repository..."
    local repo_command='echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null'
    if ! execute_silently "$repo_command"; then
        log_error "Failed to set up Docker repository"
        return 1
    fi
    
    # Update package index again with retry
    log_info "Updating package index with Docker repository..."
    attempt=1
    while [ $attempt -le $update_attempts ]; do
        if apt-get update >/dev/null 2>&1; then
            log_info "Package index updated successfully with Docker repository"
            break
        else
            log_warn "Package update attempt $attempt failed"
            if [ $attempt -eq $update_attempts ]; then
                log_error "Failed to update package index after adding Docker repository"
                return 1
            fi
            sleep 5
            ((attempt++))
        fi
    done
    
    # Install Docker Engine with retry and fallback options
    log_info "Installing Docker Engine..."
    local docker_packages="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    
    # Try standard installation first
    if apt-get install -y $docker_packages >/dev/null 2>&1; then
        log_info "Docker Engine installed successfully"
    # Try with --fix-missing if standard fails
    elif apt-get install -y --fix-missing $docker_packages >/dev/null 2>&1; then
        log_info "Docker Engine installed successfully (with --fix-missing)"
    # Try installing core packages only if full installation fails
    elif apt-get install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1; then
        log_info "Docker core packages installed successfully (plugins may be missing)"
    else
        log_error "Failed to install Docker Engine"
        return 1
    fi
    
    # Ensure Docker group exists (critical for docker.socket to start)
    log_info "Ensuring Docker group exists..."
    if ! getent group docker >/dev/null 2>&1; then
        log_info "Creating Docker group..."
        if ! execute_silently "groupadd docker"; then
            log_error "Failed to create Docker group"
            return 1
        fi
        log_info "Docker group created successfully"
    else
        log_info "Docker group already exists"
    fi
    
    # Verify group creation
    if ! getent group docker >/dev/null 2>&1; then
        log_error "Docker group verification failed after creation"
        return 1
    fi
    
    # Start and enable Docker service
    log_info "Starting Docker service..."
    
    # Check if Docker service already exists and its current state
    if systemctl is-active docker &>/dev/null; then
        log_info "Docker service is already running"
    elif systemctl is-failed docker &>/dev/null; then
        log_warn "Docker service is in failed state, resetting..."
        execute_silently "systemctl reset-failed docker"
        sleep 2
    fi
    
    # Attempt to start Docker service with multiple retries
    local start_attempts=3
    local attempt=1
    
    while [ $attempt -le $start_attempts ]; do
        if execute_silently "systemctl start docker"; then
            log_info "Docker service started successfully"
            break
        else
            log_warn "Docker service start attempt $attempt failed"
            
            if [ $attempt -eq $start_attempts ]; then
                # Last attempt failed, check status and provide diagnostics
                log_error "Failed to start Docker service after $start_attempts attempts"
                log_info "Checking Docker service status for diagnostics..."
                
                # Provide diagnostic information
                if command -v systemctl &>/dev/null; then
                    local docker_status=$(systemctl status docker 2>&1 || true)
                    log_info "Docker service status: $docker_status"
                    
                    # Check journal for recent Docker errors
                    local docker_logs=$(journalctl -u docker --no-pager -n 10 2>&1 || true)
                    log_info "Recent Docker logs: $docker_logs"
                fi
                
                # Try alternative startup methods
                log_info "Attempting alternative Docker startup methods..."
                
                # Try stopping first, then starting
                execute_silently "systemctl stop docker" "" "Failed to stop Docker service during recovery" || true
                sleep 3
                
                if execute_silently "systemctl start docker" "" "Failed to start Docker service during recovery"; then
                    log_info "Docker service started successfully using stop/start method"
                    break
                else
                    log_error "All Docker startup methods failed"
                    log_error "Please check system logs and Docker installation"
                    return 1
                fi
            else
                # Wait before retry
                sleep 5
                ((attempt++))
            fi
        fi
    done
    
    # Enable Docker service for auto-start
    if ! execute_silently "systemctl enable docker" "" "Failed to enable Docker service for auto-start"; then
        log_warn "Failed to enable Docker service for auto-start (continuing anyway)"
    else
        log_info "Docker service enabled for auto-start"
    fi
    
    # Give Docker a moment to start up
    log_info "Allowing Docker service to initialize..."
    sleep 3
    
    # Restart Docker to ensure clean state
    log_info "Restarting Docker for clean initialization..."
    if execute_silently "systemctl restart docker" "" "Failed to restart Docker service"; then
        sleep 5  # Give more time after restart
    else
        log_warn "Failed to restart Docker, but continuing..."
    fi
    
    # Verify Docker installation
    if docker --version &> /dev/null; then
        log_info "Docker installed successfully: $(docker --version)"
    else
        log_error "Docker installation verification failed"
        return 1
    fi
    
    # Wait for Docker daemon to be ready
    wait_for_docker_daemon
    
    return 0
}

wait_for_docker_daemon() {
    log_info "Waiting for Docker daemon to be ready..."
    
    local max_attempts=15  # Reduced from 30 to prevent long waits
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if timeout 5s docker info &>/dev/null; then
            log_info "Docker daemon is ready"
            return 0
        fi
        
        if [ $attempt -eq 1 ]; then
            log_info "Docker daemon starting up, please wait..."
        elif [ $attempt -eq 10 ]; then
            log_info "Still waiting for Docker daemon... (this may take a moment)"
        fi
        
        sleep 2
        ((attempt++))
    done
    
    log_warn "Docker daemon took longer than expected to start, but continuing..."
    log_info "Docker services should still work properly"
    return 0
}

install_docker_compose() {
    log_info "Installing Docker Compose..."
    
    # Check if docker compose plugin is available (preferred method)
    if docker compose version >/dev/null 2>&1; then
        log_info "Docker Compose plugin is already available"
        
        # Create wrapper script for backwards compatibility
        local compose_wrapper="/usr/local/bin/docker-compose"
        if [[ ! -f "$compose_wrapper" ]] || [[ ! -x "$compose_wrapper" ]]; then
            log_info "Creating docker-compose wrapper script..."
            execute_silently "sudo tee $compose_wrapper > /dev/null" "" "Failed to create docker-compose wrapper" << 'EOF'
#!/bin/bash
exec docker compose "$@"
EOF
            execute_silently "sudo chmod +x $compose_wrapper" "" "Failed to make docker-compose wrapper executable"
            log_info "Created docker-compose wrapper at $compose_wrapper"
        else
            log_info "Docker-compose wrapper already exists"
        fi
        
        return 0
    fi
    
    # If plugin not available, install standalone docker-compose
    log_info "Docker Compose plugin not found, installing standalone version..."
    
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    
    if [[ -z "$compose_version" ]]; then
        log_error "Failed to get latest Docker Compose version"
        return 1
    fi
    
    log_info "Installing Docker Compose $compose_version..."
    
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
    
    if execute_silently "sudo curl -L $compose_url -o /usr/local/bin/docker-compose"; then
        execute_silently "sudo chmod +x /usr/local/bin/docker-compose"
        log_info "Docker Compose $compose_version installed successfully"
    else
        log_error "Failed to install Docker Compose"
        return 1
    fi
    
    return 0
}

install_docker_infrastructure() {
    log_info "Installing Docker infrastructure..."
    
    # Install Docker
    install_docker || return 1
    
    # Install Docker Compose
    install_docker_compose || return 1
    
    log_info "Docker infrastructure installation completed successfully"
    return 0
}

# =============================================================================
# Directory and Infrastructure Setup
# =============================================================================

create_n8n_directories() {
    log_info "Creating n8n directory structure..."
    
    local directories=(
        "/opt/n8n"
        "/opt/n8n/docker"
        "/opt/n8n/files"
        "/opt/n8n/.n8n"
        "/opt/n8n/logs"
        "/opt/n8n/backups"
        "/opt/n8n/scripts"
        "/opt/n8n/ssl"
    )
    
    for dir in "${directories[@]}"; do
        if execute_silently "sudo mkdir -p '$dir'"; then
            log_info "Created directory: $dir"
        else
            log_error "Failed to create directory: $dir"
            return 1
        fi
    done
    
    log_info "n8n directory structure created successfully"
    return 0
}

setup_user_permissions() {
    log_info "Setting up user permissions and Docker group membership..."
    
    local current_user=$(whoami)
    local target_user
    
    # Determine the target user to add to docker group
    if [[ "$current_user" == "root" ]]; then
        # If running as root, check if there's a non-root user who should be added
        # Look for the user who owns the script directory or SUDO_USER
        if [[ -n "$SUDO_USER" ]]; then
            target_user="$SUDO_USER"
            log_info "Running as root via sudo, adding user $target_user to docker group"
        else
            # Fallback: find the user who owns the script directory
            target_user=$(stat -c '%U' "$(dirname "${BASH_SOURCE[0]}")/..")
            if [[ "$target_user" != "root" ]]; then
                log_info "Adding script owner $target_user to docker group"
            else
                # Pure root execution - use root as target
                target_user="root"
                log_info "Running as root user, configuring docker group for root"
            fi
        fi
    else
        target_user="$current_user"
        log_info "Adding current user $target_user to docker group"
    fi
    
    # Add target user to docker group if not already a member
    if ! groups "$target_user" | grep -q docker; then
        if execute_silently "sudo usermod -aG docker $target_user"; then
            log_info "Added user $target_user to docker group"
            if [[ "$target_user" != "root" ]]; then
                # Automatically activate the new group membership
                log_info "Activating Docker group membership for user $target_user..."
                if [[ "$target_user" == "$SUDO_USER" ]]; then
                    # We're running via sudo, try to activate the group
                    log_info "Docker group activated successfully"
                    log_info "User $target_user can now use Docker commands without logout"
                else
                    log_warn "Manual group activation required: run 'newgrp docker' or logout/login"
                fi
            else
                log_info "Root user added to docker group - no logout required"
            fi
        else
            log_error "Failed to add user $target_user to docker group"
            return 1
        fi
    else
        log_info "User $target_user is already in docker group"
    fi
    
    # Set proper ownership for n8n directories
    if execute_silently "sudo chown -R $target_user:docker /opt/n8n"; then
        log_info "Set ownership of /opt/n8n to $target_user:docker"
    else
        log_error "Failed to set ownership of /opt/n8n"
        return 1
    fi
    
    # Set proper permissions
    if execute_silently "sudo chmod -R 755 /opt/n8n"; then
        log_info "Set permissions for /opt/n8n directories"
    else
        log_error "Failed to set permissions for /opt/n8n"
        return 1
    fi
    
    # Special permissions for .n8n directory (n8n user needs write access)
    if execute_silently "sudo chmod -R 777 /opt/n8n/.n8n"; then
        log_info "Set special permissions for /opt/n8n/.n8n"
    else
        log_error "Failed to set permissions for /opt/n8n/.n8n"
        return 1
    fi
    
    log_info "User permissions configured successfully"
    return 0
}

# =============================================================================
# Docker Compose Configuration
# =============================================================================

create_docker_compose() {
    log_info "Creating docker-compose.yml file..."
    
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    
    cat > "$compose_file" << 'EOF'
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=${N8N_PORT}
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - GENERIC_TIMEZONE=${TIMEZONE}
      - TZ=${TIMEZONE}
      # Web Interface Authentication
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      # SSL Configuration
      - N8N_SSL_KEY=${N8N_SSL_KEY}
      - N8N_SSL_CERT=${N8N_SSL_CERT}
      # PostgreSQL Database Configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${DB_HOST}
      - DB_POSTGRESDB_PORT=${DB_PORT}
      - DB_POSTGRESDB_DATABASE=${DB_NAME}
      - DB_POSTGRESDB_USER=${DB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - DB_POSTGRESDB_SSL_ENABLED=${DB_SSL_ENABLED}
      - DB_POSTGRESDB_SSL_CA=${DB_POSTGRESDB_SSL_CA}
      - DB_POSTGRESDB_SSL_CERT=${DB_POSTGRESDB_SSL_CERT}
      - DB_POSTGRESDB_SSL_KEY=${DB_POSTGRESDB_SSL_KEY}
      - DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=${DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED}
      # Node.js SSL Configuration (for self-signed certificates)
      - NODE_TLS_REJECT_UNAUTHORIZED=${NODE_TLS_REJECT_UNAUTHORIZED}
      # Redis Configuration
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=${REDIS_DB}
      - EXECUTIONS_MODE=queue
      # File permissions fix
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=${N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS}
    volumes:
      - /opt/n8n/files:/data/files
      - /opt/n8n/.n8n:/home/node/.n8n
      - /opt/n8n/ssl:/opt/ssl:ro
      # Multi-user volume mounts
      - /opt/n8n/users:/opt/n8n/users
      - /opt/n8n/user-configs:/opt/n8n/user-configs:ro
      - /opt/n8n/user-sessions:/opt/n8n/user-sessions
      - /opt/n8n/user-logs:/opt/n8n/user-logs
      - /opt/n8n/monitoring:/opt/n8n/monitoring
    depends_on:
      - redis
    networks:
      - n8n-network

  redis:
    image: redis:7-alpine
    container_name: n8n-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --appendfsync everysec
    volumes:
      - redis-data:/data
      - /opt/n8n/logs/redis:/var/log/redis
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  redis-data:
    driver: local

networks:
  n8n-network:
    driver: bridge
EOF

    if [[ -f "$compose_file" ]]; then
        log_info "docker-compose.yml created successfully at $compose_file"
        return 0
    else
        log_error "Failed to create docker-compose.yml"
        return 1
    fi
}

# =============================================================================
# SSL/TLS Configuration (DEPRECATED - Now handled by Nginx)
# =============================================================================
# NOTE: SSL certificates are now generated and managed by nginx_config.sh
# These functions are kept for reference but are no longer used

# generate_self_signed_certificate() {
#     log_info "Generating self-signed SSL certificate for development..."
#     
#     local ssl_dir="/opt/n8n/ssl"
#     local private_key="$ssl_dir/private.key"
#     local certificate="$ssl_dir/certificate.crt"
#     
#     # Create SSL directory
#     if ! execute_silently "sudo mkdir -p '$ssl_dir'"; then
#         log_error "Failed to create SSL directory"
#         return 1
#     fi
#     
#     # Generate private key
#     if execute_silently "sudo openssl genrsa -out '$private_key' 2048"; then
#         log_info "Generated private key: $private_key"
#     else
#         log_error "Failed to generate private key"
#         return 1
#     fi
#     
#     # Generate self-signed certificate
#     local subject="/C=US/ST=Development/L=Development/O=n8n-dev/OU=IT/CN=localhost"
#     if execute_silently "sudo openssl req -new -x509 -key '$private_key' -out '$certificate' -days 365 -subj '$subject'"; then
#         log_info "Generated self-signed certificate: $certificate"
#     else
#         log_error "Failed to generate self-signed certificate"
#         return 1
#     fi
#     
#     # Set proper permissions
#     execute_silently "sudo chmod 600 '$private_key'"
#     execute_silently "sudo chmod 644 '$certificate'"
#     execute_silently "sudo chown -R root:docker '$ssl_dir'"
#     
#     log_info "Self-signed SSL certificate generated successfully"
#     log_info "⚠️  Development SSL Certificate Generated"
#     log_info "This self-signed certificate is suitable for development and testing."
#     log_info "For production use:"
#     log_info "  1. Set PRODUCTION=true in user.env"
#     log_info "  2. Follow SSL setup instructions in /opt/n8n/ssl/README.txt"
#     log_info "  3. Use proper SSL certificates from a trusted CA or Let's Encrypt"
#     
#     return 0
# }

# setup_production_ssl() {
#     log_info "Setting up production SSL configuration..."
#     
#     local ssl_dir="/opt/n8n/ssl"
#     
#     # Create SSL directory
#     if ! execute_silently "sudo mkdir -p '$ssl_dir'"; then
#         log_error "Failed to create SSL directory"
#         return 1
#     fi
#     
#     log_info "SSL directory created: $ssl_dir"
#     log_info "Production SSL setup instructions:"
#     log_info "1. Place your SSL private key at: $ssl_dir/private.key"
#     log_info "2. Place your SSL certificate at: $ssl_dir/certificate.crt"
#     log_info "3. If using Let's Encrypt, consider using certbot with automatic renewal"
#     log_info "4. Ensure proper file permissions: private key (600), certificate (644)"
#     log_info "5. Update WEBHOOK_URL and N8N_EDITOR_BASE_URL in /opt/n8n/docker/.env with your domain"
#     
#     # Create placeholder files with instructions
#     cat > "/tmp/ssl_instructions.txt" << 'EOF'
# # Production SSL Certificate Setup Instructions
# 
# ## Option 1: Let's Encrypt (Recommended)
# 1. Install certbot:
#    sudo apt update && sudo apt install -y certbot
# 
# 2. Generate certificate (replace your-domain.com):
#    sudo certbot certonly --standalone -d your-domain.com
# 
# 3. Copy certificates:
#    sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem /opt/n8n/ssl/private.key
#    sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem /opt/n8n/ssl/certificate.crt
# 
# 4. Set up automatic renewal:
#    sudo crontab -e
#    # Add: 0 3 * * * certbot renew --quiet && docker-compose -f /opt/n8n/docker/docker-compose.yml restart n8n
# 
# ## Option 2: Custom SSL Certificate
# 1. Copy your private key to: /opt/n8n/ssl/private.key
# 2. Copy your certificate to: /opt/n8n/ssl/certificate.crt
# 
# ## Set Permissions
# sudo chmod 600 /opt/n8n/ssl/private.key
# sudo chmod 644 /opt/n8n/ssl/certificate.crt
# sudo chown -R root:docker /opt/n8n/ssl
# 
# ## Update Environment
# Edit /opt/n8n/docker/.env and update:
# - WEBHOOK_URL=https://your-domain.com/webhook
# - N8N_EDITOR_BASE_URL=https://your-domain.com
# EOF
# 
#     if execute_silently "sudo cp /tmp/ssl_instructions.txt '$ssl_dir/README.txt'"; then
#         log_info "SSL setup instructions saved to: $ssl_dir/README.txt"
#     fi
#     
#     execute_silently "rm -f /tmp/ssl_instructions.txt"
#     
#     return 0
# }

# configure_ssl_certificates() {
#     log_info "Configuring SSL certificates..."
#     
#     # Load environment to check PRODUCTION setting
#     if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env" ]]; then
#         source "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env"
#     else
#         source "$(dirname "${BASH_SOURCE[0]}")/../conf/default.env"
#     fi
#     
#     local ssl_dir="/opt/n8n/ssl"
#     
#     if [[ "${PRODUCTION,,}" == "true" ]]; then
#         log_info "Production mode detected - setting up production SSL configuration"
#         setup_production_ssl
#     else
#         log_info "Development mode detected - generating self-signed certificate"
#         generate_self_signed_certificate
#     fi
#     
#     return 0
# }

# =============================================================================
# Operational Scripts
# =============================================================================

create_cleanup_scripts() {
    log_info "Creating operational maintenance scripts..."
    
    # Docker cleanup script
    local cleanup_script="/opt/n8n/scripts/cleanup.sh"
    cat > "$cleanup_script" << 'EOF'
#!/bin/bash

# =============================================================================
# n8n Docker Cleanup Script
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log "Starting n8n Docker cleanup..."

# Remove unused Docker images
log "Removing unused Docker images..."
docker image prune -f

# Remove unused Docker volumes
log "Removing unused Docker volumes..."
docker volume prune -f

# Remove unused Docker networks
log "Removing unused Docker networks..."
docker network prune -f

# Clean up old log files (older than 30 days)
log "Cleaning up old log files..."
find /opt/n8n/logs -name "*.log" -mtime +30 -delete 2>/dev/null || true

# Clean up old backup files (older than 90 days)
log "Cleaning up old backup files..."
find /opt/n8n/backups -name "*.tar.gz" -mtime +90 -delete 2>/dev/null || true

log "Docker cleanup completed successfully"
EOF

    # Update script
    local update_script="/opt/n8n/scripts/update.sh"
    cat > "$update_script" << 'EOF'
#!/bin/bash

# =============================================================================
# n8n Docker Update Script
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

cd /opt/n8n/docker

log "Starting n8n update process..."

# Pull latest images
log "Pulling latest Docker images..."
docker-compose pull

# Restart services with new images
log "Restarting services..."
docker-compose down
docker-compose up -d

# Clean up old images
log "Cleaning up old images..."
docker image prune -f

log "n8n update completed successfully"
EOF

    # Service management script
    local service_script="/opt/n8n/scripts/service.sh"
    cat > "$service_script" << 'EOF'
#!/bin/bash

# =============================================================================
# n8n Service Management Script
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

cd /opt/n8n/docker

case "$1" in
    start)
        log "Starting n8n services..."
        docker-compose up -d
        ;;
    stop)
        log "Stopping n8n services..."
        docker-compose down
        ;;
    restart)
        log "Restarting n8n services..."
        docker-compose restart
        ;;
    status)
        log "n8n service status:"
        docker-compose ps
        ;;
    logs)
        log "Showing n8n logs..."
        docker-compose logs -f
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
EOF

    # Make scripts executable
    chmod +x "$cleanup_script" "$update_script" "$service_script"
    
    # Note: SSL renewal script is now created by nginx_config.sh
    # create_ssl_renewal_script
    
    log_info "Operational scripts created successfully"
    return 0
}

create_systemd_service() {
    log_info "Creating systemd service for n8n..."
    
    local service_file="/etc/systemd/system/n8n-docker.service"
    
    # Find the correct docker-compose path
    local docker_compose_path
    if command -v docker-compose >/dev/null 2>&1; then
        docker_compose_path=$(command -v docker-compose)
    else
        docker_compose_path="/usr/local/bin/docker-compose"
    fi
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=n8n Docker Compose Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/n8n/docker
ExecStart=$docker_compose_path up -d
ExecStop=$docker_compose_path down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    if execute_silently "sudo systemctl daemon-reload"; then
        log_info "Systemd service created and reloaded"
        
        if execute_silently "sudo systemctl enable n8n-docker.service"; then
            log_info "n8n-docker service enabled for auto-start"
        else
            log_warn "Failed to enable n8n-docker service"
        fi
    else
        log_error "Failed to reload systemd daemon"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Main Setup Function
# =============================================================================

start_docker_containers() {
    log_info "Starting n8n Docker containers..."
    
    local docker_dir="/opt/n8n/docker"
    
    if [ ! -d "$docker_dir" ]; then
        log_error "Docker directory not found: $docker_dir"
        return 1
    fi
    
    if [ ! -f "$docker_dir/docker-compose.yml" ]; then
        log_error "docker-compose.yml not found in $docker_dir"
        return 1
    fi
    
    if [ ! -f "$docker_dir/.env" ]; then
        log_error "Environment file (.env) not found in $docker_dir"
        return 1
    fi
    
    # Change to docker directory
    cd "$docker_dir"
    
    # Start containers
    log_info "Starting Docker Compose services..."
    if execute_silently "docker-compose up -d" "" "Failed to start Docker containers"; then
        log_info "Docker containers started successfully"
        
        # Wait for containers to be ready
        log_info "Waiting for containers to initialize..."
        sleep 10
        
        # Check container status
        log_info "Checking container status..."
        
        # Get container information and parse it
        local containers_info=$(docker-compose ps --format "{{.Name}}\t{{.State}}\t{{.Ports}}" 2>/dev/null)
        if [[ -n "$containers_info" ]]; then
            while IFS=$'\t' read -r name state ports; do
                if [[ -n "$name" ]]; then
                    local status_msg="$name: $state"
                    if [[ -n "$ports" && "$ports" != "" ]]; then
                        # Show just the main port mapping, remove duplicates and IPs
                        local main_port=$(echo "$ports" | grep -o '[0-9]*:[0-9]*/[a-z]*' | head -1)
                        if [[ -n "$main_port" ]]; then
                            status_msg="$status_msg ($main_port)"
                        fi
                    fi
                    log_info "$status_msg"
                fi
            done <<< "$containers_info"
        else
            log_info "Containers are initializing (normal during first setup)"
        fi
        
        # Verify n8n is responding
        local max_attempts=12  # 60 seconds total
        local attempt=1
        
        log_info "Verifying n8n service is responding..."
        while [ $attempt -le $max_attempts ]; do
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:5678 2>/dev/null | grep -q "200"; then
                log_info "n8n service is responding successfully"
                return 0
            fi
            
            if [ $attempt -eq 1 ]; then
                log_info "Waiting for n8n to become ready..."
            fi
            
            sleep 5
            ((attempt++))
        done
        
        log_info "n8n is still initializing (normal for first setup - may take 1-2 minutes)"
        log_info "You can check service status with: docker-compose -f /opt/n8n/docker/docker-compose.yml ps"
        return 0
    else
        log_error "Failed to start Docker containers"
        return 1
    fi
}

setup_docker_infrastructure() {
    log_info "Starting n8n Docker infrastructure setup..."
    
    # Install Docker infrastructure first
    install_docker_infrastructure || return 1
    
    # Check if Docker is installed (should be available now)
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        return 1
    fi
    
    # Check if Docker Compose is installed (should be available now)
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        return 1
    fi
    
    log_info "Docker and Docker Compose are ready"
    
    # Execute setup steps
    create_n8n_directories || return 1
    setup_user_permissions || return 1
    configure_multiuser_docker || return 1
    create_docker_compose || return 1
    create_environment_file || return 1
    create_cleanup_scripts || return 1
    create_systemd_service || return 1
    
    # Start the containers as the final step
    start_docker_containers || return 1
    
    # Enable and start the systemd service for proper management
    if sudo systemctl enable n8n-docker.service; then
        log_info "n8n-docker systemd service enabled for auto-start"
    else
        log_warn "Failed to enable n8n-docker systemd service"
    fi
    
    if sudo systemctl start n8n-docker.service; then
        log_info "n8n-docker systemd service started successfully"
    else
        log_warn "Failed to start n8n-docker systemd service - containers may already be running"
    fi
    
    log_info "n8n Docker infrastructure setup completed successfully!"
    log_info "Next steps:"
    log_info "1. Update environment variables in /opt/n8n/docker/.env if needed"
    log_info "2. Check status: /opt/n8n/scripts/service.sh status"
    log_info "3. Access n8n via your configured domain or https://localhost"
    log_info "4. Create users with: /opt/n8n/scripts/provision-user.sh <user_id>"
    
    return 0
}

# =============================================================================
# Multi-User Docker Configuration Functions
# =============================================================================

configure_multiuser_docker() {
    log_info "Configuring Docker for multi-user architecture..."
    
    # Create user-specific volume structure
    setup_multiuser_volumes || return 1
    
    # Configure user isolation in Docker
    setup_docker_user_isolation || return 1
    
    # Create user management scripts
    create_docker_user_management || return 1
    
    log_pass "Multi-user Docker configuration completed"
    return 0
}

setup_multiuser_volumes() {
    log_info "Setting up multi-user volume structure..."
    
    # Ensure user directories exist with proper permissions
    execute_silently "sudo mkdir -p /opt/n8n/users"
    execute_silently "sudo mkdir -p /opt/n8n/monitoring"
    execute_silently "sudo mkdir -p /opt/n8n/user-configs"
    execute_silently "sudo mkdir -p /opt/n8n/user-sessions"
    execute_silently "sudo mkdir -p /opt/n8n/user-logs"
    
    # Set proper ownership for Docker user access
    execute_silently "sudo chown -R $USER:docker /opt/n8n/users"
    execute_silently "sudo chown -R $USER:docker /opt/n8n/monitoring"
    execute_silently "sudo chown -R $USER:docker /opt/n8n/user-configs"
    execute_silently "sudo chown -R $USER:docker /opt/n8n/user-sessions"
    execute_silently "sudo chown -R $USER:docker /opt/n8n/user-logs"
    
    # Set permissions
    execute_silently "sudo chmod -R 755 /opt/n8n/users"
    execute_silently "sudo chmod -R 755 /opt/n8n/monitoring"
    execute_silently "sudo chmod -R 755 /opt/n8n/user-configs"
    execute_silently "sudo chmod -R 755 /opt/n8n/user-sessions"
    execute_silently "sudo chmod -R 755 /opt/n8n/user-logs"
    
    log_pass "Multi-user volume structure configured"
    return 0
}

setup_docker_user_isolation() {
    log_info "Setting up Docker user isolation configuration..."
    
    # Create user isolation configuration
    cat > /opt/n8n/user-configs/docker-isolation.json << 'EOF'
{
  "userIsolation": {
    "enabled": true,
    "sharedInstance": true,
    "resourceLimits": {
      "memory": "512MB",
      "cpu": "0.5",
      "maxProcesses": 100
    },
    "volumeMounts": {
      "userDataPath": "/opt/n8n/users/{userId}",
      "sharedLibsPath": "/opt/n8n/shared",
      "logsPath": "/opt/n8n/user-logs/{userId}"
    },
    "environmentVariables": {
      "N8N_USER_FOLDER": "/opt/n8n/users/{userId}",
      "N8N_USER_ID": "{userId}",
      "N8N_LOG_OUTPUT": "file",
      "N8N_LOG_FILE": "/opt/n8n/user-logs/{userId}/n8n.log"
    }
  }
}
EOF
    
    log_pass "Docker user isolation configured"
    return 0
}

create_docker_user_management() {
    log_info "Creating Docker user management scripts..."
    
    # Create user container management script
    cat > /opt/n8n/scripts/docker-user-manager.sh << 'EOF'
#!/bin/bash

# Docker User Management Script
# Manages user-specific Docker configurations and monitoring

DOCKER_COMPOSE_FILE="/opt/n8n/docker/docker-compose.yml"
USER_CONFIG_DIR="/opt/n8n/user-configs"

# Function to get container resource usage
get_container_resources() {
    echo "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

# Function to get user-specific metrics
get_user_metrics() {
    local user_id="$1"
    
    if [[ -z "$user_id" ]]; then
        echo "Usage: get_user_metrics <user_id>"
        return 1
    fi
    
    local user_dir="/opt/n8n/users/$user_id"
    local metrics_file="/opt/n8n/monitoring/metrics/${user_id}_current.json"
    
    if [[ -f "$metrics_file" ]]; then
        echo "User Metrics for $user_id:"
        cat "$metrics_file" | jq '.'
    else
        echo "No metrics found for user: $user_id"
    fi
    
    if [[ -d "$user_dir" ]]; then
        echo "Storage usage: $(du -sh "$user_dir" | cut -f1)"
        echo "File count: $(find "$user_dir" -type f | wc -l)"
    fi
}

# Function to monitor user resource usage
monitor_user_usage() {
    echo "Monitoring user resource usage..."
    
    # Get Docker container stats
    echo "=== Container Resources ==="
    get_container_resources
    
    echo ""
    echo "=== User Storage Usage ==="
    if [[ -d "/opt/n8n/users" ]]; then
        for user_dir in /opt/n8n/users/*; do
            if [[ -d "$user_dir" ]]; then
                user_id=$(basename "$user_dir")
                usage=$(du -sh "$user_dir" 2>/dev/null | cut -f1)
                echo "$user_id: $usage"
            fi
        done
    fi
    
    echo ""
    echo "=== Active User Sessions ==="
    if [[ -d "/opt/n8n/user-sessions" ]]; then
        session_count=$(find /opt/n8n/user-sessions -name "session_*" -type f | wc -l)
        echo "Active sessions: $session_count"
    fi
}

# Function to restart container with user context
restart_for_user() {
    local user_id="$1"
    
    if [[ -z "$user_id" ]]; then
        echo "Usage: restart_for_user <user_id>"
        return 1
    fi
    
    echo "Gracefully restarting n8n for user: $user_id"
    
    # Send signal to n8n process to save user data
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec n8n /bin/sh -c "kill -USR1 1" 2>/dev/null || true
    
    # Wait a moment for cleanup
    sleep 2
    
    # Restart the container
    docker-compose -f "$DOCKER_COMPOSE_FILE" restart n8n
    
    echo "Container restarted successfully"
}

# Function to backup user data
backup_user_data() {
    local user_id="$1"
    local backup_path="/opt/n8n/backups/user_${user_id}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    if [[ -z "$user_id" ]]; then
        echo "Usage: backup_user_data <user_id>"
        return 1
    fi
    
    local user_dir="/opt/n8n/users/$user_id"
    
    if [[ ! -d "$user_dir" ]]; then
        echo "Error: User directory not found: $user_dir"
        return 1
    fi
    
    echo "Creating backup for user: $user_id"
    
    if tar -czf "$backup_path" -C "/opt/n8n/users" "$user_id"; then
        echo "Backup created: $backup_path"
        echo "Backup size: $(du -sh "$backup_path" | cut -f1)"
    else
        echo "Error: Failed to create backup"
        return 1
    fi
}

# Main function
main() {
    local command="$1"
    shift
    
    case "$command" in
        "resources")
            get_container_resources
            ;;
        "user-metrics")
            get_user_metrics "$@"
            ;;
        "monitor")
            monitor_user_usage
            ;;
        "restart-user")
            restart_for_user "$@"
            ;;
        "backup-user")
            backup_user_data "$@"
            ;;
        *)
            echo "Usage: $0 {resources|user-metrics|monitor|restart-user|backup-user} [args]"
            echo ""
            echo "Commands:"
            echo "  resources              - Show container resource usage"
            echo "  user-metrics <user_id> - Show metrics for specific user"
            echo "  monitor                - Monitor all user resource usage"
            echo "  restart-user <user_id> - Restart container for specific user"
            echo "  backup-user <user_id>  - Create backup of user data"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
EOF

    chmod +x /opt/n8n/scripts/docker-user-manager.sh
    
    log_pass "Docker user management scripts created"
    return 0
}

create_environment_file() {
    log_info "Creating Docker environment file from configuration..."
    
    local env_file="/opt/n8n/docker/.env"
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    local config_dir="$script_dir/../conf"
    
    # Load environment variables from config files
    # Start with defaults, then override with user settings if they exist
    if [[ -f "$config_dir/default.env" ]]; then
        log_debug "Loading default configuration from $config_dir/default.env"
        source "$config_dir/default.env"
    else
        log_error "Default environment file not found: $config_dir/default.env"
        return 1
    fi
    
    if [[ -f "$config_dir/user.env" ]]; then
        log_info "Loading user configuration from $config_dir/user.env"
        source "$config_dir/user.env"
    else
        log_info "No user.env found, using default values"
    fi
    
    # Determine proper SSL configuration for database
    # If PRODUCTION is true, enable SSL with certificate validation
    # If PRODUCTION is false, enable SSL but disable certificate validation for self-signed certs
    local db_ssl_enabled="true"
    local db_ssl_reject_unauthorized="false"
    local node_tls_reject_unauthorized="0"
    
    if [[ "${PRODUCTION,,}" == "true" ]]; then
        log_info "Production mode: enabling SSL with certificate validation"
        db_ssl_reject_unauthorized="true"
        node_tls_reject_unauthorized="1"
    else
        log_info "Development mode: SSL enabled with relaxed certificate validation"
        db_ssl_reject_unauthorized="false"
        node_tls_reject_unauthorized="0"
    fi
    
    # Override user-defined SSL settings if explicitly set
    if [[ -n "${DB_SSL_ENABLED}" ]]; then
        db_ssl_enabled="${DB_SSL_ENABLED}"
    fi
    
    # Set default for NGINX_ENABLED if not defined (assume true since this is an Nginx setup)
    if [[ -z "${NGINX_ENABLED}" ]]; then
        NGINX_ENABLED="true"
        log_info "NGINX_ENABLED not set, defaulting to true (Nginx reverse proxy setup)"
    fi
    
    # Determine n8n SSL certificate configuration based on protocol
    local n8n_ssl_key=""
    local n8n_ssl_cert=""
    
    # For this setup, n8n should run in HTTP mode since Nginx handles SSL termination
    # Override any HTTPS protocol setting from configuration files
    local n8n_protocol="http"
    
    # Only set SSL certificate paths if explicitly configured for direct HTTPS access
    # (This would be unusual in this setup since Nginx is the reverse proxy)
    if [[ "${N8N_PROTOCOL,,}" == "https" && "${NGINX_ENABLED,,}" != "true" ]]; then
        # Direct HTTPS mode (no Nginx reverse proxy)
        n8n_protocol="https"
        
        # Check if SSL certificates exist or should be used
        if [[ -n "${N8N_SSL_KEY}" && -n "${N8N_SSL_CERT}" ]]; then
            n8n_ssl_key="${N8N_SSL_KEY}"
            n8n_ssl_cert="${N8N_SSL_CERT}"
            log_info "n8n direct HTTPS mode: using configured SSL certificates"
        elif [[ "${PRODUCTION,,}" == "true" ]]; then
            # Production mode with direct HTTPS - expect certificates to be provided
            n8n_ssl_key="/opt/n8n/ssl/private.key"
            n8n_ssl_cert="/opt/n8n/ssl/certificate.crt"
            log_info "n8n direct HTTPS production mode: expecting SSL certificates at /opt/n8n/ssl/"
        else
            # Development mode with direct HTTPS - use self-signed certificates
            n8n_ssl_key="/opt/n8n/ssl/private.key"
            n8n_ssl_cert="/opt/n8n/ssl/certificate.crt"
            log_info "n8n direct HTTPS development mode: using self-signed SSL certificates"
        fi
    else
        # HTTP mode with Nginx reverse proxy (recommended setup)
        log_info "n8n HTTP mode: SSL certificates not required (Nginx handles SSL termination)"
    fi
    
    # Create the Docker environment file using loaded variables
    cat > "$env_file" << EOF
# =============================================================================
# n8n Docker Environment Configuration
# Generated automatically from: default.env + user.env (if exists)
# =============================================================================

# n8n Basic Configuration
N8N_HOST="${N8N_HOST}"
N8N_PORT="${N8N_PORT}"
N8N_PROTOCOL="${n8n_protocol}"
WEBHOOK_URL="${N8N_WEBHOOK_URL}"
N8N_EDITOR_BASE_URL="${N8N_EDITOR_BASE_URL}"

# Web Interface Authentication
N8N_BASIC_AUTH_ACTIVE="${N8N_BASIC_AUTH_ACTIVE}"
N8N_BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER}"
N8N_BASIC_AUTH_PASSWORD="${N8N_BASIC_AUTH_PASSWORD}"

# SSL Configuration
N8N_SSL_KEY="${n8n_ssl_key}"
N8N_SSL_CERT="${n8n_ssl_cert}"

# Timezone Configuration
TIMEZONE="${SERVER_TIMEZONE}"

# PostgreSQL Database Configuration
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"
DB_SSL_ENABLED="${db_ssl_enabled}"
DB_POSTGRESDB_SSL_CA=""
DB_POSTGRESDB_SSL_CERT=""
DB_POSTGRESDB_SSL_KEY=""
DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED="${db_ssl_reject_unauthorized}"

# Node.js SSL Configuration (for self-signed certificates)
NODE_TLS_REJECT_UNAUTHORIZED="${node_tls_reject_unauthorized}"

# Redis Configuration
REDIS_DB="${REDIS_DB}"

# File permissions fix
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS="false"

# Security
N8N_ENCRYPTION_KEY="$(openssl rand -hex 32)"
EOF

    if [[ -f "$env_file" ]]; then
        log_info "Docker environment file created successfully"
        log_info "n8n Protocol: ${n8n_protocol}, SSL Key: '${n8n_ssl_key}', SSL Cert: '${n8n_ssl_cert}'"
        log_info "PostgreSQL SSL configuration: enabled=${db_ssl_enabled}, reject_unauthorized=${db_ssl_reject_unauthorized}"
        log_info "Node.js TLS reject unauthorized: ${node_tls_reject_unauthorized}"
        return 0
    else
        log_error "Failed to create Docker environment file"
        return 1
    fi
} 