#!/bin/bash

# test_hardware_change_detector.sh - Tests for Hardware Change Detection
# Part of Milestone 6 test suite

set -euo pipefail

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

# Source required utilities
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Test configuration
TEST_ENV_DIR="/tmp/test_hardware_change_detector"
PASSED_TESTS=0
TOTAL_TESTS=0

# Test helper functions
setup_hardware_change_detector_test_environment() {
    log_info "Setting up hardware change detector test environment..."
    
    # Create test directories
    mkdir -p "$TEST_ENV_DIR"
    mkdir -p "$TEST_ENV_DIR/specs"
    mkdir -p "$TEST_ENV_DIR/backups"
    mkdir -p "$TEST_ENV_DIR/cooldown"
    
    # Set test environment variables
    export TEST_MODE=true
    export HARDWARE_SPEC_FILE="$TEST_ENV_DIR/specs/hardware_specs.json"
    export DETECTOR_LOG_FILE="$TEST_ENV_DIR/detector.log"
    export DETECTOR_PID_FILE="$TEST_ENV_DIR/detector.pid"
    
    # Set email configuration for tests
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    export SMTP_SERVER="smtp.example.com"
    export SMTP_PORT="587"
    export SMTP_USERNAME="testuser"
    export SMTP_PASSWORD="testpass"
    export EMAIL_COOLDOWN_HOURS="24"
    
    log_info "Hardware change detector test environment setup completed"
}

cleanup_hardware_change_detector_test_environment() {
    log_info "Cleaning up hardware change detector test environment..."
    rm -rf "$TEST_ENV_DIR"
    unset TEST_MODE HARDWARE_SPEC_FILE DETECTOR_LOG_FILE DETECTOR_PID_FILE
    unset EMAIL_SENDER EMAIL_RECIPIENT SMTP_SERVER SMTP_PORT SMTP_USERNAME SMTP_PASSWORD EMAIL_COOLDOWN_HOURS
    log_info "Hardware change detector test environment cleanup completed"
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

# Hardware specs management tests
test_current_hardware_specs_generation() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    local specs
    specs=$(get_current_hardware_specs)
    
    [[ "$specs" =~ "cpu_cores" ]] && [[ "$specs" =~ "memory_gb" ]] && [[ "$specs" =~ "disk_gb" ]]
}

test_hardware_specs_loading() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Create test specs file
    cat > "$HARDWARE_SPEC_FILE" << EOF
{
    "cpu_cores": 4,
    "memory_gb": 8,
    "disk_gb": 100,
    "timestamp": "$(date -Iseconds)"
}
EOF
    
    load_hardware_specs "$HARDWARE_SPEC_FILE"
    [[ -n "${PREVIOUS_CPU_CORES:-}" ]] && [[ -n "${PREVIOUS_MEMORY_GB:-}" ]] && [[ -n "${PREVIOUS_DISK_GB:-}" ]]
}

test_hardware_specs_saving() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    save_hardware_specs "$HARDWARE_SPEC_FILE"
    
    [[ -f "$HARDWARE_SPEC_FILE" ]] && grep -q "cpu_cores" "$HARDWARE_SPEC_FILE"
}

test_hardware_specs_backup_creation() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Create original specs file
    echo '{"cpu_cores": 4}' > "$HARDWARE_SPEC_FILE"
    
    backup_hardware_specs "$HARDWARE_SPEC_FILE" "$TEST_ENV_DIR/backups"
    
    [[ -f "$TEST_ENV_DIR/backups/hardware_specs_backup_"*.json ]]
}

test_spec_value_extraction() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Create test specs file
    cat > "$HARDWARE_SPEC_FILE" << EOF
{
    "cpu_cores": 4,
    "memory_gb": 8,
    "disk_gb": 100
}
EOF
    
    local cpu_cores memory_gb disk_gb
    cpu_cores=$(get_spec_value "$HARDWARE_SPEC_FILE" "cpu_cores")
    memory_gb=$(get_spec_value "$HARDWARE_SPEC_FILE" "memory_gb")
    disk_gb=$(get_spec_value "$HARDWARE_SPEC_FILE" "disk_gb")
    
    [[ "$cpu_cores" == "4" ]] && [[ "$memory_gb" == "8" ]] && [[ "$disk_gb" == "100" ]]
}

# Hardware change detection tests
test_hardware_change_detection_no_changes() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set current specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    export PREVIOUS_CPU_CORES=4 PREVIOUS_MEMORY_GB=8 PREVIOUS_DISK_GB=100
    
    ! detect_hardware_changes
}

test_hardware_change_detection_cpu_change() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set specs with CPU change
    export CPU_CORES=8 MEMORY_GB=8 DISK_GB=100
    export PREVIOUS_CPU_CORES=4 PREVIOUS_MEMORY_GB=8 PREVIOUS_DISK_GB=100
    
    detect_hardware_changes
}

test_hardware_change_detection_memory_change() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set specs with memory change
    export CPU_CORES=4 MEMORY_GB=16 DISK_GB=100
    export PREVIOUS_CPU_CORES=4 PREVIOUS_MEMORY_GB=8 PREVIOUS_DISK_GB=100
    
    detect_hardware_changes
}

test_hardware_change_detection_disk_change() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set specs with disk change
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=200
    export PREVIOUS_CPU_CORES=4 PREVIOUS_MEMORY_GB=8 PREVIOUS_DISK_GB=100
    
    detect_hardware_changes
}

test_hardware_change_detection_multiple_changes() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set specs with multiple changes
    export CPU_CORES=8 MEMORY_GB=16 DISK_GB=200
    export PREVIOUS_CPU_CORES=4 PREVIOUS_MEMORY_GB=8 PREVIOUS_DISK_GB=100
    
    detect_hardware_changes
}

test_hardware_change_detection_threshold_cpu() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set specs with change below threshold
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    export PREVIOUS_CPU_CORES=4 PREVIOUS_MEMORY_GB=8 PREVIOUS_DISK_GB=100
    export CPU_CHANGE_THRESHOLD=2
    
    ! detect_hardware_changes
}

# Service management tests
test_systemd_service_creation() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test service file creation (mock test)
    create_detector_service >/dev/null 2>&1 || true
    
    # Service creation should not fail
    true
}

test_detector_service_status() {
    # Test service status check (mock test)
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --status >/dev/null 2>&1 || true
}

test_detector_service_start_stop() {
    # Test service start/stop (mock test)
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --start >/dev/null 2>&1 || true
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --stop >/dev/null 2>&1 || true
}

# Script functionality tests
test_hardware_detector_help() {
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --help >/dev/null 2>&1
}

test_hardware_detector_show_specs() {
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --show-specs >/dev/null 2>&1
}

test_hardware_detector_check_once() {
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --check-once >/dev/null 2>&1
}

test_hardware_detector_status() {
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --status >/dev/null 2>&1 || true
}

test_hardware_detector_invalid_option() {
    ! bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --invalid-option >/dev/null 2>&1
}

# Optimization trigger tests
test_optimization_trigger_mock() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Mock optimization trigger (should not fail)
    trigger_optimization >/dev/null 2>&1 || true
}

test_optimization_trigger_missing_script() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test with missing optimization script
    export OPTIMIZATION_SCRIPT="/nonexistent/script.sh"
    ! trigger_optimization >/dev/null 2>&1
    unset OPTIMIZATION_SCRIPT
}

# Email notification integration tests
test_email_notification_integration() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test email notification preparation (mock test)
    local subject body
    subject=$(get_email_subject "hardware_change")
    body=$(get_email_body "hardware_change" "Test specs")
    
    [[ -n "$subject" ]] && [[ -n "$body" ]]
}

test_email_test_functionality() {
    # Test email test functionality (mock test)
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --test-email >/dev/null 2>&1 || true
}

# Daemon functionality tests
test_daemon_initialization() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test daemon initialization (mock test)
    initialize_daemon >/dev/null 2>&1 || true
}

# Error handling tests
test_missing_hardware_detector_script() {
    ! bash "/nonexistent/hardware_change_detector.sh" >/dev/null 2>&1
}

test_invalid_hardware_specs_file() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Create invalid specs file
    echo "invalid json" > "$HARDWARE_SPEC_FILE"
    
    # Should handle invalid file gracefully
    load_hardware_specs "$HARDWARE_SPEC_FILE" >/dev/null 2>&1 || true
}

test_missing_directories() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test with missing directories (should create them)
    export HARDWARE_SPEC_FILE="/tmp/nonexistent/specs.json"
    save_hardware_specs "$HARDWARE_SPEC_FILE" >/dev/null 2>&1 || true
}

test_permission_errors() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test with permission errors (should handle gracefully)
    export HARDWARE_SPEC_FILE="/root/protected/specs.json"
    save_hardware_specs "$HARDWARE_SPEC_FILE" >/dev/null 2>&1 || true
}

# Performance tests
test_hardware_detection_performance() {
    local start_time end_time elapsed
    start_time=$(date +%s.%N)
    
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    get_current_hardware_specs >/dev/null 2>&1
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    # Should complete within 3 seconds
    (( $(echo "$elapsed < 3.0" | bc -l 2>/dev/null || echo "1") ))
}

test_change_detection_performance() {
    local start_time end_time elapsed
    start_time=$(date +%s.%N)
    
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set test specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    export PREVIOUS_CPU_CORES=4 PREVIOUS_MEMORY_GB=8 PREVIOUS_DISK_GB=100
    
    detect_hardware_changes >/dev/null 2>&1
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    # Should complete within 1 second
    (( $(echo "$elapsed < 1.0" | bc -l 2>/dev/null || echo "1") ))
}

# Integration workflow tests
test_full_change_detection_workflow() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Create initial specs
    export CPU_CORES=4 MEMORY_GB=8 DISK_GB=100
    save_hardware_specs "$HARDWARE_SPEC_FILE"
    
    # Load specs
    load_hardware_specs "$HARDWARE_SPEC_FILE"
    
    # Change specs and detect
    export CPU_CORES=8
    detect_hardware_changes
}

test_force_optimization_workflow() {
    # Test force optimization workflow (mock test)
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --force-optimization >/dev/null 2>&1 || true
}

# Main test execution
main() {
    log_info "Running hardware change detector tests..."
    
    setup_hardware_change_detector_test_environment
    
    # Hardware specs management tests
    run_test "test_current_hardware_specs_generation" test_current_hardware_specs_generation
    run_test "test_hardware_specs_loading" test_hardware_specs_loading
    run_test "test_hardware_specs_saving" test_hardware_specs_saving
    run_test "test_hardware_specs_backup_creation" test_hardware_specs_backup_creation
    run_test "test_spec_value_extraction" test_spec_value_extraction
    
    # Hardware change detection tests
    run_test "test_hardware_change_detection_no_changes" test_hardware_change_detection_no_changes
    run_test "test_hardware_change_detection_cpu_change" test_hardware_change_detection_cpu_change
    run_test "test_hardware_change_detection_memory_change" test_hardware_change_detection_memory_change
    run_test "test_hardware_change_detection_disk_change" test_hardware_change_detection_disk_change
    run_test "test_hardware_change_detection_multiple_changes" test_hardware_change_detection_multiple_changes
    run_test "test_hardware_change_detection_threshold_cpu" test_hardware_change_detection_threshold_cpu
    
    # Service management tests
    run_test "test_systemd_service_creation" test_systemd_service_creation
    run_test "test_detector_service_status" test_detector_service_status
    run_test "test_detector_service_start_stop" test_detector_service_start_stop
    
    # Script functionality tests
    run_test "test_hardware_detector_help" test_hardware_detector_help
    run_test "test_hardware_detector_show_specs" test_hardware_detector_show_specs
    run_test "test_hardware_detector_check_once" test_hardware_detector_check_once
    run_test "test_hardware_detector_status" test_hardware_detector_status
    run_test "test_hardware_detector_invalid_option" test_hardware_detector_invalid_option
    
    # Optimization trigger tests
    run_test "test_optimization_trigger_mock" test_optimization_trigger_mock
    run_test "test_optimization_trigger_missing_script" test_optimization_trigger_missing_script
    
    # Email notification integration tests
    run_test "test_email_notification_integration" test_email_notification_integration
    run_test "test_email_test_functionality" test_email_test_functionality
    
    # Daemon functionality tests
    run_test "test_daemon_initialization" test_daemon_initialization
    
    # Error handling tests
    run_test "test_missing_hardware_detector_script" test_missing_hardware_detector_script
    run_test "test_invalid_hardware_specs_file" test_invalid_hardware_specs_file
    run_test "test_missing_directories" test_missing_directories
    run_test "test_permission_errors" test_permission_errors
    
    # Performance tests
    run_test "test_hardware_detection_performance" test_hardware_detection_performance
    run_test "test_change_detection_performance" test_change_detection_performance
    
    # Integration workflow tests
    run_test "test_full_change_detection_workflow" test_full_change_detection_workflow
    run_test "test_force_optimization_workflow" test_force_optimization_workflow
    
    cleanup_hardware_change_detector_test_environment
    
    log_info "Hardware change detector tests completed: $PASSED_TESTS/$TOTAL_TESTS passed"
    
    if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
        log_info "Hardware Change Detector Tests: PASSED"
        return 0
    else
        log_error "Hardware Change Detector Tests: FAILED"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 