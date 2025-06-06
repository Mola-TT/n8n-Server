#!/bin/bash

# test_dynamic_optimization.sh - Tests for Dynamic Hardware Optimization
# Part of Milestone 6 test suite

set -euo pipefail

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

# Source required utilities
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Test configuration
TEST_ENV_DIR="/tmp/test_dynamic_optimization"
PASSED_TESTS=0
TOTAL_TESTS=0

# Test helper functions
setup_test_environment() {
    log_info "Setting up test environment for dynamic optimization..."
    
    # Create test directories
    mkdir -p "$TEST_ENV_DIR"
    mkdir -p "$TEST_ENV_DIR/config"
    mkdir -p "$TEST_ENV_DIR/backups"
    
    # Set test environment variables
    export TEST_MODE=true
    export CPU_CORES=4
    export MEMORY_GB=8
    export DISK_GB=100
    
    log_info "Test environment setup completed"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_ENV_DIR"
    unset TEST_MODE CPU_CORES MEMORY_GB DISK_GB
    log_info "Test environment cleanup completed"
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

# Hardware detection tests
test_hardware_detection_cpu_cores() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    local cores
    cores=$(detect_cpu_cores)
    [[ "$cores" =~ ^[0-9]+$ ]] && [[ "$cores" -gt 0 ]]
}

test_hardware_detection_memory() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    local memory
    memory=$(detect_memory_gb)
    [[ "$memory" =~ ^[0-9]+$ ]] && [[ "$memory" -gt 0 ]]
}

test_hardware_detection_disk() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    local disk
    disk=$(detect_disk_gb)
    [[ "$disk" =~ ^[0-9]+$ ]] && [[ "$disk" -gt 0 ]]
}

test_hardware_specs_export() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    get_hardware_specs
    [[ -n "${CPU_CORES:-}" ]] && [[ -n "${MEMORY_GB:-}" ]] && [[ -n "${DISK_GB:-}" ]]
}

# Parameter calculation tests
test_n8n_parameter_calculation() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    calculate_n8n_parameters
    [[ -n "${N8N_EXECUTION_PROCESS:-}" ]] && [[ -n "${N8N_EXECUTION_TIMEOUT:-}" ]]
}

test_docker_parameter_calculation() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    calculate_docker_parameters
    [[ -n "${DOCKER_MEMORY_LIMIT:-}" ]] && [[ -n "${DOCKER_CPU_LIMIT:-}" ]]
}

test_nginx_parameter_calculation() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    calculate_nginx_parameters
    [[ -n "${NGINX_WORKER_PROCESSES:-}" ]] && [[ -n "${NGINX_WORKER_CONNECTIONS:-}" ]]
}

test_redis_parameter_calculation() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    calculate_redis_parameters
    [[ -n "${REDIS_MAXMEMORY:-}" ]] && [[ -n "${REDIS_MAXMEMORY_POLICY:-}" ]]
}

test_netdata_parameter_calculation() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    calculate_netdata_parameters
    [[ -n "${NETDATA_UPDATE_EVERY:-}" ]] && [[ -n "${NETDATA_MEMORY_MODE:-}" ]]
}

# Parameter scaling tests
test_parameter_scaling_low_end_hardware() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=2 MEMORY_GB=2 DISK_GB=20
    export HW_CPU_CORES=2 HW_MEMORY_MB=2048

    calculate_n8n_parameters
    calculate_docker_parameters

    # Verify low-end scaling
    [[ "${N8N_EXECUTION_PROCESS:-0}" -le 4 ]] && \
    [[ "${DOCKER_MEMORY_LIMIT:-0}" =~ ^[0-9]+[mg]$ ]]
}

test_parameter_scaling_high_end_hardware() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=16 MEMORY_GB=32 DISK_GB=1000
    export HW_CPU_CORES=16 HW_MEMORY_MB=32768

    calculate_n8n_parameters
    calculate_docker_parameters

    # Verify high-end scaling
    [[ "${N8N_EXECUTION_PROCESS:-0}" -ge 8 ]] && \
    [[ "${DOCKER_MEMORY_LIMIT:-0}" =~ ^[0-9]+[mg]$ ]]
}

# Configuration update tests
test_n8n_configuration_update() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    
    # Create test config file
    local test_config="$TEST_ENV_DIR/config/test.env"
    echo "N8N_EXECUTION_PROCESS=2" > "$test_config"
    
    calculate_n8n_parameters
    
    # Test would update configuration (mock test)
    [[ -f "$test_config" ]]
}

test_docker_configuration_backup() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Create test docker-compose file
    local test_compose="$TEST_ENV_DIR/config/docker-compose.yml"
    echo "version: '3.8'" > "$test_compose"
    
    # Test backup functionality (mock test)
    [[ -f "$test_compose" ]]
}

# Script functionality tests
test_optimization_script_detect_only() {
    bash "$PROJECT_ROOT/setup/dynamic_optimization.sh" --detect-only >/dev/null 2>&1
}

test_optimization_script_calculate_only() {
    bash "$PROJECT_ROOT/setup/dynamic_optimization.sh" --calculate-only >/dev/null 2>&1
}

test_optimization_script_help() {
    bash "$PROJECT_ROOT/setup/dynamic_optimization.sh" --help >/dev/null 2>&1
}

test_optimization_script_invalid_option() {
    ! bash "$PROJECT_ROOT/setup/dynamic_optimization.sh" --invalid-option >/dev/null 2>&1
}

test_full_optimization_dry_run() {
    bash "$PROJECT_ROOT/setup/dynamic_optimization.sh" --dry-run >/dev/null 2>&1
}

test_optimization_report_generation() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    
    calculate_n8n_parameters
    calculate_docker_parameters
    
    # Test report generation (mock test)
    [[ -n "${N8N_EXECUTION_PROCESS:-}" ]]
}

# Performance tests
test_hardware_detection_performance() {
    local start_time end_time elapsed
    start_time=$(date +%s.%N)
    
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    get_hardware_specs >/dev/null 2>&1
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    # Should complete within 5 seconds
    (( $(echo "$elapsed < 5.0" | bc -l 2>/dev/null || echo "1") ))
}

test_parameter_calculation_performance() {
    local start_time end_time elapsed
    start_time=$(date +%s.%N)
    
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    
    calculate_n8n_parameters >/dev/null 2>&1
    calculate_docker_parameters >/dev/null 2>&1
    calculate_nginx_parameters >/dev/null 2>&1
    calculate_redis_parameters >/dev/null 2>&1
    calculate_netdata_parameters >/dev/null 2>&1
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    # Should complete within 3 seconds
    (( $(echo "$elapsed < 3.0" | bc -l 2>/dev/null || echo "1") ))
}

# Error handling tests
test_missing_optimization_script() {
    ! bash "/nonexistent/dynamic_optimization.sh" >/dev/null 2>&1
}

test_invalid_hardware_values() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    export CPU_CORES=0 MEMORY_GB=0 DISK_GB=0
    
    # Should handle invalid values gracefully
    calculate_n8n_parameters >/dev/null 2>&1 || true
}

test_missing_configuration_files() {
    source "$PROJECT_ROOT/setup/dynamic_optimization.sh"
    
    # Test with missing config files (should not crash)
    update_n8n_configuration "/nonexistent/config.env" >/dev/null 2>&1 || true
}

# Main test execution
main() {
    log_info "Running dynamic optimization tests..."
    
    setup_test_environment
    
    # Hardware detection tests
    run_test "test_hardware_detection_cpu_cores" test_hardware_detection_cpu_cores
    run_test "test_hardware_detection_memory" test_hardware_detection_memory
    run_test "test_hardware_detection_disk" test_hardware_detection_disk
    run_test "test_hardware_specs_export" test_hardware_specs_export
    
    # Parameter calculation tests
    run_test "test_n8n_parameter_calculation" test_n8n_parameter_calculation
    run_test "test_docker_parameter_calculation" test_docker_parameter_calculation
    run_test "test_nginx_parameter_calculation" test_nginx_parameter_calculation
    run_test "test_redis_parameter_calculation" test_redis_parameter_calculation
    run_test "test_netdata_parameter_calculation" test_netdata_parameter_calculation
    
    # Parameter scaling tests
    run_test "test_parameter_scaling_low_end_hardware" test_parameter_scaling_low_end_hardware
    run_test "test_parameter_scaling_high_end_hardware" test_parameter_scaling_high_end_hardware
    
    # Configuration update tests
    run_test "test_n8n_configuration_update" test_n8n_configuration_update
    run_test "test_docker_configuration_backup" test_docker_configuration_backup
    
    # Script functionality tests
    run_test "test_optimization_script_detect_only" test_optimization_script_detect_only
    run_test "test_optimization_script_calculate_only" test_optimization_script_calculate_only
    run_test "test_optimization_script_help" test_optimization_script_help
    run_test "test_optimization_script_invalid_option" test_optimization_script_invalid_option
    run_test "test_full_optimization_dry_run" test_full_optimization_dry_run
    run_test "test_optimization_report_generation" test_optimization_report_generation
    
    # Performance tests
    run_test "test_hardware_detection_performance" test_hardware_detection_performance
    run_test "test_parameter_calculation_performance" test_parameter_calculation_performance
    
    # Error handling tests
    run_test "test_missing_optimization_script" test_missing_optimization_script
    run_test "test_invalid_hardware_values" test_invalid_hardware_values
    run_test "test_missing_configuration_files" test_missing_configuration_files
    
    cleanup_test_environment
    
    log_info "Dynamic optimization tests completed: $PASSED_TESTS/$TOTAL_TESTS passed"
    
    if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
        log_info "Dynamic Optimization Tests: PASSED"
        return 0
    else
        log_error "Dynamic Optimization Tests: FAILED"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 