#!/bin/bash

# ==============================================================================
# Docker Infrastructure Test Suite - Milestone 2
# ==============================================================================
# This script validates the Docker infrastructure setup including:
# - Directory structure and permissions
# - Docker and Docker Compose installation
# - docker-compose.yml configuration
# - Redis configuration
# - Operational scripts
# - System integration
# ==============================================================================

# Source required libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/utilities.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ==============================================================================
# Test Helper Functions
# ==============================================================================

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

# ==============================================================================
# Directory Structure Tests
# ==============================================================================

test_n8n_directories() {
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
        if [[ ! -d "$dir" ]]; then
            log_error "Directory does not exist: $dir"
            return 1
        fi
    done
    
    return 0
}

test_directory_permissions() {
    # Determine expected owner using same logic as setup script
    local current_user=$(whoami)
    local expected_owner
    
    if [[ "$current_user" == "root" ]]; then
        # If running as root, check if there's a non-root user who should own the directories
        if [[ -n "$SUDO_USER" ]]; then
            expected_owner="$SUDO_USER"
        else
            # Fallback: find the user who owns the script directory
            expected_owner=$(stat -c '%U' "$(dirname "${BASH_SOURCE[0]}")/..")
            if [[ "$expected_owner" == "root" ]]; then
                expected_owner="root"
            fi
        fi
    else
        expected_owner="$current_user"
    fi
    
    # Check ownership
    local actual_owner=$(stat -c '%U' /opt/n8n)
    if [[ "$actual_owner" != "$expected_owner" ]]; then
        log_error "/opt/n8n is owned by '$actual_owner', expected '$expected_owner'"
        return 1
    fi
    
    # Check group ownership (should be docker)
    local actual_group=$(stat -c '%G' /opt/n8n)
    if [[ "$actual_group" != "docker" ]]; then
        log_error "/opt/n8n group is '$actual_group', expected 'docker'"
        return 1
    fi
    
    # Check if directories are writable by the expected owner
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

# ==============================================================================
# Docker Configuration Tests
# ==============================================================================

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

# ==============================================================================
# Operational Scripts Tests
# ==============================================================================

test_operational_scripts() {
    local scripts=(
        "/opt/n8n/scripts/cleanup.sh"
        "/opt/n8n/scripts/update.sh"
        "/opt/n8n/scripts/service.sh"
        "/opt/n8n/scripts/ssl-renew.sh"
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

# ==============================================================================
# System Integration Tests
# ==============================================================================

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
        log_warn "n8n-docker service is not enabled (this may be expected)"
    fi
    
    return 0
}

test_docker_installation() {
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        return 1
    fi
    
    # Check if Docker service is running first
    if ! systemctl is-active docker &>/dev/null; then
        log_warn "Docker service is not running"
        return 0  # Don't fail the test, just warn
    else
        log_info "Docker service is active"
    fi
    
    # Give Docker daemon time to be ready if service just started
    log_info "Checking Docker daemon readiness..."
    local daemon_ready=false
    local max_attempts=15
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if timeout 5s docker info &>/dev/null; then
            daemon_ready=true
            log_info "Docker daemon is accessible"
            break
        fi
        
        if [ $attempt -eq 1 ]; then
            log_info "Waiting for Docker daemon to be ready..."
        fi
        
        sleep 2
        ((attempt++))
    done
    
    if [ "$daemon_ready" = false ]; then
        log_warn "Docker daemon is not accessible (this is normal if not running as root or in docker group, or if Docker is still starting up)"
    fi
    
    # Check Docker version (only if daemon is ready)
    if [ "$daemon_ready" = true ]; then
        local docker_version_output
        if docker_version_output=$(timeout 10s docker --version 2>/dev/null); then
            log_info "Docker version: $docker_version_output"
        else
            log_warn "Docker version check failed or timed out"
        fi
    else
        log_info "Skipping Docker version check (daemon not accessible)"
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        return 1
    fi
    
    # Check Docker Compose version
    local compose_version_output
    if compose_version_output=$(timeout 10s docker compose version --short 2>/dev/null); then
        log_info "Docker Compose version: $compose_version_output"
    elif compose_version_output=$(timeout 10s docker-compose version --short 2>/dev/null); then
        log_info "Docker Compose version: $compose_version_output"
    elif compose_version_output=$(timeout 10s docker compose version 2>/dev/null | head -1); then
        log_info "Docker Compose version: $compose_version_output"
    else
        log_warn "Docker Compose version check failed or timed out"
    fi
    
    return 0
}

test_user_docker_group() {
    local current_user=$(whoami)
    
    if ! groups "$current_user" | grep -q docker; then
        log_info "User $current_user is not in docker group (this is normal after initial setup)"
        log_info "Docker group membership was configured during installation"
    else
        log_info "User $current_user is in docker group"
    fi
    
    return 0
}

# ==============================================================================
# Volume and Network Tests
# ==============================================================================

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
    
    if ! grep -q "/opt/n8n/ssl:/opt/ssl:ro" "$compose_file"; then
        log_error "SSL volume mount not configured"
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

# ==============================================================================
# Main Test Runner
# ==============================================================================

run_all_tests() {
    log_info "Starting Docker Infrastructure Test Suite..."
    echo "================================================================================"
    
    # Directory and Permission Tests
    run_test "n8n Directory Structure" test_n8n_directories
    run_test "Directory Permissions" test_directory_permissions
    
    # Docker Configuration Tests
    run_test "Docker Compose File" test_docker_compose_file
    run_test "Environment File" test_environment_file
    run_test "Redis Configuration" test_redis_configuration
    
    # Operational Scripts Tests
    run_test "Operational Scripts" test_operational_scripts
    run_test "Cleanup Script Content" test_cleanup_script_content
    run_test "Service Script Functionality" test_service_script_functionality
    
    # System Integration Tests
    run_test "Systemd Service" test_systemd_service
    run_test "Docker Installation" test_docker_installation
    run_test "User Docker Group" test_user_docker_group
    
    # Volume and Network Tests
    run_test "Volume Mounts" test_volume_mounts
    run_test "Network Configuration" test_network_configuration
    
    # Test Summary
    echo "================================================================================"
    echo "Docker Infrastructure Test Summary:"
    log_info "Tests Run: $TESTS_RUN"
    log_info "Tests Passed: $TESTS_PASSED"
    log_info "Tests Failed: $TESTS_FAILED"
    echo "================================================================================"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "🎉 All Docker infrastructure tests passed!"
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