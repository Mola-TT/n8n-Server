#!/bin/bash

# =============================================================================
# Docker Configuration Script for n8n Server - Milestone 2
# =============================================================================
# This script sets up the complete Docker infrastructure for n8n server
# including Redis, PostgreSQL integration, and operational maintenance
# =============================================================================

# Source required libraries
source "$(dirname "$0")/../lib/logger.sh"
source "$(dirname "$0")/../lib/utilities.sh"

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
    
    # Add user to docker group if not already a member
    if ! groups "$current_user" | grep -q docker; then
        if execute_silently "sudo usermod -aG docker $current_user"; then
            log_info "Added user $current_user to docker group"
            log_warning "Please log out and log back in for group changes to take effect"
        else
            log_error "Failed to add user to docker group"
            return 1
        fi
    else
        log_info "User $current_user is already in docker group"
    fi
    
    # Set proper ownership for n8n directories
    if execute_silently "sudo chown -R $current_user:docker /opt/n8n"; then
        log_info "Set ownership of /opt/n8n to $current_user:docker"
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
      # Redis Configuration
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=${REDIS_DB}
      - EXECUTIONS_MODE=queue
    volumes:
      - /opt/n8n/files:/data/files
      - /opt/n8n/.n8n:/home/node/.n8n
      - /opt/n8n/ssl:/opt/ssl:ro
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

create_environment_file() {
    log_info "Creating Docker environment file..."
    
    local env_file="/opt/n8n/docker/.env"
    
    cat > "$env_file" << 'EOF'
# =============================================================================
# n8n Docker Environment Configuration
# =============================================================================

# n8n Basic Configuration
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://your-domain.com/webhook
N8N_EDITOR_BASE_URL=https://your-domain.com

# SSL Configuration
N8N_SSL_KEY=/opt/ssl/private.key
N8N_SSL_CERT=/opt/ssl/certificate.crt

# Timezone Configuration
TIMEZONE=UTC

# PostgreSQL Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=n8n
DB_USER=n8n_user
DB_PASSWORD=your_secure_password
DB_SSL_ENABLED=false

# Redis Configuration
REDIS_DB=0

# Security
N8N_ENCRYPTION_KEY=your_encryption_key_here
EOF

    if [[ -f "$env_file" ]]; then
        log_info "Environment file created at $env_file"
        log_warning "Please update the environment variables in $env_file with your actual values"
        return 0
    else
        log_error "Failed to create environment file"
        return 1
    fi
}

# =============================================================================
# SSL/TLS Configuration
# =============================================================================

generate_self_signed_certificate() {
    log_info "Generating self-signed SSL certificate for development..."
    
    local ssl_dir="/opt/n8n/ssl"
    local private_key="$ssl_dir/private.key"
    local certificate="$ssl_dir/certificate.crt"
    
    # Create SSL directory
    if ! execute_silently "sudo mkdir -p '$ssl_dir'"; then
        log_error "Failed to create SSL directory"
        return 1
    fi
    
    # Generate private key
    if execute_silently "sudo openssl genrsa -out '$private_key' 2048"; then
        log_info "Generated private key: $private_key"
    else
        log_error "Failed to generate private key"
        return 1
    fi
    
    # Generate self-signed certificate
    local subject="/C=US/ST=Development/L=Development/O=n8n-dev/OU=IT/CN=localhost"
    if execute_silently "sudo openssl req -new -x509 -key '$private_key' -out '$certificate' -days 365 -subj '$subject'"; then
        log_info "Generated self-signed certificate: $certificate"
    else
        log_error "Failed to generate self-signed certificate"
        return 1
    fi
    
    # Set proper permissions
    execute_silently "sudo chmod 600 '$private_key'"
    execute_silently "sudo chmod 644 '$certificate'"
    execute_silently "sudo chown -R root:docker '$ssl_dir'"
    
    log_info "Self-signed SSL certificate generated successfully"
    log_warning "This is a development certificate. Use proper SSL certificates for production."
    
    return 0
}

setup_production_ssl() {
    log_info "Setting up production SSL configuration..."
    
    local ssl_dir="/opt/n8n/ssl"
    
    # Create SSL directory
    if ! execute_silently "sudo mkdir -p '$ssl_dir'"; then
        log_error "Failed to create SSL directory"
        return 1
    fi
    
    log_info "SSL directory created: $ssl_dir"
    log_info "Production SSL setup instructions:"
    log_info "1. Place your SSL private key at: $ssl_dir/private.key"
    log_info "2. Place your SSL certificate at: $ssl_dir/certificate.crt"
    log_info "3. If using Let's Encrypt, consider using certbot with automatic renewal"
    log_info "4. Ensure proper file permissions: private key (600), certificate (644)"
    log_info "5. Update WEBHOOK_URL and N8N_EDITOR_BASE_URL in /opt/n8n/docker/.env with your domain"
    
    # Create placeholder files with instructions
    cat > "/tmp/ssl_instructions.txt" << 'EOF'
# Production SSL Certificate Setup Instructions

## Option 1: Let's Encrypt (Recommended)
1. Install certbot:
   sudo apt update && sudo apt install -y certbot

2. Generate certificate (replace your-domain.com):
   sudo certbot certonly --standalone -d your-domain.com

3. Copy certificates:
   sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem /opt/n8n/ssl/private.key
   sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem /opt/n8n/ssl/certificate.crt

4. Set up automatic renewal:
   sudo crontab -e
   # Add: 0 3 * * * certbot renew --quiet && docker-compose -f /opt/n8n/docker/docker-compose.yml restart n8n

## Option 2: Custom SSL Certificate
1. Copy your private key to: /opt/n8n/ssl/private.key
2. Copy your certificate to: /opt/n8n/ssl/certificate.crt

## Set Permissions
sudo chmod 600 /opt/n8n/ssl/private.key
sudo chmod 644 /opt/n8n/ssl/certificate.crt
sudo chown -R root:docker /opt/n8n/ssl

## Update Environment
Edit /opt/n8n/docker/.env and update:
- WEBHOOK_URL=https://your-domain.com/webhook
- N8N_EDITOR_BASE_URL=https://your-domain.com
EOF

    if execute_silently "sudo cp /tmp/ssl_instructions.txt '$ssl_dir/README.txt'"; then
        log_info "SSL setup instructions saved to: $ssl_dir/README.txt"
    fi
    
    execute_silently "rm -f /tmp/ssl_instructions.txt"
    
    return 0
}

configure_ssl_certificates() {
    log_info "Configuring SSL certificates..."
    
    # Load environment to check PRODUCTION setting
    if [[ -f "$(dirname "$0")/../conf/user.env" ]]; then
        source "$(dirname "$0")/../conf/user.env"
    else
        source "$(dirname "$0")/../conf/default.env"
    fi
    
    local ssl_dir="/opt/n8n/ssl"
    
    if [[ "${PRODUCTION,,}" == "true" ]]; then
        log_info "Production mode detected - setting up production SSL configuration"
        setup_production_ssl
    else
        log_info "Development mode detected - generating self-signed certificate"
        generate_self_signed_certificate
    fi
    
    return 0
}

create_ssl_renewal_script() {
    log_info "Creating SSL certificate renewal script..."
    
    local renewal_script="/opt/n8n/scripts/ssl-renew.sh"
    cat > "$renewal_script" << 'EOF'
#!/bin/bash

# =============================================================================
# SSL Certificate Renewal Script
# =============================================================================

echo "Starting SSL certificate renewal process..."

# Check if we're in production mode
if [[ "${PRODUCTION,,}" == "true" ]]; then
    echo "Production mode - attempting Let's Encrypt renewal..."
    
    # Attempt certificate renewal
    if certbot renew --quiet; then
        echo "Certificate renewal successful"
        
        # Copy renewed certificates
        if [[ -d "/etc/letsencrypt/live" ]]; then
            for domain_dir in /etc/letsencrypt/live/*/; do
                if [[ -f "$domain_dir/privkey.pem" && -f "$domain_dir/fullchain.pem" ]]; then
                    echo "Copying renewed certificates for $(basename "$domain_dir")"
                    sudo cp "$domain_dir/privkey.pem" /opt/n8n/ssl/private.key
                    sudo cp "$domain_dir/fullchain.pem" /opt/n8n/ssl/certificate.crt
                    sudo chmod 600 /opt/n8n/ssl/private.key
                    sudo chmod 644 /opt/n8n/ssl/certificate.crt
                    break
                fi
            done
        fi
        
        # Restart n8n to use new certificates
        echo "Restarting n8n service..."
        cd /opt/n8n/docker && docker-compose restart n8n
        
        echo "SSL certificate renewal completed successfully"
    else
        echo "Certificate renewal failed or not needed"
    fi
else
    echo "Development mode - regenerating self-signed certificate..."
    
    # Regenerate self-signed certificate (valid for another year)
    cd /opt/n8n/ssl
    
    if openssl genrsa -out private.key 2048 && \
       openssl req -new -x509 -key private.key -out certificate.crt -days 365 \
       -subj "/C=US/ST=Development/L=Development/O=n8n-dev/OU=IT/CN=localhost"; then
        
        chmod 600 private.key
        chmod 644 certificate.crt
        chown -R root:docker /opt/n8n/ssl
        
        echo "Self-signed certificate regenerated"
        
        # Restart n8n
        cd /opt/n8n/docker && docker-compose restart n8n
        echo "n8n restarted with new certificate"
    else
        echo "Failed to regenerate self-signed certificate"
        exit 1
    fi
fi

echo "SSL renewal process completed"
EOF

    chmod +x "$renewal_script"
    log_info "SSL renewal script created: $renewal_script"
    
    return 0
}

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

echo "Starting n8n Docker cleanup..."

# Remove unused Docker images
echo "Removing unused Docker images..."
docker image prune -f

# Remove unused Docker volumes
echo "Removing unused Docker volumes..."
docker volume prune -f

# Remove unused Docker networks
echo "Removing unused Docker networks..."
docker network prune -f

# Clean up old log files (older than 30 days)
echo "Cleaning up old log files..."
find /opt/n8n/logs -name "*.log" -mtime +30 -delete 2>/dev/null || true

# Clean up old backup files (older than 90 days)
echo "Cleaning up old backup files..."
find /opt/n8n/backups -name "*.tar.gz" -mtime +90 -delete 2>/dev/null || true

echo "Docker cleanup completed successfully"
EOF

    # Update script
    local update_script="/opt/n8n/scripts/update.sh"
    cat > "$update_script" << 'EOF'
#!/bin/bash

# =============================================================================
# n8n Docker Update Script
# =============================================================================

cd /opt/n8n/docker

echo "Starting n8n update process..."

# Pull latest images
echo "Pulling latest Docker images..."
docker-compose pull

# Restart services with new images
echo "Restarting services..."
docker-compose down
docker-compose up -d

# Clean up old images
echo "Cleaning up old images..."
docker image prune -f

echo "n8n update completed successfully"
EOF

    # Service management script
    local service_script="/opt/n8n/scripts/service.sh"
    cat > "$service_script" << 'EOF'
#!/bin/bash

# =============================================================================
# n8n Service Management Script
# =============================================================================

cd /opt/n8n/docker

case "$1" in
    start)
        echo "Starting n8n services..."
        docker-compose up -d
        ;;
    stop)
        echo "Stopping n8n services..."
        docker-compose down
        ;;
    restart)
        echo "Restarting n8n services..."
        docker-compose restart
        ;;
    status)
        echo "n8n service status:"
        docker-compose ps
        ;;
    logs)
        echo "Showing n8n logs..."
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
    
    # Create SSL renewal script
    create_ssl_renewal_script
    
    log_info "Operational scripts created successfully"
    return 0
}

create_systemd_service() {
    log_info "Creating systemd service for n8n..."
    
    local service_file="/etc/systemd/system/n8n-docker.service"
    
    sudo tee "$service_file" > /dev/null << 'EOF'
[Unit]
Description=n8n Docker Compose Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/n8n/docker
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    if execute_silently "sudo systemctl daemon-reload"; then
        log_info "Systemd service created and reloaded"
        
        if execute_silently "sudo systemctl enable n8n-docker.service"; then
            log_info "n8n-docker service enabled for auto-start"
        else
            log_warning "Failed to enable n8n-docker service"
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

setup_docker_infrastructure() {
    log_info "Starting n8n Docker infrastructure setup..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        return 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        return 1
    fi
    
    # Execute setup steps
    create_n8n_directories || return 1
    setup_user_permissions || return 1
    create_docker_compose || return 1
    create_environment_file || return 1
    configure_ssl_certificates || return 1
    create_cleanup_scripts || return 1
    create_systemd_service || return 1
    
    log_info "n8n Docker infrastructure setup completed successfully!"
    log_info "Next steps:"
    log_info "1. Update environment variables in /opt/n8n/docker/.env"
    log_info "2. Start services: sudo systemctl start n8n-docker"
    log_info "3. Check status: /opt/n8n/scripts/service.sh status"
    
    return 0
} 