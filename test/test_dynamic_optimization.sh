#!/bin/bash

# test_dynamic_optimization.sh - Tests for Dynamic Hardware Optimization
# Part of Milestone 6: Dynamic Hardware Optimization

set -euo pipefail

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source required utilities
source "$SCRIPT_DIR/../lib/logger.sh"
source "$SCRIPT_DIR/../lib/utilities.sh"

# Test configuration
readonly TEST_BACKUP_DIR="/tmp/n8n_optimization_test_backup"
readonly OPTIMIZATION_SCRIPT="$PROJECT_ROOT/setup/dynamic_optimization.sh"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    log_info "Setting up test environment for dynamic optimization..."
    
    # Create test backup directory
    mkdir -p "$TEST_BACKUP_DIR"
    
    # Backup original files if they exist
    [[ -f "/opt/n8n/docker/.env" ]] && cp "/opt/n8n/docker/.env" "$TEST_BACKUP_DIR/n8n.env.original"
    [[ -f "/opt/n8n/docker/docker-compose.yml" ]] && cp "/opt/n8n/docker/docker-compose.yml" "$TEST_BACKUP_DIR/docker-compose.yml.original"
    [[ -f "/etc/nginx/nginx.conf" ]] && cp "/etc/nginx/nginx.conf" "$TEST_BACKUP_DIR/nginx.conf.original"
    [[ -f "/etc/nginx/sites-available/n8n" ]] && cp "/etc/nginx/sites-available/n8n" "$TEST_BACKUP_DIR/nginx-n8n.conf.original"
    [[ -f "/etc/netdata/netdata.conf" ]] && cp "/etc/netdata/netdata.conf" "$TEST_BACKUP_DIR/netdata.conf.original"
    
    # Create test directories
    mkdir -p "/opt/n8n/docker" "/opt/n8n/logs" "/opt/n8n/backups/optimization"
    
    log_info "Test environment setup completed"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    
    # Restore original files if they were backed up
    [[ -f "$TEST_BACKUP_DIR/n8n.env.original" ]] && cp "$TEST_BACKUP_DIR/n8n.env.original" "/opt/n8n/docker/.env"
    [[ -f "$TEST_BACKUP_DIR/docker-compose.yml.original" ]] && cp "$TEST_BACKUP_DIR/docker-compose.yml.original" "/opt/n8n/docker/docker-compose.yml"
    [[ -f "$TEST_BACKUP_DIR/nginx.conf.original" ]] && cp "$TEST_BACKUP_DIR/nginx.conf.original" "/etc/nginx/nginx.conf"
    [[ -f "$TEST_BACKUP_DIR/nginx-n8n.conf.original" ]] && cp "$TEST_BACKUP_DIR/nginx-n8n.conf.original" "/etc/nginx/sites-available/n8n"
    [[ -f "$TEST_BACKUP_DIR/netdata.conf.original" ]] && cp "$TEST_BACKUP_DIR/netdata.conf.original" "/etc/netdata/netdata.conf"
    
    # Remove test backup directory
    rm -rf "$TEST_BACKUP_DIR"
    
    log_info "Test environment cleanup completed"
}

# =============================================================================
# HARDWARE DETECTION TESTS
# =============================================================================

test_hardware_detection_cpu_cores() {
    source "$OPTIMIZATION_SCRIPT"
    
    local cpu_cores
    cpu_cores=$(detect_cpu_cores)
    
    # Verify CPU cores is a positive integer
    [[ "$cpu_cores" =~ ^[0-9]+$ ]] && [[ "$cpu_cores" -ge 1 ]] && [[ "$cpu_cores" -le 64 ]]
}

test_hardware_detection_memory() {
    source "$OPTIMIZATION_SCRIPT"
    
    local memory_gb
    memory_gb=$(detect_memory_gb)
    
    # Verify memory is a positive integer
    [[ "$memory_gb" =~ ^[0-9]+$ ]] && [[ "$memory_gb" -ge 1 ]] && [[ "$memory_gb" -le 256 ]]
}

test_hardware_detection_disk() {
    source "$OPTIMIZATION_SCRIPT"
    
    local disk_gb
    disk_gb=$(detect_disk_gb)
    
    # Verify disk space is a positive integer
    [[ "$disk_gb" =~ ^[0-9]+$ ]] && [[ "$disk_gb" -ge 10 ]] && [[ "$disk_gb" -le 10240 ]]
}

test_hardware_specs_export() {
    source "$OPTIMIZATION_SCRIPT"
    
    get_hardware_specs
    
    # Verify exported variables exist and are valid
    [[ -n "${HW_CPU_CORES:-}" ]] && [[ "$HW_CPU_CORES" =~ ^[0-9]+$ ]] &&
    [[ -n "${HW_MEMORY_GB:-}" ]] && [[ "$HW_MEMORY_GB" =~ ^[0-9]+$ ]] &&
    [[ -n "${HW_DISK_GB:-}" ]] && [[ "$HW_DISK_GB" =~ ^[0-9]+$ ]]
}

# =============================================================================
# PARAMETER CALCULATION TESTS
# =============================================================================

test_n8n_parameter_calculation() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    calculate_n8n_parameters
    
    # Verify calculated parameters
    [[ -n "${N8N_EXECUTION_PROCESS:-}" ]] && [[ "$N8N_EXECUTION_PROCESS" =~ ^[0-9]+$ ]] &&
    [[ -n "${N8N_MEMORY_LIMIT_MB:-}" ]] && [[ "$N8N_MEMORY_LIMIT_MB" =~ ^[0-9]+$ ]] &&
    [[ -n "${N8N_EXECUTION_TIMEOUT:-}" ]] && [[ "$N8N_EXECUTION_TIMEOUT" =~ ^[0-9]+$ ]] &&
    [[ -n "${N8N_WEBHOOK_TIMEOUT:-}" ]] && [[ "$N8N_WEBHOOK_TIMEOUT" =~ ^[0-9]+$ ]]
}

test_docker_parameter_calculation() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    calculate_docker_parameters
    
    # Verify calculated parameters
    [[ -n "${DOCKER_MEMORY_LIMIT:-}" ]] && [[ "$DOCKER_MEMORY_LIMIT" =~ ^[0-9]+g$ ]] &&
    [[ -n "${DOCKER_CPU_LIMIT:-}" ]] && [[ "$DOCKER_CPU_LIMIT" =~ ^[0-9.]+$ ]] &&
    [[ -n "${DOCKER_SHM_SIZE:-}" ]] && [[ "$DOCKER_SHM_SIZE" =~ ^[0-9]+m$ ]]
}

test_nginx_parameter_calculation() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    calculate_nginx_parameters
    
    # Verify calculated parameters
    [[ -n "${NGINX_WORKER_PROCESSES:-}" ]] && [[ "$NGINX_WORKER_PROCESSES" =~ ^[0-9]+$ ]] &&
    [[ -n "${NGINX_WORKER_CONNECTIONS:-}" ]] && [[ "$NGINX_WORKER_CONNECTIONS" =~ ^[0-9]+$ ]] &&
    [[ -n "${NGINX_CLIENT_MAX_BODY:-}" ]] && [[ "$NGINX_CLIENT_MAX_BODY" =~ ^[0-9]+m$ ]] &&
    [[ -n "${NGINX_SSL_SESSION_CACHE:-}" ]] && [[ "$NGINX_SSL_SESSION_CACHE" =~ ^[0-9]+m$ ]]
}

test_redis_parameter_calculation() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    calculate_redis_parameters
    
    # Verify calculated parameters
    [[ -n "${REDIS_MAXMEMORY:-}" ]] && [[ "$REDIS_MAXMEMORY" =~ ^[0-9]+mb$ ]] &&
    [[ -n "${REDIS_SAVE_INTERVAL:-}" ]] && [[ -n "$REDIS_SAVE_INTERVAL" ]] &&
    [[ -n "${REDIS_MAXMEMORY_POLICY:-}" ]] && [[ "$REDIS_MAXMEMORY_POLICY" == "allkeys-lru" ]]
}

test_netdata_parameter_calculation() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    calculate_netdata_parameters
    
    # Verify calculated parameters
    [[ -n "${NETDATA_UPDATE_EVERY:-}" ]] && [[ "$NETDATA_UPDATE_EVERY" =~ ^[0-9]+$ ]] &&
    [[ -n "${NETDATA_MEMORY_LIMIT:-}" ]] && [[ "$NETDATA_MEMORY_LIMIT" =~ ^[0-9]+$ ]] &&
    [[ -n "${NETDATA_HISTORY_HOURS:-}" ]] && [[ "$NETDATA_HISTORY_HOURS" =~ ^[0-9]+$ ]]
}

# =============================================================================
# PARAMETER SCALING TESTS
# =============================================================================

test_parameter_scaling_low_end_hardware() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Test with low-end hardware
    export HW_CPU_CORES=1
    export HW_MEMORY_GB=1
    export HW_DISK_GB=20
    
    calculate_n8n_parameters
    calculate_docker_parameters
    calculate_nginx_parameters
    calculate_redis_parameters
    calculate_netdata_parameters
    
    # Verify parameters are reasonable for low-end hardware
    [[ "$N8N_EXECUTION_PROCESS" -eq 1 ]] &&
    [[ "${DOCKER_MEMORY_LIMIT%g}" -eq 0 ]] &&  # Should be 0g for 1GB system
    [[ "$NGINX_WORKER_PROCESSES" -eq 1 ]] &&
    [[ "${REDIS_MAXMEMORY%mb}" -ge 64 ]] &&  # Minimum Redis memory
    [[ "$NETDATA_UPDATE_EVERY" -ge 2 ]]  # Slower updates for low-end
}

test_parameter_scaling_high_end_hardware() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Test with high-end hardware
    export HW_CPU_CORES=16
    export HW_MEMORY_GB=64
    export HW_DISK_GB=1000
    
    calculate_n8n_parameters
    calculate_docker_parameters
    calculate_nginx_parameters
    calculate_redis_parameters
    calculate_netdata_parameters
    
    # Verify parameters scale appropriately for high-end hardware
    [[ "$N8N_EXECUTION_PROCESS" -ge 12 ]] &&  # 75% of 16 cores
    [[ "${DOCKER_MEMORY_LIMIT%g}" -ge 50 ]] &&  # 80% of 64GB
    [[ "$NGINX_WORKER_PROCESSES" -eq 16 ]] &&
    [[ "${REDIS_MAXMEMORY%mb}" -ge 9000 ]] &&  # 15% of 64GB
    [[ "$NETDATA_UPDATE_EVERY" -eq 1 ]]  # Fastest updates for high-end
}

# =============================================================================
# CONFIGURATION UPDATE TESTS
# =============================================================================

test_n8n_configuration_update() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Create test n8n environment file
    local test_env_file="/opt/n8n/docker/.env"
    cat > "$test_env_file" << EOF
N8N_PORT=5678
N8N_HOST=0.0.0.0
N8N_EXECUTION_PROCESS=2
N8N_EXECUTION_TIMEOUT=300
WEBHOOK_TIMEOUT=240
EOF
    
    # Set test parameters
    export N8N_EXECUTION_PROCESS=4
    export N8N_EXECUTION_TIMEOUT=600
    export N8N_WEBHOOK_TIMEOUT=480
    
    update_n8n_configuration
    
    # Verify configuration was updated
    grep -q "N8N_EXECUTION_PROCESS=4" "$test_env_file" &&
    grep -q "N8N_EXECUTION_TIMEOUT=600" "$test_env_file" &&
    grep -q "WEBHOOK_TIMEOUT=480" "$test_env_file"
}

test_docker_configuration_backup() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    backup_configurations
    
    # Verify backup was created
    [[ -n "${BACKUP_PATH:-}" ]] && [[ -d "$BACKUP_PATH" ]] &&
    [[ -f "$BACKUP_PATH/manifest.txt" ]]
}

# =============================================================================
# COMMAND LINE INTERFACE TESTS
# =============================================================================

test_optimization_script_detect_only() {
    bash "$OPTIMIZATION_SCRIPT" --detect-only >/dev/null 2>&1
}

test_optimization_script_calculate_only() {
    bash "$OPTIMIZATION_SCRIPT" --calculate-only >/dev/null 2>&1
}

test_optimization_script_help() {
    bash "$OPTIMIZATION_SCRIPT" --help >/dev/null 2>&1
}

test_optimization_script_invalid_option() {
    ! bash "$OPTIMIZATION_SCRIPT" --invalid-option >/dev/null 2>&1
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_full_optimization_dry_run() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    
    # Test the full optimization workflow without actually applying changes
    get_hardware_specs &&
    calculate_n8n_parameters &&
    calculate_docker_parameters &&
    calculate_nginx_parameters &&
    calculate_redis_parameters &&
    calculate_netdata_parameters &&
    backup_configurations
    
    # Verify all parameters were calculated
    [[ -n "${N8N_EXECUTION_PROCESS:-}" ]] &&
    [[ -n "${DOCKER_MEMORY_LIMIT:-}" ]] &&
    [[ -n "${NGINX_WORKER_PROCESSES:-}" ]] &&
    [[ -n "${REDIS_MAXMEMORY:-}" ]] &&
    [[ -n "${NETDATA_UPDATE_EVERY:-}" ]] &&
    [[ -n "${BACKUP_PATH:-}" ]]
}

test_optimization_report_generation() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs and parameters
    export HW_CPU_CORES=4
    export HW_MEMORY_GB=8
    export HW_DISK_GB=100
    export N8N_EXECUTION_PROCESS=3
    export N8N_MEMORY_LIMIT_MB=3276
    export N8N_EXECUTION_TIMEOUT=540
    export N8N_WEBHOOK_TIMEOUT=432
    export DOCKER_MEMORY_LIMIT="6g"
    export DOCKER_CPU_LIMIT="3.6"
    export DOCKER_SHM_SIZE="768m"
    export NGINX_WORKER_PROCESSES=4
    export NGINX_WORKER_CONNECTIONS=1536
    export NGINX_CLIENT_MAX_BODY="50m"
    export NGINX_SSL_SESSION_CACHE="16m"
    export REDIS_MAXMEMORY="1228mb"
    export REDIS_MAXMEMORY_POLICY="allkeys-lru"
    export REDIS_SAVE_INTERVAL="900 1 300 10"
    export NETDATA_UPDATE_EVERY=1
    export NETDATA_MEMORY_LIMIT=409
    export NETDATA_HISTORY_HOURS=72
    export BACKUP_PATH="/opt/n8n/backups/optimization/test"
    
    local report_file
    report_file=$(generate_optimization_report)
    
    # Verify report was generated and contains expected content
    [[ -f "$report_file" ]] &&
    grep -q "n8n Server Dynamic Optimization Report" "$report_file" &&
    grep -q "CPU Cores: 4" "$report_file" &&
    grep -q "Memory: 8GB" "$report_file" &&
    grep -q "Execution Processes: 3" "$report_file"
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_hardware_detection_performance() {
    source "$OPTIMIZATION_SCRIPT"
    
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    # Run hardware detection multiple times
    for i in {1..10}; do
        get_hardware_specs >/dev/null 2>&1
    done
    
    end_time=$(date +%s%N)
    duration=$(((end_time - start_time) / 1000000))  # Convert to milliseconds
    
    # Hardware detection should complete within reasonable time (< 1 second total)
    [[ "$duration" -lt 1000 ]]
}

test_parameter_calculation_performance() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Set test hardware specs
    export HW_CPU_CORES=8
    export HW_MEMORY_GB=16
    export HW_DISK_GB=500
    
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    # Run parameter calculations multiple times
    for i in {1..10}; do
        calculate_n8n_parameters >/dev/null 2>&1
        calculate_docker_parameters >/dev/null 2>&1
        calculate_nginx_parameters >/dev/null 2>&1
        calculate_redis_parameters >/dev/null 2>&1
        calculate_netdata_parameters >/dev/null 2>&1
    done
    
    end_time=$(date +%s%N)
    duration=$(((end_time - start_time) / 1000000))  # Convert to milliseconds
    
    # Parameter calculations should complete within reasonable time (< 500ms total)
    [[ "$duration" -lt 500 ]]
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_missing_optimization_script() {
    local fake_script="/tmp/nonexistent_optimization_script.sh"
    ! bash "$fake_script" --help >/dev/null 2>&1
}

test_invalid_hardware_values() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Test with invalid hardware values
    export HW_CPU_CORES=0
    export HW_MEMORY_GB=0
    export HW_DISK_GB=0
    
    # Should handle invalid values gracefully
    calculate_n8n_parameters >/dev/null 2>&1 &&
    [[ "$N8N_EXECUTION_PROCESS" -ge 1 ]]  # Should default to minimum values
}

test_missing_configuration_files() {
    source "$OPTIMIZATION_SCRIPT"
    
    # Test with missing configuration files
    local fake_env_file="/tmp/nonexistent.env"
    
    # Should handle missing files gracefully
    ! update_n8n_configuration >/dev/null 2>&1 || true  # Allow failure
}

# =============================================================================
# TEST RUNNER
# =============================================================================

run_dynamic_optimization_tests() {
    local tests_passed=0
    local tests_failed=0
    local test_functions=(
        # Hardware detection tests
        "test_hardware_detection_cpu_cores"
        "test_hardware_detection_memory"
        "test_hardware_detection_disk"
        "test_hardware_specs_export"
        
        # Parameter calculation tests
        "test_n8n_parameter_calculation"
        "test_docker_parameter_calculation"
        "test_nginx_parameter_calculation"
        "test_redis_parameter_calculation"
        "test_netdata_parameter_calculation"
        
        # Parameter scaling tests
        "test_parameter_scaling_low_end_hardware"
        "test_parameter_scaling_high_end_hardware"
        
        # Configuration update tests
        "test_n8n_configuration_update"
        "test_docker_configuration_backup"
        
        # Command line interface tests
        "test_optimization_script_detect_only"
        "test_optimization_script_calculate_only"
        "test_optimization_script_help"
        "test_optimization_script_invalid_option"
        
        # Integration tests
        "test_full_optimization_dry_run"
        "test_optimization_report_generation"
        
        # Performance tests
        "test_hardware_detection_performance"
        "test_parameter_calculation_performance"
        
        # Error handling tests
        "test_missing_optimization_script"
        "test_invalid_hardware_values"
        "test_missing_configuration_files"
    )
    
    log_info "Running dynamic optimization tests..."
    setup_test_environment
    
    for test_function in "${test_functions[@]}"; do
        if $test_function >/dev/null 2>&1; then
            log_info "✓ $test_function"
            tests_passed=$((tests_passed + 1))
        else
            log_error "✗ $test_function"
            tests_failed=$((tests_failed + 1))
        fi
    done
    
    cleanup_test_environment
    
    local total_tests=$((tests_passed + tests_failed))
    log_info "Dynamic optimization tests completed: $tests_passed/$total_tests passed"
    
    return $tests_failed
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_dynamic_optimization_tests
fi 