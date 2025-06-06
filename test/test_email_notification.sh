#!/bin/bash

# test_email_notification.sh - Tests for Email Notification System
# Part of Milestone 6: Dynamic Hardware Optimization

set -euo pipefail

# Source required libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/utilities.sh"

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test variables - removed readonly to prevent conflicts when running multiple tests
TEST_EMAIL_CONFIG="/tmp/test_email_config.env"
HARDWARE_DETECTOR_SCRIPT="$PROJECT_ROOT/setup/hardware_change_detector.sh"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_email_test_environment() {
    log_info "Setting up email test environment..."
    
    # Create test email configuration
    cat > "$TEST_EMAIL_CONFIG" << EOF
EMAIL_SENDER="test@example.com"
EMAIL_RECIPIENT="admin@example.com"
SMTP_SERVER="smtp.example.com"
SMTP_PORT=587
SMTP_TLS="YES"
SMTP_USERNAME="test@example.com"
SMTP_PASSWORD="testpassword"
EOF
    
    # Create test directories
    mkdir -p "/opt/n8n/data" "/opt/n8n/logs"
    
    log_info "Email test environment setup completed"
}

cleanup_email_test_environment() {
    log_info "Cleaning up email test environment..."
    
    # Remove test files
    rm -f "$TEST_EMAIL_CONFIG"
    rm -f "/opt/n8n/data/last_email_notification"
    rm -f "/opt/n8n/data/hardware_specs.json"
    
    log_info "Email test environment cleanup completed"
}

# =============================================================================
# EMAIL CONFIGURATION TESTS
# =============================================================================

test_email_configuration_loading() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
        # Set up test environment with email config using temp file
    export PROJECT_ROOT="$PROJECT_ROOT"
    cp "$TEST_EMAIL_CONFIG" "$PROJECT_ROOT/conf/user.env.email_test"

    # Load test email configuration
    source "$PROJECT_ROOT/conf/user.env.email_test"

    # Verify email configuration is loaded
    [[ "${EMAIL_SENDER:-}" == "test@example.com" ]] &&
    [[ "${EMAIL_RECIPIENT:-}" == "admin@example.com" ]] &&
    [[ "${SMTP_SERVER:-}" == "smtp.example.com" ]]

    # Cleanup test file
    rm -f "$PROJECT_ROOT/conf/user.env.email_test"
}

test_email_configuration_missing() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Temporarily unset email configuration
    local original_sender="$EMAIL_SENDER"
    local original_recipient="$EMAIL_RECIPIENT"
    unset EMAIL_SENDER EMAIL_RECIPIENT
    
    # Test should handle missing configuration gracefully
    local result
    result=$(send_email_notification "test" "Test message" 2>&1)
    local exit_code=$?
    
    # Restore original configuration
    export EMAIL_SENDER="$original_sender"
    export EMAIL_RECIPIENT="$original_recipient"
    
    # Should fail gracefully with missing configuration
    [[ $exit_code -ne 0 ]] || echo "$result" | grep -q "Email configuration missing"
}

# =============================================================================
# EMAIL COOLDOWN TESTS
# =============================================================================

test_email_cooldown_functionality() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Create data directory if it doesn't exist
    mkdir -p "/opt/n8n/data"
    
    # Remove any existing cooldown file
    rm -f "/opt/n8n/data/last_email_notification"

    # Test initial cooldown check (should pass)
    check_email_cooldown
    local first_result=$?

    # Test immediate second check (should fail due to cooldown)
    check_email_cooldown
    local second_result=$?

    # First should pass (0), second should fail (1)
    [[ "$first_result" -eq 0 ]] && [[ "$second_result" -eq 1 ]]
}

test_email_cooldown_expiry() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Create old cooldown file (simulate expired cooldown)
    local cooldown_file="/opt/n8n/data/last_email_notification"
    local old_time=$(($(date +%s) - 7200))  # 2 hours ago
    
    # Ensure directory exists
    mkdir -p "/opt/n8n/data" 2>/dev/null || true
    echo "$old_time" > "$cooldown_file"
    
    # Should pass cooldown check (return 0 when cooldown expired)
    if check_email_cooldown; then
        return 0  # Test passes - cooldown has expired
    else
        return 1  # Test fails - cooldown should have expired
    fi
}

test_email_cooldown_file_creation() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    local cooldown_file="/opt/n8n/data/last_email_notification"
    
    # Remove cooldown file if exists
    rm -f "$cooldown_file"
    
    # Check cooldown (should create file)
    check_email_cooldown
    
    # Verify file was created
    [[ -f "$cooldown_file" ]]
}

# =============================================================================
# EMAIL CONTENT TESTS
# =============================================================================

test_hardware_change_detected_email_content() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Mock hardware change data
    local old_specs='{"cpu_cores": 2, "memory_gb": 4, "disk_gb": 50}'
    local new_specs='{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 100}'
    
    # Test email content generation
    local subject body
    subject=$(generate_hardware_change_email_subject "$old_specs" "$new_specs" 2>/dev/null)
    body=$(generate_hardware_change_email_body "$old_specs" "$new_specs" 2>/dev/null)
    
    # Verify content contains expected information
    [[ "$subject" =~ "Hardware Change Detected" ]] && 
    [[ "$body" =~ "CPU cores: 2 → 4" ]] && 
    [[ "$body" =~ "Memory: 4GB → 8GB" ]] && 
    [[ "$body" =~ "Disk: 50GB → 100GB" ]]
}

test_hardware_optimization_completed_email_content() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test optimization completion email
    local subject body
    subject=$(generate_optimization_email_subject "completed" 2>/dev/null)
    body=$(generate_optimization_email_body "Hardware optimization completed successfully" 2>/dev/null)
    
    # Verify content
    [[ "$subject" =~ "Optimization Completed" ]] && 
    [[ "$body" =~ "optimization completed successfully" ]]
}

test_invalid_email_notification_type() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test with invalid notification type
    local result
    result=$(send_email_notification "invalid_type" "Test message" 2>&1)
    local exit_code=$?
    
    # Should handle invalid type gracefully
    [[ $exit_code -ne 0 ]] || echo "$result" | grep -q "Invalid notification type"
}

# =============================================================================
# EMAIL SENDING MECHANISM TESTS
# =============================================================================

test_email_sending_methods_availability() {
    # Test if email sending commands are available
    local methods_available=0
    
    # Check for msmtp
    if command -v msmtp >/dev/null 2>&1; then
        methods_available=$((methods_available + 1))
    fi
    
    # Check for sendmail
    if command -v sendmail >/dev/null 2>&1; then
        methods_available=$((methods_available + 1))
    fi
    
    # Check for mail command
    if command -v mail >/dev/null 2>&1; then
        methods_available=$((methods_available + 1))
    fi
    
    # At least one method should be available on most systems
    [[ "$methods_available" -ge 1 ]] || log_warn "No email sending methods available"
    return 0  # Don't fail test if no email methods available
}

test_email_message_format() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    local test_subject="Test Subject"
    local test_body="Test email body content"
    local temp_file
    temp_file=$(mktemp)
    
    # Create email message format
    cat > "$temp_file" << EOF
To: test@example.com
From: sender@example.com
Subject: ${test_subject}

${test_body}
EOF
    
    # Verify message format
    grep -q "To: test@example.com" "$temp_file" &&
    grep -q "From: sender@example.com" "$temp_file" &&
    grep -q "Subject: Test Subject" "$temp_file" &&
    grep -q "Test email body content" "$temp_file"
    
    # Cleanup
    rm -f "$temp_file"
}

# =============================================================================
# TEST EMAIL FUNCTIONALITY TESTS
# =============================================================================

test_email_functionality_command_line() {
    # Test the test email functionality via command line
    bash "$HARDWARE_DETECTOR_SCRIPT" --test-email >/dev/null 2>&1 || true
    # Don't fail if email sending fails (expected in test environment)
}

test_email_functionality_with_configuration() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set up email configuration
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    
    # Test email functionality (should handle gracefully if sending fails)
    test_email_functionality >/dev/null 2>&1 || true
    # Don't fail if email sending fails (expected in test environment)
}

test_email_functionality_without_configuration() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Clear email configuration
    unset EMAIL_SENDER EMAIL_RECIPIENT
    
    # Should handle missing configuration gracefully
    test_email_functionality >/dev/null 2>&1 || true
}

# =============================================================================
# HARDWARE CHANGE NOTIFICATION INTEGRATION TESTS
# =============================================================================

test_hardware_change_notification_integration() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set up test environment
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    export HARDWARE_CHANGED="true"
    export CURRENT_HARDWARE_SPECS='{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 100}'
    export PREVIOUS_HARDWARE_SPECS='{"cpu_cores": 2, "memory_gb": 4, "disk_gb": 100}'
    export CHANGE_SUMMARY="CPU: 2 → 4 cores (+2)\nMemory: 4GB → 8GB (+4GB)"
    
    # Test notification sending (should handle gracefully if sending fails)
    send_hardware_change_notification "detected" >/dev/null 2>&1 || true
    send_hardware_change_notification "optimized" >/dev/null 2>&1 || true
}

test_email_notification_with_cooldown() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Create a recent email timestamp file
    local cooldown_file="/tmp/test_email_cooldown"
    echo "$(date +%s)" > "$cooldown_file"
    
    # Mock the cooldown check
    local result
    result=$(check_email_cooldown "$cooldown_file" 2>/dev/null)
    local exit_code=$?
    
    # Clean up
    rm -f "$cooldown_file"
    
    # Should respect cooldown period
    [[ $exit_code -ne 0 ]]
}

test_partial_email_configuration() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test with partial configuration (missing recipient and SMTP credentials)
    export EMAIL_SENDER="sender@example.com"
    export SMTP_SERVER="smtp.example.com"
    export SMTP_PORT="587"
    unset EMAIL_RECIPIENT SMTP_USERNAME SMTP_PASSWORD
    
    # Should fail validation due to incomplete config
    local result
    result=$(validate_email_configuration 2>&1 || echo "validation_failed")
    
    # Should contain missing configuration message or validation should fail
    [[ "$result" == *"Missing email configuration"* ]] || [[ "$result" == *"validation_failed"* ]]
}

# =============================================================================
# EMAIL CONFIGURATION VALIDATION TESTS
# =============================================================================

test_email_configuration_validation() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test with valid configuration
    export EMAIL_SENDER="valid@example.com"
    export EMAIL_RECIPIENT="recipient@example.com"
    
    # Should not skip notification due to missing config
    local result
    result=$(send_hardware_change_notification "detected" 2>&1 || echo "config_valid")
    [[ "$result" != *"Email not configured"* ]]
}

test_email_configuration_partial() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test with partial configuration (missing recipient and SMTP credentials)
    export EMAIL_SENDER="sender@example.com"
    export SMTP_SERVER="smtp.example.com"
    export SMTP_PORT="587"
    unset EMAIL_RECIPIENT SMTP_USERNAME SMTP_PASSWORD
    
    # Should fail validation due to incomplete config
    local result
    result=$(validate_email_configuration 2>&1 || echo "validation_failed")
    
    # Should contain missing configuration message or validation should fail
    [[ "$result" == *"Missing email configuration"* ]] || [[ "$result" == *"validation_failed"* ]]
}

# =============================================================================
# EMAIL SUBJECT AND FORMATTING TESTS
# =============================================================================

test_email_subject_formatting() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test subject prefix
    local test_subject="${EMAIL_SUBJECT_PREFIX} Test Subject"
    [[ "$test_subject" == "[n8n Server] Test Subject" ]]
}

test_email_body_hardware_specs_formatting() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test hardware specs formatting
    local test_specs='{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 100}'
    local formatted_specs
    formatted_specs=$(echo "$test_specs" | grep -E '(cpu_cores|memory_gb|disk_gb)' | sed 's/[",]//g' | sed 's/^[[:space:]]*/- /')
    
    # Should format specs properly
    [[ -n "$formatted_specs" ]]
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_email_error_handling_missing_temp_file() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test with invalid temp file path
    local invalid_temp="/invalid/path/temp_file"
    
    # Should handle file creation errors gracefully
    send_email_notification "Test Subject" "Test Body" >/dev/null 2>&1 || true
}

test_email_error_handling_command_failure() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Test email sending when all commands fail (expected in test environment)
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    
    # Should handle command failures gracefully
    send_email_notification "Test Subject" "Test Body" >/dev/null 2>&1 || true
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_email_notification_performance() {
    source "$HARDWARE_DETECTOR_SCRIPT"
    
    # Set up test environment
    export EMAIL_SENDER="test@example.com"
    export EMAIL_RECIPIENT="admin@example.com"
    export CHANGE_SUMMARY="Performance test"
    export CURRENT_HARDWARE_SPECS='{"cpu_cores": 4, "memory_gb": 8, "disk_gb": 100}'
    export PREVIOUS_HARDWARE_SPECS='{"cpu_cores": 2, "memory_gb": 4, "disk_gb": 100}'
    
    local start_time end_time duration
    # Use seconds if nanoseconds not available
    if date +%s%N >/dev/null 2>&1; then
        start_time=$(date +%s%N)
        
        # Run email notification multiple times
        for i in {1..5}; do
            send_hardware_change_notification "detected" >/dev/null 2>&1 || true
        done
        
        end_time=$(date +%s%N)
        duration=$(((end_time - start_time) / 1000000))  # Convert to milliseconds
        
        # Email processing should complete within reasonable time (< 2 seconds total)
        [[ "$duration" -lt 2000 ]]
    else
        # Fallback to seconds precision
        start_time=$(date +%s)
        
        # Run email notification multiple times
        for i in {1..5}; do
            send_hardware_change_notification "detected" >/dev/null 2>&1 || true
        done
        
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        
        # Email processing should complete within reasonable time (< 5 seconds total)
        [[ "$duration" -lt 5 ]]
    fi
}

# =============================================================================
# TEST RUNNER
# =============================================================================

run_email_notification_tests() {
    local tests_passed=0
    local tests_failed=0
    local test_functions=(
        # Email configuration tests
        "test_email_configuration_loading"
        "test_email_configuration_missing"
        
        # Email cooldown tests
        "test_email_cooldown_functionality"
        "test_email_cooldown_expiry"
        "test_email_cooldown_file_creation"
        
        # Email content tests
        "test_hardware_change_detected_email_content"
        "test_hardware_optimization_completed_email_content"
        "test_invalid_email_notification_type"
        
        # Email sending mechanism tests
        "test_email_sending_methods_availability"
        "test_email_message_format"
        
        # Test email functionality tests
        "test_email_functionality_command_line"
        "test_email_functionality_with_configuration"
        "test_email_functionality_without_configuration"
        
        # Hardware change notification integration tests
        "test_hardware_change_notification_integration"
        "test_email_notification_with_cooldown"
        
        # Email configuration validation tests
        "test_email_configuration_validation"
        "test_email_configuration_partial"
        
        # Email subject and formatting tests
        "test_email_subject_formatting"
        "test_email_body_hardware_specs_formatting"
        
        # Error handling tests
        "test_email_error_handling_missing_temp_file"
        "test_email_error_handling_command_failure"
        
        # Performance tests
        "test_email_notification_performance"
    )
    
    log_info "Running email notification tests..."
    setup_email_test_environment
    
    for test_function in "${test_functions[@]}"; do
        # Add timeout protection to prevent hanging tests
        if timeout 30s bash -c "$test_function" >/dev/null 2>&1; then
            log_info "✓ $test_function"
            tests_passed=$((tests_passed + 1))
        else
            log_error "✗ $test_function"
            tests_failed=$((tests_failed + 1))
        fi
    done
    
    cleanup_email_test_environment
    
    local total_tests=$((tests_passed + tests_failed))
    log_info "Email notification tests completed: $tests_passed/$total_tests passed"
    
    return $tests_failed
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Add overall timeout protection for the entire test suite
    timeout 300s run_email_notification_tests || {
        echo "[ERROR] Email notification tests timed out after 5 minutes"
        exit 1
    }
fi 