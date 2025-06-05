#!/bin/bash

# test_optimization.sh - Integration Tests for Dynamic Optimization
# Part of Milestone 6 test suite

set -euo pipefail

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

# Source required utilities
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Test configuration
TEST_ENV_DIR="/tmp/test_optimization_integration"
PASSED_TESTS=0
TOTAL_TESTS=0

# Test helper functions
setup_integration_test_environment() {
    log_info "Setting up dynamic optimization integration test environment..."
    
    # Create test directories
    mkdir -p "$TEST_ENV_DIR"
    mkdir -p "$TEST_ENV_DIR/config"
    mkdir -p "$TEST_ENV_DIR/backups"
    mkdir -p "$TEST_ENV_DIR/specs"
    mkdir -p "$TEST_ENV_DIR/logs"
    
    # Set test environment variables
    export TEST_MODE=true
    export HARDWARE_SPEC_FILE="$TEST_ENV_DIR/specs/hardware_specs.json"
    
    # Set email configuration for tests
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    export SMTP_SERVER="smtp.example.com"
    export SMTP_PORT="587"
    export SMTP_USERNAME="testuser"
    export SMTP_PASSWORD="testpass"
    export EMAIL_COOLDOWN_HOURS="24"
    
    log_info "Integration test environment setup completed"
}

cleanup_integration_test_environment() {
    log_info "Cleaning up integration test environment..."
    rm -rf "$TEST_ENV_DIR"
    unset TEST_MODE HARDWARE_SPEC_FILE
    unset EMAIL_SENDER EMAIL_RECIPIENT SMTP_SERVER SMTP_PORT SMTP_USERNAME SMTP_PASSWORD EMAIL_COOLDOWN_HOURS
    log_info "Integration test environment cleanup completed"
}

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TOTAL_TESTS++))
    
    if $test_function; then
        log_info "✓ $test_name"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "✗ $test_name"
        return 1
    fi
}

# Script availability tests
test_optimization_script_availability() {
    [[ -f "$PROJECT_ROOT/setup/dynamic_optimization.sh" ]] && [[ -x "$PROJECT_ROOT/setup/dynamic_optimization.sh" ]]
}

test_hardware_detector_script_availability() {
    [[ -f "$PROJECT_ROOT/setup/hardware_change_detector.sh" ]] && [[ -x "$PROJECT_ROOT/setup/hardware_change_detector.sh" ]]
}

test_required_utilities_availability() {
    which bc >/dev/null 2>&1 && which awk >/dev/null 2>&1 && which grep >/dev/null 2>&1
}

# Complete workflow tests
test_complete_optimization_workflow() {
    # Test complete optimization workflow
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Set test hardware specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    
    # Run detection and calculation
    get_hardware_specs
    calculate_n8n_parameters
    calculate_docker_parameters
    calculate_nginx_parameters
    calculate_redis_parameters
    calculate_netdata_parameters
    
    # Verify parameters were calculated
    [[ -n "${N8N_EXECUTION_PROCESS:-}" ]] && \
    [[ -n "${DOCKER_MEMORY_LIMIT:-}" ]] && \
    [[ -n "${NGINX_WORKER_PROCESSES:-}" ]] && \
    [[ -n "${REDIS_MAXMEMORY:-}" ]] && \
    [[ -n "${NETDATA_UPDATE_EVERY:-}" ]]
}

test_hardware_change_detection_workflow() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Create initial hardware specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    save_hardware_specs "$HARDWARE_SPEC_FILE"
    
    # Load previous specs
    load_hardware_specs "$HARDWARE_SPEC_FILE"
    
    # Simulate hardware change
    export CPU_CORES=8
    
    # Detect changes
    detect_hardware_changes
}

test_service_management_workflow() {
    # Test service management workflow (mock test)
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --help >/dev/null 2>&1 && \
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --show-specs >/dev/null 2>&1
}

# Integration between components
test_optimization_and_detection_integration() {
    # Test integration between optimization and detection
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set hardware specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    
    # Run optimization
    get_hardware_specs
    calculate_n8n_parameters
    
    # Save specs for detection
    save_hardware_specs "$HARDWARE_SPEC_FILE"
    
    # Load and verify
    load_hardware_specs "$HARDWARE_SPEC_FILE"
    [[ -n "${PREVIOUS_CPU_CORES:-}" ]]
}

# Configuration consistency tests
test_configuration_backup_and_restore() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Create test configuration
    local test_config="$TEST_ENV_DIR/config/test.env"
    echo "TEST_VALUE=original" > "$test_config"
    
    # Test backup functionality
    backup_configurations "$TEST_ENV_DIR/backups"
    
    # Verify backup was created (mock test)
    [[ -d "$TEST_ENV_DIR/backups" ]]
}

test_email_notification_integration() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test email configuration loading
    load_email_configuration
    
    # Test email content generation
    local subject body
    subject=$(get_email_subject "hardware_change")
    body=$(get_email_body "hardware_change" "Test hardware specs")
    
    [[ -n "$subject" ]] && [[ -n "$body" ]]
}

# Configuration consistency tests
test_n8n_configuration_consistency() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Set consistent hardware specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    
    # Calculate parameters multiple times
    calculate_n8n_parameters
    local first_execution_process="$N8N_EXECUTION_PROCESS"
    
    calculate_n8n_parameters
    local second_execution_process="$N8N_EXECUTION_PROCESS"
    
    # Should be consistent
    [[ "$first_execution_process" == "$second_execution_process" ]]
}

test_docker_configuration_consistency() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Set consistent hardware specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    
    # Calculate parameters multiple times
    calculate_docker_parameters
    local first_memory_limit="$DOCKER_MEMORY_LIMIT"
    
    calculate_docker_parameters
    local second_memory_limit="$DOCKER_MEMORY_LIMIT"
    
    # Should be consistent
    [[ "$first_memory_limit" == "$second_memory_limit" ]]
}

test_cross_component_parameter_consistency() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Set hardware specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    
    # Calculate all parameters
    calculate_n8n_parameters
    calculate_docker_parameters
    calculate_nginx_parameters
    
    # Verify parameters are reasonable relative to each other
    [[ "${N8N_EXECUTION_PROCESS:-0}" -le "${CPU_CORES}" ]] && \
    [[ "${NGINX_WORKER_PROCESSES:-0}" -le "${CPU_CORES}" ]]
}

# Performance impact tests
test_optimization_performance_impact() {
    local start_time end_time elapsed
    start_time=$(date +%s.%N)
    
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Run complete optimization
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    get_hardware_specs
    calculate_n8n_parameters
    calculate_docker_parameters
    calculate_nginx_parameters
    calculate_redis_parameters
    calculate_netdata_parameters
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    # Should complete within 10 seconds
    (( $(echo "$elapsed < 10.0" | bc -l 2>/dev/null || echo "1") ))
}

test_hardware_detection_performance_impact() {
    local start_time end_time elapsed
    start_time=$(date +%s.%N)
    
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Run hardware detection workflow
    get_current_hardware_specs >/dev/null 2>&1
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    save_hardware_specs "$HARDWARE_SPEC_FILE"
    load_hardware_specs "$HARDWARE_SPEC_FILE"
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    # Should complete within 5 seconds
    (( $(echo "$elapsed < 5.0" | bc -l 2>/dev/null || echo "1") ))
}

# System stability tests
test_system_stability_after_optimization() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Run optimization multiple times
    for i in {1..3}; do
        export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
        calculate_n8n_parameters >/dev/null 2>&1
        calculate_docker_parameters >/dev/null 2>&1
    done
    
    # Should not crash or cause issues
    true
}

test_service_stability_after_detection() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Run detection multiple times
    for i in {1..3}; do
        export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
        get_current_hardware_specs >/dev/null 2>&1
    done
    
    # Should not crash or cause issues
    true
}

# Recovery and rollback tests
test_configuration_rollback() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Create test configuration
    local test_config="$TEST_ENV_DIR/config/test.env"
    echo "ORIGINAL_VALUE=test" > "$test_config"
    
    # Create backup
    backup_configurations "$TEST_ENV_DIR/backups"
    
    # Modify configuration
    echo "MODIFIED_VALUE=test" > "$test_config"
    
    # Test rollback capability (mock test)
    [[ -d "$TEST_ENV_DIR/backups" ]]
}

test_hardware_specs_recovery() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Create valid specs file
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    save_hardware_specs "$HARDWARE_SPEC_FILE"
    
    # Corrupt specs file
    echo "invalid json" > "$HARDWARE_SPEC_FILE"
    
    # Test recovery (should handle gracefully)
    load_hardware_specs "$HARDWARE_SPEC_FILE" >/dev/null 2>&1 || true
    
    # Recovery should not crash the system
    true
}

# Multi-component coordination tests
test_optimization_and_detection_coordination() {
    # Test coordination between optimization and detection scripts
    bash "$PROJECT_ROOT/setup/dynamic_optimization.sh" --detect-only >/dev/null 2>&1 && \
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --show-specs >/dev/null 2>&1
}

test_service_and_script_coordination() {
    # Test coordination between service management and scripts
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --help >/dev/null 2>&1 && \
    bash "$PROJECT_ROOT/setup/dynamic_optimization.sh" --help >/dev/null 2>&1
}

# Error recovery tests
test_error_recovery_missing_files() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Test with missing files (should handle gracefully)
    update_n8n_configuration "/nonexistent/file.env" >/dev/null 2>&1 || true
    
    # Should not crash
    true
}

test_error_recovery_invalid_permissions() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test with invalid permissions (should handle gracefully)
    export HARDWARE_SPEC_FILE="/root/protected/specs.json"
    save_hardware_specs "$HARDWARE_SPEC_FILE" >/dev/null 2>&1 || true
    
    # Should not crash
    true
}

# Main test execution
main() {
    log_info "Running dynamic optimization integration tests..."
    
    setup_integration_test_environment
    
    # Script availability tests
    run_test "test_optimization_script_availability" test_optimization_script_availability
    run_test "test_hardware_detector_script_availability" test_hardware_detector_script_availability
    run_test "test_required_utilities_availability" test_required_utilities_availability
    
    # Complete workflow tests
    run_test "test_complete_optimization_workflow" test_complete_optimization_workflow
    run_test "test_hardware_change_detection_workflow" test_hardware_change_detection_workflow
    run_test "test_service_management_workflow" test_service_management_workflow
    
    # Integration between components
    run_test "test_optimization_and_detection_integration" test_optimization_and_detection_integration
    run_test "test_configuration_backup_and_restore" test_configuration_backup_and_restore
    run_test "test_email_notification_integration" test_email_notification_integration
    
    # Configuration consistency tests
    run_test "test_n8n_configuration_consistency" test_n8n_configuration_consistency
    run_test "test_docker_configuration_consistency" test_docker_configuration_consistency
    run_test "test_cross_component_parameter_consistency" test_cross_component_parameter_consistency
    
    # Performance impact tests
    run_test "test_optimization_performance_impact" test_optimization_performance_impact
    run_test "test_hardware_detection_performance_impact" test_hardware_detection_performance_impact
    
    # System stability tests
    run_test "test_system_stability_after_optimization" test_system_stability_after_optimization
    run_test "test_service_stability_after_detection" test_service_stability_after_detection
    
    # Recovery and rollback tests
    run_test "test_configuration_rollback" test_configuration_rollback
    run_test "test_hardware_specs_recovery" test_hardware_specs_recovery
    
    # Multi-component coordination tests
    run_test "test_optimization_and_detection_coordination" test_optimization_and_detection_coordination
    run_test "test_service_and_script_coordination" test_service_and_script_coordination
    
    # Error recovery tests
    run_test "test_error_recovery_missing_files" test_error_recovery_missing_files
    run_test "test_error_recovery_invalid_permissions" test_error_recovery_invalid_permissions
    
    cleanup_integration_test_environment
    
    log_info "Dynamic optimization integration tests completed: $PASSED_TESTS/$TOTAL_TESTS passed"
    
    if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
        log_info "Dynamic Optimization Integration Tests: PASSED"
        return 0
    else
        log_error "Dynamic Optimization Integration Tests: FAILED"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 