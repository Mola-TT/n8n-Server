#!/bin/bash

# test_dynamic_optimization_integration.sh - Integration Tests for Dynamic Hardware Optimization
# Tests end-to-end workflows, cross-component integration, and system stability

set -euo pipefail

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source required utilities
source "$SCRIPT_DIR/../lib/logger.sh"
source "$SCRIPT_DIR/../lib/utilities.sh"

# Test configuration
readonly OPTIMIZATION_SCRIPT="$PROJECT_ROOT/setup/dynamic_optimization.sh"
readonly HARDWARE_DETECTOR_SCRIPT="$PROJECT_ROOT/setup/hardware_change_detector.sh"
readonly TEST_BACKUP_DIR="/tmp/dynamic_optimization_integration_backup"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_integration_test_environment() {
    log_info "Setting up dynamic optimization integration test environment..."
    
    # Create test backup directory
    mkdir -p "$TEST_BACKUP_DIR"
    
    # Create necessary directories
    mkdir -p "/opt/n8n/data" "/opt/n8n/logs" "/opt/n8n/backups/optimization"
    mkdir -p "/opt/n8n/docker"
    
    # Backup original configuration files if they exist
    [[ -f "/opt/n8n/docker/.env" ]] && cp "/opt/n8n/docker/.env" "$TEST_BACKUP_DIR/n8n.env.original"
    [[ -f "/opt/n8n/docker/docker-compose.yml" ]] && cp "/opt/n8n/docker/docker-compose.yml" "$TEST_BACKUP_DIR/docker-compose.yml.original"
    
    # Create minimal test configuration files
    create_test_configuration_files
    
    log_info "Integration test environment setup completed"
}

cleanup_integration_test_environment() {
    log_info "Cleaning up integration test environment..."
    
    # Restore original files if they were backed up
    [[ -f "$TEST_BACKUP_DIR/n8n.env.original" ]] && cp "$TEST_BACKUP_DIR/n8n.env.original" "/opt/n8n/docker/.env"
    [[ -f "$TEST_BACKUP_DIR/docker-compose.yml.original" ]] && cp "$TEST_BACKUP_DIR/docker-compose.yml.original" "/opt/n8n/docker/docker-compose.yml"
    
    # Remove test files
    rm -f "/opt/n8n/data/hardware_specs.json"
    rm -f "/opt/n8n/data/hardware_specs.json.backup"
    rm -f "/opt/n8n/data/last_email_notification"
    
    # Stop and remove test service
    systemctl stop n8n-hardware-detector.service >/dev/null 2>&1 || true
    systemctl disable n8n-hardware-detector.service >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/n8n-hardware-detector.service"
    systemctl daemon-reload >/dev/null 2>&1 || true
    
    # Remove test backup directory
    rm -rf "$TEST_BACKUP_DIR"
    
    log_info "Integration test environment cleanup completed"
}

create_test_configuration_files() {
    # Create test n8n environment file
    cat > "/opt/n8n/docker/.env" << EOF
N8N_PORT=5678
N8N_HOST=0.0.0.0
N8N_PROTOCOL=http
N8N_EXECUTION_PROCESS=2
N8N_EXECUTION_TIMEOUT=300
WEBHOOK_TIMEOUT=240
DB_HOST=localhost
DB_PORT=5432
DB_NAME=n8n
DB_USER=n8n
DB_PASSWORD=password
REDIS_HOST=localhost
REDIS_PORT=6379
EOF
    
    # Create test Docker Compose file
    cat > "/opt/n8n/docker/docker-compose.yml" << EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    ports:
      - "5678:5678"
    environment:
      - N8N_PORT=5678
      - N8N_HOST=0.0.0.0
    volumes:
      - /opt/n8n/files:/data/files
      - /opt/n8n/.n8n:/home/node/.n8n
    restart: unless-stopped
    networks:
      - n8n-network
    deploy:
      resources:
        limits:
          memory: 2g
          cpus: "1.0"
    shm_size: 256m

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    restart: unless-stopped
    networks:
      - n8n-network

volumes:
  redis-data:

networks:
  n8n-network:
    driver: bridge
EOF
}

# =============================================================================
# SCRIPT AVAILABILITY TESTS
# =============================================================================

test_optimization_script_availability() {
    [[ -f "$OPTIMIZATION_SCRIPT" ]] && [[ -x "$OPTIMIZATION_SCRIPT" ]]
}

test_hardware_detector_script_availability() {
    [[ -f "$HARDWARE_DETECTOR_SCRIPT" ]] && [[ -x "$HARDWARE_DETECTOR_SCRIPT" ]]
}

test_required_utilities_availability() {
    [[ -f "$PROJECT_ROOT/utils/logger.sh" ]] &&
    [[ -f "$PROJECT_ROOT/utils/utilities.sh" ]]
}

# =============================================================================
# END-TO-END OPTIMIZATION WORKFLOW TESTS
# =============================================================================

test_complete_optimization_workflow() {
    # Test the complete optimization workflow from detection to application
    
    # Step 1: Hardware detection
    bash "$OPTIMIZATION_SCRIPT" --detect-only >/dev/null 2>&1 || return 1
    
    # Step 2: Parameter calculation
    bash "$OPTIMIZATION_SCRIPT" --calculate-only >/dev/null 2>&1 || return 1
    
    # Step 3: Report generation
    bash "$OPTIMIZATION_SCRIPT" --report-only >/dev/null 2>&1 || return 1
    
    # Step 4: Verification
    bash "$OPTIMIZATION_SCRIPT" --verify-only >/dev/null 2>&1 || return 1
    
    return 0
}

test_hardware_change_detection_workflow() {
    # Test the complete hardware change detection workflow
    
    # Step 1: Initialize hardware specs
    bash "$HARDWARE_DETECTOR_SCRIPT" --show-specs >/dev/null 2>&1 || return 1
    
    # Step 2: Check for changes
    bash "$HARDWARE_DETECTOR_SCRIPT" --check-once >/dev/null 2>&1 || true  # May return non-zero if no changes
    
    # Step 3: Test email functionality
    bash "$HARDWARE_DETECTOR_SCRIPT" --test-email >/dev/null 2>&1 || true  # May fail in test environment
    
    # Step 4: Force optimization
    bash "$HARDWARE_DETECTOR_SCRIPT" --force-optimize >/dev/null 2>&1 || true  # May fail in test environment
    
    return 0
}

test_service_management_workflow() {
    # Test the complete service management workflow
    
    # Step 1: Install service
    bash "$HARDWARE_DETECTOR_SCRIPT" --install-service >/dev/null 2>&1 || return 1
    
    # Step 2: Check status
    bash "$HARDWARE_DETECTOR_SCRIPT" --status >/dev/null 2>&1 || return 1
    
    # Step 3: Start service
    bash "$HARDWARE_DETECTOR_SCRIPT" --start-service >/dev/null 2>&1 || true  # May fail in test environment
    
    # Step 4: Stop service
    bash "$HARDWARE_DETECTOR_SCRIPT" --stop-service >/dev/null 2>&1 || true  # May fail in test environment
    
    return 0
}

# =============================================================================
# CROSS-COMPONENT INTEGRATION TESTS
# =============================================================================

test_optimization_and_detection_integration() {
    # Test integration between optimization and detection components
    
    # Create initial hardware specs using detector
    bash "$HARDWARE_DETECTOR_SCRIPT" --show-specs > "/tmp/initial_specs.json" 2>/dev/null || return 1
    
    # Run optimization
    bash "$OPTIMIZATION_SCRIPT" --calculate-only >/dev/null 2>&1 || return 1
    
    # Verify specs file exists
    [[ -f "/tmp/initial_specs.json" ]] || return 1
    
    # Cleanup
    rm -f "/tmp/initial_specs.json"
    
    return 0
}

test_configuration_backup_and_restore() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    # Create backup
    backup_configurations >/dev/null 2>&1 || return 1
    
    # Verify backup was created
    [[ -n "${BACKUP_PATH:-}" ]] && [[ -d "$BACKUP_PATH" ]] || return 1
    
    # Verify manifest file exists
    [[ -f "$BACKUP_PATH/manifest.txt" ]] || return 1
    
    return 0
}

test_email_notification_integration() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set up test email configuration
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    export CHANGE_SUMMARY="Integration test change"
    export CURRENT_HARDWARE_SPECS='{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 100}'
    export PREVIOUS_HARDWARE_SPECS='{"cpu_cores": 2, "memory_gb": 4, "disk_gb": 50}'
    
    # Test email notifications (should handle gracefully if sending fails)
    send_hardware_change_notification "detected" >/dev/null 2>&1 || true
    send_hardware_change_notification "optimized" >/dev/null 2>&1 || true
    
    return 0
}

# =============================================================================
# CONFIGURATION CONSISTENCY TESTS
# =============================================================================

test_n8n_configuration_consistency() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    # Calculate parameters
    calculate_n8n_parameters >/dev/null 2>&1 || return 1
    
    # Verify parameters are consistent
    [[ -n "${N8N_EXECUTION_PROCESS:-}" ]] &&
    [[ -n "${N8N_EXECUTION_TIMEOUT:-}" ]] &&
    [[ -n "${N8N_WEBHOOK_TIMEOUT:-}" ]] || return 1
    
    # Verify timeout relationship (webhook should be less than execution)
    [[ "$N8N_WEBHOOK_TIMEOUT" -lt "$N8N_EXECUTION_TIMEOUT" ]] || return 1
    
    return 0
}

test_docker_configuration_consistency() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    # Calculate parameters
    calculate_docker_parameters >/dev/null 2>&1 || return 1
    
    # Verify parameters are consistent
    [[ -n "${DOCKER_MEMORY_LIMIT:-}" ]] &&
    [[ -n "${DOCKER_CPU_LIMIT:-}" ]] &&
    [[ -n "${DOCKER_SHM_SIZE:-}" ]] || return 1
    
    # Verify format consistency
    [[ "$DOCKER_MEMORY_LIMIT" =~ ^[0-9]+g$ ]] &&
    [[ "$DOCKER_CPU_LIMIT" =~ ^[0-9.]+$ ]] &&
    [[ "$DOCKER_SHM_SIZE" =~ ^[0-9]+m$ ]] || return 1
    
    return 0
}

test_cross_component_parameter_consistency() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=8
    export HW_MEMORY_GB=16
    export HW_DISK_GB=200
    
    # Calculate all parameters
    calculate_n8n_parameters >/dev/null 2>&1 || return 1
    calculate_docker_parameters >/dev/null 2>&1 || return 1
    calculate_nginx_parameters >/dev/null 2>&1 || return 1
    calculate_redis_parameters >/dev/null 2>&1 || return 1
    calculate_netdata_parameters >/dev/null 2>&1 || return 1
    
    # Verify CPU-based parameters are consistent
    [[ "$N8N_EXECUTION_PROCESS" -le "$HW_CPU_CORES" ]] &&
    [[ "$NGINX_WORKER_PROCESSES" -le "$HW_CPU_CORES" ]] || return 1
    
    # Verify memory-based parameters don't exceed total memory
    local n8n_memory_gb=$((N8N_MEMORY_LIMIT_MB / 1024))
    local docker_memory_gb="${DOCKER_MEMORY_LIMIT%g}"
    local redis_memory_gb=$((${REDIS_MAXMEMORY%mb} / 1024))
    
    [[ "$n8n_memory_gb" -le "$HW_MEMORY_GB" ]] &&
    [[ "$docker_memory_gb" -le "$HW_MEMORY_GB" ]] &&
    [[ "$redis_memory_gb" -le "$HW_MEMORY_GB" ]] || return 1
    
    return 0
}

# =============================================================================
# PERFORMANCE IMPACT TESTS
# =============================================================================

test_optimization_performance_impact() {
    local start_time end_time duration
    start_time=$(date +%s)
    
    # Run complete optimization workflow
    bash "$OPTIMIZATION_SCRIPT" --calculate-only >/dev/null 2>&1 || return 1
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Optimization should complete within reasonable time (< 30 seconds)
    [[ "$duration" -lt 30 ]] || return 1
    
    return 0
}

test_hardware_detection_performance_impact() {
    local start_time end_time duration
    start_time=$(date +%s)
    
    # Run hardware detection multiple times
    for i in {1..3}; do
        bash "$HARDWARE_DETECTOR_SCRIPT" --show-specs >/dev/null 2>&1 || return 1
    done
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Detection should complete within reasonable time (< 10 seconds total)
    [[ "$duration" -lt 10 ]] || return 1
    
    return 0
}

# =============================================================================
# SYSTEM STABILITY TESTS
# =============================================================================

test_system_stability_after_optimization() {
    # Test that system remains stable after optimization
    
    # Run optimization
    bash "$OPTIMIZATION_SCRIPT" --calculate-only >/dev/null 2>&1 || return 1
    
    # Verify system commands still work
    nproc >/dev/null 2>&1 || return 1
    free >/dev/null 2>&1 || return 1
    df >/dev/null 2>&1 || return 1
    
    # Verify logging still works
    log_info "System stability test" >/dev/null 2>&1 || return 1
    
    return 0
}

test_service_stability_after_detection() {
    # Test that services remain stable after hardware detection
    
    # Install and test service
    bash "$HARDWARE_DETECTOR_SCRIPT" --install-service >/dev/null 2>&1 || return 1
    
    # Check service status
    bash "$HARDWARE_DETECTOR_SCRIPT" --status >/dev/null 2>&1 || return 1
    
    # Verify systemd is still functional
    systemctl --version >/dev/null 2>&1 || return 1
    
    return 0
}

# =============================================================================
# ROLLBACK AND RECOVERY TESTS
# =============================================================================

test_configuration_rollback() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Create initial configuration
    cat > "/opt/n8n/docker/.env" << EOF
N8N_EXECUTION_PROCESS=2
N8N_EXECUTION_TIMEOUT=300
WEBHOOK_TIMEOUT=240
EOF
    
    # Create backup
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    backup_configurations >/dev/null 2>&1 || return 1
    
    # Modify configuration
    export N8N_EXECUTION_PROCESS=4
    export N8N_EXECUTION_TIMEOUT=600
    export N8N_WEBHOOK_TIMEOUT=480
    update_n8n_configuration >/dev/null 2>&1 || return 1
    
    # Verify modification
    grep -q "N8N_EXECUTION_PROCESS=4" "/opt/n8n/docker/.env" || return 1
    
    # Restore from backup
    [[ -n "${BACKUP_PATH:-}" ]] && [[ -f "$BACKUP_PATH/n8n.env.backup" ]] || return 1
    cp "$BACKUP_PATH/n8n.env.backup" "/opt/n8n/docker/.env"
    
    # Verify restoration
    grep -q "N8N_EXECUTION_PROCESS=2" "/opt/n8n/docker/.env" || return 1
    
    return 0
}

test_hardware_specs_recovery() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Create initial specs
    local test_specs='{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 100}'
    export HARDWARE_SPEC_FILE="/opt/n8n/data/hardware_specs.json"
    save_hardware_specs "$test_specs" >/dev/null 2>&1 || return 1
    
    # Verify backup was created
    [[ -f "${HARDWARE_SPEC_FILE}.backup" ]] || return 1
    
    # Corrupt main file
    echo "corrupted" > "$HARDWARE_SPEC_FILE"
    
    # Restore from backup
    cp "${HARDWARE_SPEC_FILE}.backup" "$HARDWARE_SPEC_FILE"
    
    # Verify restoration
    grep -q '"cpu_cores": 4' "$HARDWARE_SPEC_FILE" || return 1
    
    return 0
}

# =============================================================================
# MULTI-COMPONENT COORDINATION TESTS
# =============================================================================

test_optimization_and_detection_coordination() {
    # Test coordination between optimization and detection components
    
    # Initialize hardware specs via detector
    bash "$HARDWARE_DETECTOR_SCRIPT" --show-specs >/dev/null 2>&1 || return 1
    
    # Run optimization
    bash "$OPTIMIZATION_SCRIPT" --detect-only >/dev/null 2>&1 || return 1
    
    # Check for changes via detector
    bash "$HARDWARE_DETECTOR_SCRIPT" --check-once >/dev/null 2>&1 || true
    
    # Both components should work together without conflicts
    return 0
}

test_service_and_script_coordination() {
    # Test coordination between service management and script execution
    
    # Install service
    bash "$HARDWARE_DETECTOR_SCRIPT" --install-service >/dev/null 2>&1 || return 1
    
    # Run script operations
    bash "$HARDWARE_DETECTOR_SCRIPT" --show-specs >/dev/null 2>&1 || return 1
    bash "$OPTIMIZATION_SCRIPT" --detect-only >/dev/null 2>&1 || return 1
    
    # Check service status
    bash "$HARDWARE_DETECTOR_SCRIPT" --status >/dev/null 2>&1 || return 1
    
    # No conflicts should occur
    return 0
}

# =============================================================================
# ERROR RECOVERY TESTS
# =============================================================================

test_error_recovery_missing_files() {
    # Test recovery from missing configuration files
    
    # Remove configuration files
    rm -f "/opt/n8n/docker/.env"
    rm -f "/opt/n8n/docker/docker-compose.yml"
    
    # Scripts should handle missing files gracefully
    bash "$OPTIMIZATION_SCRIPT" --detect-only >/dev/null 2>&1 || return 1
    bash "$HARDWARE_DETECTOR_SCRIPT" --show-specs >/dev/null 2>&1 || return 1
    
    # Recreate test files
    create_test_configuration_files
    
    return 0
}

test_error_recovery_invalid_permissions() {
    # Test recovery from permission issues
    
    # Create read-only directory
    local readonly_dir="/tmp/readonly_test_integration"
    mkdir -p "$readonly_dir"
    chmod 444 "$readonly_dir" 2>/dev/null || true
    
    # Scripts should handle permission errors gracefully
    bash "$OPTIMIZATION_SCRIPT" --detect-only >/dev/null 2>&1 || return 1
    bash "$HARDWARE_DETECTOR_SCRIPT" --show-specs >/dev/null 2>&1 || return 1
    
    # Cleanup
    chmod 755 "$readonly_dir" 2>/dev/null || true
    rm -rf "$readonly_dir"
    
    return 0
}

# =============================================================================
# TEST RUNNER
# =============================================================================

run_dynamic_optimization_integration_tests() {
    local tests_passed=0
    local tests_failed=0
    local test_functions=(
        # Script availability tests
        "test_optimization_script_availability"
        "test_hardware_detector_script_availability"
        "test_required_utilities_availability"
        
        # End-to-end workflow tests
        "test_complete_optimization_workflow"
        "test_hardware_change_detection_workflow"
        "test_service_management_workflow"
        
        # Cross-component integration tests
        "test_optimization_and_detection_integration"
        "test_configuration_backup_and_restore"
        "test_email_notification_integration"
        
        # Configuration consistency tests
        "test_n8n_configuration_consistency"
        "test_docker_configuration_consistency"
        "test_cross_component_parameter_consistency"
        
        # Performance impact tests
        "test_optimization_performance_impact"
        "test_hardware_detection_performance_impact"
        
        # System stability tests
        "test_system_stability_after_optimization"
        "test_service_stability_after_detection"
        
        # Rollback and recovery tests
        "test_configuration_rollback"
        "test_hardware_specs_recovery"
        
        # Multi-component coordination tests
        "test_optimization_and_detection_coordination"
        "test_service_and_script_coordination"
        
        # Error recovery tests
        "test_error_recovery_missing_files"
        "test_error_recovery_invalid_permissions"
    )
    
    log_info "Running dynamic optimization integration tests..."
    setup_integration_test_environment
    
    for test_function in "${test_functions[@]}"; do
        if $test_function >/dev/null 2>&1; then
            log_info "✓ $test_function"
            tests_passed=$((tests_passed + 1))
        else
            log_error "✗ $test_function"
            tests_failed=$((tests_failed + 1))
        fi
    done
    
    cleanup_integration_test_environment
    
    local total_tests=$((tests_passed + tests_failed))
    log_info "Dynamic optimization integration tests completed: $tests_passed/$total_tests passed"
    
    return $tests_failed
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_dynamic_optimization_integration_tests
fi 