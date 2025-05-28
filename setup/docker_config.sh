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
    create_cleanup_scripts || return 1
    create_systemd_service || return 1
    
    log_info "n8n Docker infrastructure setup completed successfully!"
    log_info "Next steps:"
    log_info "1. Update environment variables in /opt/n8n/docker/.env"
    log_info "2. Start services: sudo systemctl start n8n-docker"
    log_info "3. Check status: /opt/n8n/scripts/service.sh status"
    
    return 0
} 