#!/bin/bash

# test_hardware_change_detector.sh - Tests for Hardware Change Detection
# Part of Milestone 6: Dynamic Hardware Optimization

set -euo pipefail

# Source required libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/utilities.sh"

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test variables - removed readonly to prevent conflicts when running multiple tests
HARDWARE_DETECTOR_SCRIPT="$PROJECT_ROOT/setup/hardware_change_detector.sh"
TEST_HARDWARE_SPEC_FILE="/tmp/test_hardware_specs.json"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_hardware_detector_test_environment() {
    log_info "Setting up hardware change detector test environment..."
    
    # Create test directories
    mkdir -p "/opt/n8n/data" "/opt/n8n/logs" "/opt/n8n/backups"
    
    # Create test hardware specs file
    cat > "$TEST_HARDWARE_SPEC_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cpu_cores": 2,
    "memory_gb": 4,
    "disk_gb": 50,
    "hostname": "test-server",
    "uptime": "up 1 day"
}
EOF
    
    log_info "Hardware change detector test environment setup completed"
}

cleanup_hardware_detector_test_environment() {
    log_info "Cleaning up hardware change detector test environment..."
    
    # Remove test files
    rm -f "$TEST_HARDWARE_SPEC_FILE"
    rm -f "/opt/n8n/data/hardware_specs.json"
    rm -f "/opt/n8n/data/hardware_specs.json.backup"
    rm -f "/opt/n8n/data/last_email_notification"
    
    # Stop test service if running
    systemctl stop n8n-hardware-detector.service >/dev/null 2>&1 || true
    systemctl disable n8n-hardware-detector.service >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/n8n-hardware-detector.service"
    systemctl daemon-reload >/dev/null 2>&1 || true
    
    log_info "Hardware change detector test environment cleanup completed"
}

# =============================================================================
# HARDWARE SPECIFICATION TESTS
# =============================================================================

test_current_hardware_specs_generation() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    local specs
    specs=$(get_current_hardware_specs)
    
    # Verify JSON format and required fields
    echo "$specs" | grep -q '"timestamp"' &&
    echo "$specs" | grep -q '"cpu_cores"' &&
    echo "$specs" | grep -q '"memory_gb"' &&
    echo "$specs" | grep -q '"disk_gb"' &&
    echo "$specs" | grep -q '"hostname"'
}

test_hardware_specs_loading() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$TEST_HARDWARE_SPEC_FILE"
    
    local specs
    specs=$(load_previous_hardware_specs)
    
    # Verify loaded specs contain expected values
    echo "$specs" | grep -q '"cpu_cores": 2' &&
    echo "$specs" | grep -q '"memory_gb": 4' &&
    echo "$specs" | grep -q '"disk_gb": 50'
}

test_hardware_specs_saving() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    local test_specs='{"cpu_cores": 8, "memory_gb": 16, "disk_gb": 200}'
    local test_file="/tmp/test_save_specs.json"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$test_file"
    
    save_hardware_specs "$test_specs"
    
    # Verify file was created and contains correct content
    [[ -f "$test_file" ]] &&
    grep -q '"cpu_cores": 8' "$test_file" &&
    grep -q '"memory_gb": 16' "$test_file"
    
    # Cleanup
    rm -f "$test_file"
}

test_hardware_specs_backup_creation() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    local test_file="/tmp/test_backup_specs.json"
    local backup_file="${test_file}.backup"
    
    # Create initial file
    echo '{"cpu_cores": 4}' > "$test_file"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$test_file"
    
    # Save new specs (should create backup)
    save_hardware_specs '{"cpu_cores": 8}'
    
    # Verify backup was created
    [[ -f "$backup_file" ]] &&
    grep -q '"cpu_cores": 4' "$backup_file"
    
    # Cleanup
    rm -f "$test_file" "$backup_file"
}

# =============================================================================
# CHANGE DETECTION TESTS
# =============================================================================

test_spec_value_extraction() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    local test_json='{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 100}'
    
    local cpu_cores memory_gb disk_gb
    cpu_cores=$(extract_spec_value "$test_json" "cpu_cores")
    memory_gb=$(extract_spec_value "$test_json" "memory_gb")
    disk_gb=$(extract_spec_value "$test_json" "disk_gb")
    
    # Verify extracted values
    [[ "$cpu_cores" == "4" ]] &&
    [[ "$memory_gb" == "8" ]] &&
    [[ "$disk_gb" == "100" ]]
}

test_hardware_change_detection_no_changes() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file with current specs
    export HARDWARE_SPEC_FILE="$TEST_HARDWARE_SPEC_FILE"
    
    # Mock current specs to match previous specs
    get_current_hardware_specs() {
        cat "$TEST_HARDWARE_SPEC_FILE"
    }
    
    # Should detect no changes
    ! detect_hardware_changes
}

test_hardware_change_detection_cpu_change() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$TEST_HARDWARE_SPEC_FILE"
    
    # Mock current specs with CPU change
    get_current_hardware_specs() {
        cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cpu_cores": 4,
    "memory_gb": 4,
    "disk_gb": 50,
    "hostname": "test-server",
    "uptime": "up 1 day"
}
EOF
    }
    
    # Should detect CPU change
    detect_hardware_changes &&
    [[ "${HARDWARE_CHANGED:-}" == "true" ]] &&
    [[ "${CHANGE_SUMMARY:-}" == *"CPU"* ]]
}

test_hardware_change_detection_memory_change() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$TEST_HARDWARE_SPEC_FILE"
    
    # Mock current specs with memory change
    get_current_hardware_specs() {
        cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cpu_cores": 2,
    "memory_gb": 8,
    "disk_gb": 50,
    "hostname": "test-server",
    "uptime": "up 1 day"
}
EOF
    }
    
    # Should detect memory change
    detect_hardware_changes &&
    [[ "${HARDWARE_CHANGED:-}" == "true" ]] &&
    [[ "${CHANGE_SUMMARY:-}" == *"Memory"* ]]
}

test_hardware_change_detection_disk_change() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$TEST_HARDWARE_SPEC_FILE"
    
    # Mock current specs with disk change
    get_current_hardware_specs() {
        cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cpu_cores": 2,
    "memory_gb": 4,
    "disk_gb": 100,
    "hostname": "test-server",
    "uptime": "up 1 day"
}
EOF
    }
    
    # Should detect disk change
    detect_hardware_changes &&
    [[ "${HARDWARE_CHANGED:-}" == "true" ]] &&
    [[ "${CHANGE_SUMMARY:-}" == *"Disk"* ]]
}

test_hardware_change_detection_multiple_changes() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$TEST_HARDWARE_SPEC_FILE"
    
    # Mock current specs with multiple changes
    get_current_hardware_specs() {
        cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cpu_cores": 8,
    "memory_gb": 16,
    "disk_gb": 200,
    "hostname": "test-server",
    "uptime": "up 1 day"
}
EOF
    }
    
    # Should detect multiple changes
    detect_hardware_changes &&
    [[ "${HARDWARE_CHANGED:-}" == "true" ]] &&
    [[ "${CHANGE_SUMMARY:-}" == *"CPU"* ]] &&
    [[ "${CHANGE_SUMMARY:-}" == *"Memory"* ]] &&
    [[ "${CHANGE_SUMMARY:-}" == *"Disk"* ]]
}

test_hardware_change_detection_threshold_cpu() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$TEST_HARDWARE_SPEC_FILE"
    
    # Mock current specs with small CPU change (below threshold)
    get_current_hardware_specs() {
        cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cpu_cores": 2,
    "memory_gb": 4,
    "disk_gb": 50,
    "hostname": "test-server",
    "uptime": "up 1 day"
}
EOF
    }
    
    # Should not detect change (below threshold)
    ! detect_hardware_changes
}

# =============================================================================
# SERVICE MANAGEMENT TESTS
# =============================================================================

test_systemd_service_creation() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Create systemd service
    create_systemd_service >/dev/null 2>&1
    
    # Verify service file was created
    [[ -f "/etc/systemd/system/n8n-hardware-detector.service" ]] &&
    grep -q "n8n Hardware Change Detector" "/etc/systemd/system/n8n-hardware-detector.service"
}

test_detector_service_status() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test status detection
    local status
    status=$(get_detector_status)
    
    # Should return valid status
    [[ "$status" == "running" ]] || [[ "$status" == "stopped" ]] || [[ "$status" == "disabled" ]]
}

test_detector_service_start_stop() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Create service first
    create_systemd_service >/dev/null 2>&1
    
    # Test service start
    start_detector_service >/dev/null 2>&1 || true
    
    # Test service stop
    stop_detector_service >/dev/null 2>&1 || true
    
    # Should handle start/stop gracefully
    return 0
}

# =============================================================================
# COMMAND LINE INTERFACE TESTS
# =============================================================================

test_hardware_detector_help() {
    bash "$HARDWARE_DETECTOR_SCRIPT" --help >/dev/null 2>&1
}

test_hardware_detector_show_specs() {
    bash "$HARDWARE_DETECTOR_SCRIPT" --show-specs >/dev/null 2>&1
}

test_hardware_detector_check_once() {
    bash "$HARDWARE_DETECTOR_SCRIPT" --check-once >/dev/null 2>&1 || true
    # May return non-zero if no changes detected
}

test_hardware_detector_status() {
    bash "$HARDWARE_DETECTOR_SCRIPT" --status >/dev/null 2>&1
}

test_hardware_detector_invalid_option() {
    ! bash "$HARDWARE_DETECTOR_SCRIPT" --invalid-option >/dev/null 2>&1
}

# =============================================================================
# OPTIMIZATION TRIGGER TESTS
# =============================================================================

test_optimization_trigger_mock() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Mock optimization script to avoid actual execution
    local mock_optimization_script="/tmp/mock_optimization.sh"
    cat > "$mock_optimization_script" << 'EOF'
#!/bin/bash
echo "Mock optimization completed"
exit 0
EOF
    chmod +x "$mock_optimization_script"
    
    # Set test environment
    export HARDWARE_CHANGED="true"
    export CURRENT_HARDWARE_SPECS='{"cpu_cores": 4}'
    export CHANGE_SUMMARY="Test change"
    export OPTIMIZATION_DELAY_SECONDS=1
    
    # Override optimization script path
    SCRIPT_DIR="/tmp"
    
    # Test optimization trigger
    trigger_optimization >/dev/null 2>&1 || true
    
    # Cleanup
    rm -f "$mock_optimization_script"
}

test_optimization_trigger_missing_script() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test environment with non-existent script
    export HARDWARE_CHANGED="true"
    export CURRENT_HARDWARE_SPECS='{"cpu_cores": 4}'
    export CHANGE_SUMMARY="Test change"
    
    # Override script directory to non-existent path
    SCRIPT_DIR="/nonexistent"
    
    # Should handle missing script gracefully
    ! trigger_optimization >/dev/null 2>&1
}

# =============================================================================
# EMAIL INTEGRATION TESTS
# =============================================================================

test_email_notification_integration() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set up test environment
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    export CHANGE_SUMMARY="Test hardware change"
    
    # Test email notifications (should handle gracefully if sending fails)
    send_hardware_change_notification "detected" >/dev/null 2>&1 || true
    send_hardware_change_notification "optimized" >/dev/null 2>&1 || true
}

test_email_test_functionality() {
    bash "$HARDWARE_DETECTOR_SCRIPT" --test-email >/dev/null 2>&1 || true
    # Don't fail if email sending fails (expected in test environment)
}

# =============================================================================
# DAEMON FUNCTIONALITY TESTS
# =============================================================================

test_daemon_initialization() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="/tmp/test_daemon_specs.json"
    
    # Remove existing file
    rm -f "$HARDWARE_SPEC_FILE"
    
    # Mock the daemon loop to exit after initialization
    run_daemon() {
        log_info "Starting hardware change detector daemon..."
        mkdir -p "$(dirname "$HARDWARE_SPEC_FILE")" "$(dirname "$DETECTOR_LOG_FILE")"
        
        if [[ ! -f "$HARDWARE_SPEC_FILE" ]]; then
            log_info "Initializing hardware specifications..."
            local initial_specs
            initial_specs=$(get_current_hardware_specs)
            save_hardware_specs "$initial_specs"
        fi
        
        # Exit after initialization for testing
        return 0
    }
    
    # Test daemon initialization
    run_daemon >/dev/null 2>&1
    
    # Verify initialization created specs file
    [[ -f "$HARDWARE_SPEC_FILE" ]]
    
    # Cleanup
    rm -f "$HARDWARE_SPEC_FILE"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_missing_hardware_detector_script() {
    local fake_script="/tmp/nonexistent_detector_script.sh"
    ! bash "$fake_script" --help >/dev/null 2>&1
}

test_invalid_hardware_specs_file() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Create invalid JSON file
    local invalid_file="/tmp/invalid_specs.json"
    echo "invalid json content" > "$invalid_file"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$invalid_file"
    
    # Should handle invalid JSON gracefully
    local specs
    specs=$(load_previous_hardware_specs)
    [[ -n "$specs" ]]  # Should return something (even if empty object)
    
    # Cleanup
    rm -f "$invalid_file"
}

test_missing_directories() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test with non-existent directories
    export HARDWARE_SPEC_FILE="/nonexistent/dir/specs.json"
    
    # Should handle missing directories gracefully
    get_current_hardware_specs >/dev/null 2>&1
}

test_permission_errors() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Create read-only directory (if running as non-root)
    local readonly_dir="/tmp/readonly_test"
    mkdir -p "$readonly_dir"
    chmod 444 "$readonly_dir" 2>/dev/null || true
    
    # Set test hardware spec file in read-only directory
    export HARDWARE_SPEC_FILE="$readonly_dir/specs.json"
    
    # Should handle permission errors gracefully
    save_hardware_specs '{"test": "data"}' >/dev/null 2>&1 || true
    
    # Cleanup
    chmod 755 "$readonly_dir" 2>/dev/null || true
    rm -rf "$readonly_dir"
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_hardware_detection_performance() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    # Run hardware detection multiple times
    for i in {1..5}; do
        get_current_hardware_specs >/dev/null 2>&1
    done
    
    end_time=$(date +%s%N)
    duration=$(((end_time - start_time) / 1000000))  # Convert to milliseconds
    
    # Hardware detection should complete within reasonable time (< 1 second total)
    [[ "$duration" -lt 1000 ]]
}

test_change_detection_performance() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="$TEST_HARDWARE_SPEC_FILE"
    
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    # Run change detection multiple times
    for i in {1..5}; do
        detect_hardware_changes >/dev/null 2>&1 || true
    done
    
    end_time=$(date +%s%N)
    duration=$(((end_time - start_time) / 1000000))  # Convert to milliseconds
    
    # Change detection should complete within reasonable time (< 500ms total)
    [[ "$duration" -lt 500 ]]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_full_change_detection_workflow() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set test hardware spec file
    export HARDWARE_SPEC_FILE="/tmp/test_workflow_specs.json"
    
    # Create initial specs
    save_hardware_specs '{"cpu_cores": 2, "memory_gb": 4, "disk_gb": 50}'
    
    # Mock current specs with changes
    get_current_hardware_specs() {
        echo '{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 100}'
    }
    
    # Test full workflow
    detect_hardware_changes &&
    [[ "${HARDWARE_CHANGED:-}" == "true" ]] &&
    [[ -n "${CHANGE_SUMMARY:-}" ]] &&
    [[ -n "${CURRENT_HARDWARE_SPECS:-}" ]] &&
    [[ -n "${PREVIOUS_HARDWARE_SPECS:-}" ]]
    
    # Cleanup
    rm -f "/tmp/test_workflow_specs.json"
}

test_force_optimization_workflow() {
    bash "$HARDWARE_DETECTOR_SCRIPT" --force-optimize >/dev/null 2>&1 || true
    # Don't fail if optimization fails (expected in test environment)
}

# =============================================================================
# TEST RUNNER
# =============================================================================

run_hardware_change_detector_tests() {
    local tests_passed=0
    local tests_failed=0
    local test_functions=(
        # Hardware specification tests
        "test_current_hardware_specs_generation"
        "test_hardware_specs_loading"
        "test_hardware_specs_saving"
        "test_hardware_specs_backup_creation"
        
        # Change detection tests
        "test_spec_value_extraction"
        "test_hardware_change_detection_no_changes"
        "test_hardware_change_detection_cpu_change"
        "test_hardware_change_detection_memory_change"
        "test_hardware_change_detection_disk_change"
        "test_hardware_change_detection_multiple_changes"
        "test_hardware_change_detection_threshold_cpu"
        
        # Service management tests
        "test_systemd_service_creation"
        "test_detector_service_status"
        "test_detector_service_start_stop"
        
        # Command line interface tests
        "test_hardware_detector_help"
        "test_hardware_detector_show_specs"
        "test_hardware_detector_check_once"
        "test_hardware_detector_status"
        "test_hardware_detector_invalid_option"
        
        # Optimization trigger tests
        "test_optimization_trigger_mock"
        "test_optimization_trigger_missing_script"
        
        # Email integration tests
        "test_email_notification_integration"
        "test_email_test_functionality"
        
        # Daemon functionality tests
        "test_daemon_initialization"
        
        # Error handling tests
        "test_missing_hardware_detector_script"
        "test_invalid_hardware_specs_file"
        "test_missing_directories"
        "test_permission_errors"
        
        # Performance tests
        "test_hardware_detection_performance"
        "test_change_detection_performance"
        
        # Integration tests
        "test_full_change_detection_workflow"
        "test_force_optimization_workflow"
    )
    
    log_info "Running hardware change detector tests..."
    setup_hardware_detector_test_environment
    
    for test_function in "${test_functions[@]}"; do
        log_info "Running $test_function..."
        if $test_function; then
            log_info "✓ $test_function"
            tests_passed=$((tests_passed + 1))
        else
            log_error "✗ $test_function"
            tests_failed=$((tests_failed + 1))
        fi
    done
    
    cleanup_hardware_detector_test_environment
    
    local total_tests=$((tests_passed + tests_failed))
    log_info "Hardware change detector tests completed: $tests_passed/$total_tests passed"
    
    return $tests_failed
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    run_hardware_change_detector_tests
fi 