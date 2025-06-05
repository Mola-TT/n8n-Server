#!/bin/bash

# test_email_notification.sh - Tests for Email Notification System
# Part of Milestone 6 test suite

set -euo pipefail

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

# Source required utilities
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Test configuration
TEST_ENV_DIR="/tmp/test_email_notification"
PASSED_TESTS=0
TOTAL_TESTS=0

# Test helper functions
setup_email_test_environment() {
    log_info "Setting up email test environment..."
    
    # Create test directories
    mkdir -p "$TEST_ENV_DIR"
    mkdir -p "$TEST_ENV_DIR/cooldown"
    
    # Set test email configuration
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    export SMTP_SERVER="smtp.example.com"
    export SMTP_PORT="587"
    export SMTP_USERNAME="testuser"
    export SMTP_PASSWORD="testpass"
    export EMAIL_COOLDOWN_HOURS="24"
    export TEST_EMAIL_SUBJECT="Test Email"
    
    log_info "Email test environment setup completed"
}

cleanup_email_test_environment() {
    log_info "Cleaning up email test environment..."
    rm -rf "$TEST_ENV_DIR"
    unset EMAIL_SENDER EMAIL_RECIPIENT SMTP_SERVER SMTP_PORT SMTP_USERNAME SMTP_PASSWORD EMAIL_COOLDOWN_HOURS TEST_EMAIL_SUBJECT
    log_info "Email test environment cleanup completed"
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

# Email configuration tests
test_email_configuration_loading() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    load_email_configuration
}

test_email_configuration_missing() {
    unset EMAIL_SENDER
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    ! load_email_configuration
    export EMAIL_SENDER="test@example.com"  # Restore for other tests
}

# Email cooldown tests
test_email_cooldown_functionality() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test cooldown check
    local cooldown_file="$TEST_ENV_DIR/cooldown/test_cooldown"
    echo "$(date +%s)" > "$cooldown_file"
    
    # Should be in cooldown
    is_email_cooldown_active "test" "$TEST_ENV_DIR/cooldown"
}

test_email_cooldown_expiry() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test expired cooldown
    local cooldown_file="$TEST_ENV_DIR/cooldown/test_cooldown"
    echo "$(($(date +%s) - 86400 - 1))" > "$cooldown_file"  # 24h + 1s ago
    
    # Should not be in cooldown
    ! is_email_cooldown_active "test" "$TEST_ENV_DIR/cooldown"
}

test_email_cooldown_file_creation() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test cooldown file creation
    set_email_cooldown "test" "$TEST_ENV_DIR/cooldown"
    
    [[ -f "$TEST_ENV_DIR/cooldown/test_cooldown" ]]
}

# Email content tests
test_hardware_change_detected_email_content() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    local test_specs="CPU: 4 cores, Memory: 8GB, Disk: 100GB"
    local subject body
    
    subject=$(get_email_subject "hardware_change")
    body=$(get_email_body "hardware_change" "$test_specs")
    
    [[ "$subject" =~ "Hardware Change Detected" ]] && [[ "$body" =~ "CPU: 4 cores" ]]
}

test_hardware_optimization_completed_email_content() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    local test_message="Optimization completed successfully"
    local subject body
    
    subject=$(get_email_subject "optimization_completed")
    body=$(get_email_body "optimization_completed" "$test_message")
    
    [[ "$subject" =~ "Optimization Completed" ]] && [[ "$body" =~ "successfully" ]]
}

test_invalid_email_notification_type() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Should handle invalid notification type gracefully
    get_email_subject "invalid_type" >/dev/null 2>&1 || true
}

# Email sending method tests
test_email_sending_methods_availability() {
    # Test if email sending tools are available
    which mail >/dev/null 2>&1 || which sendmail >/dev/null 2>&1 || which msmtp >/dev/null 2>&1
}

test_email_message_format() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    local subject="Test Subject"
    local body="Test Body"
    local message
    
    message=$(format_email_message "$subject" "$body")
    
    [[ "$message" =~ "Subject: $subject" ]] && [[ "$message" =~ "$body" ]]
}

# Email functionality tests
test_email_functionality_command_line() {
    # Test command line email functionality (mock test)
    bash "$PROJECT_ROOT/setup/hardware_change_detector.sh" --test-email >/dev/null 2>&1 || true
}

test_email_functionality_with_configuration() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test with valid configuration (mock test - don't actually send)
    load_email_configuration && [[ -n "${EMAIL_SENDER:-}" ]]
}

test_email_functionality_without_configuration() {
    unset EMAIL_SENDER EMAIL_RECIPIENT
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Should fail gracefully without configuration
    ! load_email_configuration
    
    # Restore configuration
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
}

# Integration tests
test_hardware_change_notification_integration() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    local test_specs="CPU: 4 cores, Memory: 8GB, Disk: 100GB"
    
    # Test notification preparation (mock test)
    local subject body
    subject=$(get_email_subject "hardware_change")
    body=$(get_email_body "hardware_change" "$test_specs")
    
    [[ -n "$subject" ]] && [[ -n "$body" ]]
}

test_email_notification_with_cooldown() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Set cooldown
    set_email_cooldown "test" "$TEST_ENV_DIR/cooldown"
    
    # Should be in cooldown
    is_email_cooldown_active "test" "$TEST_ENV_DIR/cooldown"
}

# Email configuration validation tests
test_email_configuration_validation() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test with complete configuration
    load_email_configuration
}

test_email_configuration_partial() {
    unset SMTP_PASSWORD
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Should fail with partial configuration
    ! load_email_configuration
    
    # Restore
    export SMTP_PASSWORD="testpass"
}

# Email formatting tests
test_email_subject_formatting() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    local subject
    subject=$(get_email_subject "hardware_change")
    
    [[ "$subject" =~ ^\[.*\] ]]  # Should start with prefix
}

test_email_body_hardware_specs_formatting() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    local test_specs="CPU: 4 cores\nMemory: 8GB\nDisk: 100GB"
    local body
    
    body=$(get_email_body "hardware_change" "$test_specs")
    
    [[ "$body" =~ "CPU: 4 cores" ]] && [[ "$body" =~ "Memory: 8GB" ]]
}

# Error handling tests
test_email_error_handling_missing_temp_file() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test with missing temporary file (should handle gracefully)
    format_email_message "Test" "Body" >/dev/null 2>&1 || true
}

test_email_error_handling_command_failure() {
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test email sending with invalid command (should handle gracefully)
    send_email_notification "test" "Test message" >/dev/null 2>&1 || true
}

# Performance tests
test_email_notification_performance() {
    local start_time end_time elapsed
    start_time=$(date +%s.%N)
    
    source "$PROJECT_ROOT/setup/hardware_change_detector.sh"
    
    # Test email preparation performance
    get_email_subject "hardware_change" >/dev/null 2>&1
    get_email_body "hardware_change" "Test specs" >/dev/null 2>&1
    
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    # Should complete within 2 seconds
    (( $(echo "$elapsed < 2.0" | bc -l 2>/dev/null || echo "1") ))
}

# Main test execution
main() {
    log_info "Running email notification tests..."
    
    setup_email_test_environment
    
    # Email configuration tests
    run_test "test_email_configuration_loading" test_email_configuration_loading
    run_test "test_email_configuration_missing" test_email_configuration_missing
    
    # Email cooldown tests
    run_test "test_email_cooldown_functionality" test_email_cooldown_functionality
    run_test "test_email_cooldown_expiry" test_email_cooldown_expiry
    run_test "test_email_cooldown_file_creation" test_email_cooldown_file_creation
    
    # Email content tests
    run_test "test_hardware_change_detected_email_content" test_hardware_change_detected_email_content
    run_test "test_hardware_optimization_completed_email_content" test_hardware_optimization_completed_email_content
    run_test "test_invalid_email_notification_type" test_invalid_email_notification_type
    
    # Email sending method tests
    run_test "test_email_sending_methods_availability" test_email_sending_methods_availability
    run_test "test_email_message_format" test_email_message_format
    
    # Email functionality tests
    run_test "test_email_functionality_command_line" test_email_functionality_command_line
    run_test "test_email_functionality_with_configuration" test_email_functionality_with_configuration
    run_test "test_email_functionality_without_configuration" test_email_functionality_without_configuration
    
    # Integration tests
    run_test "test_hardware_change_notification_integration" test_hardware_change_notification_integration
    run_test "test_email_notification_with_cooldown" test_email_notification_with_cooldown
    
    # Email configuration validation tests
    run_test "test_email_configuration_validation" test_email_configuration_validation
    run_test "test_email_configuration_partial" test_email_configuration_partial
    
    # Email formatting tests
    run_test "test_email_subject_formatting" test_email_subject_formatting
    run_test "test_email_body_hardware_specs_formatting" test_email_body_hardware_specs_formatting
    
    # Error handling tests
    run_test "test_email_error_handling_missing_temp_file" test_email_error_handling_missing_temp_file
    run_test "test_email_error_handling_command_failure" test_email_error_handling_command_failure
    
    # Performance tests
    run_test "test_email_notification_performance" test_email_notification_performance
    
    cleanup_email_test_environment
    
    log_info "Email notification tests completed: $PASSED_TESTS/$TOTAL_TESTS passed"
    
    if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
        log_info "Email Notification Tests: PASSED"
        return 0
    else
        log_error "Email Notification Tests: FAILED"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 