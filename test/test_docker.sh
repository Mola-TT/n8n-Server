#!/bin/bash

# =============================================================================
# Docker Infrastructure Test Suite - Milestone 2
# =============================================================================
# This script validates the complete n8n Docker infrastructure setup
# including directories, permissions, Docker Compose, Redis, and scripts
# =============================================================================

# Source required libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/utilities.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# Test Helper Functions
# =============================================================================

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    log_info "Running test: $test_name"
    
    if $test_function; then
        ((TESTS_PASSED++))
        log_info "✓ PASSED: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "✗ FAILED: $test_name"
        return 1
    fi
}

# =============================================================================
# Directory Structure Tests
# =============================================================================

test_n8n_directories() {
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
        if [[ ! -d "$dir" ]]; then
            log_error "Directory does not exist: $dir"
            return 1
        fi
    done
    
    return 0
}

test_directory_permissions() {
    local current_user=$(whoami)
    
    # Check ownership
    if [[ $(stat -c '%U' /opt/n8n) != "$current_user" ]]; then
        log_error "/opt/n8n is not owned by $current_user"
        return 1
    fi
    
    # Check if directories are writable
    if [[ ! -w "/opt/n8n/files" ]]; then
        log_error "/opt/n8n/files is not writable"
        return 1
    fi
    
    if [[ ! -w "/opt/n8n/.n8n" ]]; then
        log_error "/opt/n8n/.n8n is not writable"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Docker Configuration Tests
# =============================================================================

test_docker_compose_file() {
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "docker-compose.yml file does not exist"
        return 1
    fi
    
    # Check if file contains required services
    if ! grep -q "services:" "$compose_file"; then
        log_error "docker-compose.yml missing services section"
        return 1
    fi
    
    if ! grep -q "n8n:" "$compose_file"; then
        log_error "docker-compose.yml missing n8n service"
        return 1
    fi
    
    if ! grep -q "redis:" "$compose_file"; then
        log_error "docker-compose.yml missing redis service"
        return 1
    fi
    
    # Check for required configurations
    if ! grep -q "n8nio/n8n:latest" "$compose_file"; then
        log_error "docker-compose.yml missing correct n8n image"
        return 1
    fi
    
    if ! grep -q "5678:5678" "$compose_file"; then
        log_error "docker-compose.yml missing port mapping"
        return 1
    fi
    
    if ! grep -q "depends_on:" "$compose_file"; then
        log_error "docker-compose.yml missing depends_on configuration"
        return 1
    fi
    
    return 0
}

test_environment_file() {
    local env_file="/opt/n8n/docker/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file does not exist"
        return 1
    fi
    
    # Check for required environment variables
    local required_vars=(
        "N8N_HOST"
        "N8N_PORT"
        "N8N_PROTOCOL"
        "TIMEZONE"
        "DB_HOST"
        "DB_PORT"
        "DB_NAME"
        "DB_USER"
        "DB_PASSWORD"
        "REDIS_DB"
    )
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" "$env_file"; then
            log_error "Environment file missing variable: $var"
            return 1
        fi
    done
    
    return 0
}

test_redis_configuration() {
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    
    # Check Redis service configuration
    if ! grep -q "redis:7-alpine" "$compose_file"; then
        log_error "Redis image not configured correctly"
        return 1
    fi
    
    if ! grep -q "redis-server --appendonly yes" "$compose_file"; then
        log_error "Redis persistence not configured"
        return 1
    fi
    
    if ! grep -q "redis-data:" "$compose_file"; then
        log_error "Redis volume not configured"
        return 1
    fi
    
    if ! grep -q "healthcheck:" "$compose_file"; then
        log_error "Redis health check not configured"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Operational Scripts Tests
# =============================================================================

test_operational_scripts() {
    local scripts=(
        "/opt/n8n/scripts/cleanup.sh"
        "/opt/n8n/scripts/update.sh"
        "/opt/n8n/scripts/service.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_error "Script does not exist: $script"
            return 1
        fi
        
        if [[ ! -x "$script" ]]; then
            log_error "Script is not executable: $script"
            return 1
        fi
    done
    
    return 0
}

test_cleanup_script_content() {
    local cleanup_script="/opt/n8n/scripts/cleanup.sh"
    
    if ! grep -q "docker image prune" "$cleanup_script"; then
        log_error "Cleanup script missing image cleanup"
        return 1
    fi
    
    if ! grep -q "docker volume prune" "$cleanup_script"; then
        log_error "Cleanup script missing volume cleanup"
        return 1
    fi
    
    if ! grep -q "find /opt/n8n/logs" "$cleanup_script"; then
        log_error "Cleanup script missing log cleanup"
        return 1
    fi
    
    return 0
}

test_service_script_functionality() {
    local service_script="/opt/n8n/scripts/service.sh"
    
    # Check for required service commands
    local commands=("start" "stop" "restart" "status" "logs")
    
    for cmd in "${commands[@]}"; do
        if ! grep -q "$cmd)" "$service_script"; then
            log_error "Service script missing command: $cmd"
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# System Integration Tests
# =============================================================================

test_systemd_service() {
    local service_file="/etc/systemd/system/n8n-docker.service"
    
    if [[ ! -f "$service_file" ]]; then
        log_error "Systemd service file does not exist"
        return 1
    fi
    
    if ! grep -q "Description=n8n Docker Compose Service" "$service_file"; then
        log_error "Systemd service missing description"
        return 1
    fi
    
    if ! grep -q "docker-compose up -d" "$service_file"; then
        log_error "Systemd service missing start command"
        return 1
    fi
    
    # Check if service is enabled
    if ! systemctl is-enabled n8n-docker.service &>/dev/null; then
        log_warning "n8n-docker service is not enabled (this may be expected)"
    fi
    
    return 0
}

test_docker_installation() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        return 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        return 1
    fi
    
    # Check if Docker service is running
    if ! systemctl is-active docker &>/dev/null; then
        log_warning "Docker service is not running"
    fi
    
    return 0
}

test_user_docker_group() {
    local current_user=$(whoami)
    
    if ! groups "$current_user" | grep -q docker; then
        log_warning "User $current_user is not in docker group (may require logout/login)"
    fi
    
    return 0
}

# =============================================================================
# Volume and Network Tests
# =============================================================================

test_volume_mounts() {
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    
    # Check for required volume mounts
    if ! grep -q "/opt/n8n/files:/data/files" "$compose_file"; then
        log_error "Files volume mount not configured"
        return 1
    fi
    
    if ! grep -q "/opt/n8n/.n8n:/home/node/.n8n" "$compose_file"; then
        log_error "n8n home volume mount not configured"
        return 1
    fi
    
    if ! grep -q "redis-data:/data" "$compose_file"; then
        log_error "Redis data volume not configured"
        return 1
    fi
    
    return 0
}

test_network_configuration() {
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    
    if ! grep -q "networks:" "$compose_file"; then
        log_error "Networks section not found"
        return 1
    fi
    
    if ! grep -q "n8n-network:" "$compose_file"; then
        log_error "n8n-network not configured"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Environment Variable Tests
# =============================================================================

test_postgresql_variables() {
    local env_file="/opt/n8n/docker/.env"
    
    local pg_vars=("DB_HOST" "DB_PORT" "DB_NAME" "DB_USER" "DB_PASSWORD")
    
    for var in "${pg_vars[@]}"; do
        if ! grep -q "^$var=" "$env_file"; then
            log_error "PostgreSQL variable missing: $var"
            return 1
        fi
    done
    
    return 0
}

test_ssl_configuration() {
    local env_file="/opt/n8n/docker/.env"
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    local ssl_dir="/opt/n8n/ssl"
    
    # Check SSL environment variables
    if ! grep -q "N8N_SSL_KEY=" "$env_file"; then
        log_error "N8N_SSL_KEY variable not found in environment file"
        return 1
    fi
    
    if ! grep -q "N8N_SSL_CERT=" "$env_file"; then
        log_error "N8N_SSL_CERT variable not found in environment file"
        return 1
    fi
    
    # Check SSL volume mount in docker-compose
    if ! grep -q "/opt/n8n/ssl:/opt/ssl:ro" "$compose_file"; then
        log_error "SSL volume mount not configured in docker-compose"
        return 1
    fi
    
    # Check SSL directory exists
    if [[ ! -d "$ssl_dir" ]]; then
        log_error "SSL directory does not exist: $ssl_dir"
        return 1
    fi
    
    # Check for SSL renewal script
    if [[ ! -f "/opt/n8n/scripts/ssl-renew.sh" ]]; then
        log_error "SSL renewal script does not exist"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/ssl-renew.sh" ]]; then
        log_error "SSL renewal script is not executable"
        return 1
    fi
    
    return 0
}

test_ssl_certificates() {
    local ssl_dir="/opt/n8n/ssl"
    local private_key="$ssl_dir/private.key"
    local certificate="$ssl_dir/certificate.crt"
    
    # Check if SSL files exist (they should after setup)
    if [[ -f "$private_key" ]]; then
        # Check private key permissions
        local key_perms=$(stat -c "%a" "$private_key")
        if [[ "$key_perms" != "600" ]]; then
            log_warning "Private key permissions should be 600, found: $key_perms"
        fi
        
        # Validate private key format
        if ! openssl rsa -in "$private_key" -check -noout &>/dev/null; then
            log_error "Invalid private key format"
            return 1
        fi
    fi
    
    if [[ -f "$certificate" ]]; then
        # Check certificate permissions
        local cert_perms=$(stat -c "%a" "$certificate")
        if [[ "$cert_perms" != "644" ]]; then
            log_warning "Certificate permissions should be 644, found: $cert_perms"
        fi
        
        # Validate certificate format
        if ! openssl x509 -in "$certificate" -text -noout &>/dev/null; then
            log_error "Invalid certificate format"
            return 1
        fi
        
        # Check certificate expiry
        local expiry_date=$(openssl x509 -in "$certificate" -noout -enddate | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_until_expiry -lt 30 ]]; then
            log_warning "SSL certificate expires in $days_until_expiry days"
        fi
    fi
    
    return 0
}

test_timezone_configuration() {
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    local env_file="/opt/n8n/docker/.env"
    
    # Check timezone in environment file
    if ! grep -q "TIMEZONE=" "$env_file"; then
        log_error "TIMEZONE variable not found in environment file"
        return 1
    fi
    
    # Check timezone variables in docker-compose
    if ! grep -q "GENERIC_TIMEZONE=\${TIMEZONE}" "$compose_file"; then
        log_error "GENERIC_TIMEZONE not configured in docker-compose"
        return 1
    fi
    
    if ! grep -q "TZ=\${TIMEZONE}" "$compose_file"; then
        log_error "TZ variable not configured in docker-compose"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_all_tests() {
    log_info "Starting n8n Docker Infrastructure Test Suite..."
    log_info "=================================================="
    
    # Directory and Permission Tests
    run_test "n8n Directory Structure" test_n8n_directories
    run_test "Directory Permissions" test_directory_permissions
    
    # Docker Configuration Tests
    run_test "Docker Compose File" test_docker_compose_file
    run_test "Environment File" test_environment_file
    run_test "Redis Configuration" test_redis_configuration
    
    # Operational Scripts Tests
    run_test "Operational Scripts Existence" test_operational_scripts
    run_test "Cleanup Script Content" test_cleanup_script_content
    run_test "Service Script Functionality" test_service_script_functionality
    
    # System Integration Tests
    run_test "Systemd Service" test_systemd_service
    run_test "Docker Installation" test_docker_installation
    run_test "User Docker Group" test_user_docker_group
    
    # Volume and Network Tests
    run_test "Volume Mounts" test_volume_mounts
    run_test "Network Configuration" test_network_configuration
    
    # Environment Variable Tests
    run_test "PostgreSQL Variables" test_postgresql_variables
    run_test "SSL Configuration" test_ssl_configuration
    run_test "SSL Certificates" test_ssl_certificates
    run_test "Timezone Configuration" test_timezone_configuration
    
    # Test Summary
    log_info "=================================================="
    log_info "Test Summary:"
    log_info "Tests Run: $TESTS_RUN"
    log_info "Tests Passed: $TESTS_PASSED"
    log_info "Tests Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "🎉 All tests passed! n8n Docker infrastructure is ready."
        return 0
    else
        log_error "❌ $TESTS_FAILED test(s) failed. Please review the issues above."
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi 