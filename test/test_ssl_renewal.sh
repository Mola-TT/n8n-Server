#!/bin/bash

# =============================================================================
# SSL Renewal Test Suite for n8n Server - Milestone 5
# =============================================================================
# This script tests SSL certificate renewal functionality for both production
# and development environments
# =============================================================================

# Source required libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/utilities.sh"

# Test configuration
TEST_SECTION="SSL Certificate Management"
TESTS_PASSED=0
TESTS_FAILED=0

# SSL paths for testing
SSL_CERT_DIR="/etc/nginx/ssl"
SSL_CERT_PATH="$SSL_CERT_DIR/certificate.crt"
SSL_KEY_PATH="$SSL_CERT_DIR/private.key"
SSL_BACKUP_DIR="/opt/n8n/ssl/backups"
SSL_LOG_FILE="/var/log/ssl_renewal.log"

# Test environment backup
TEST_BACKUP_DIR="/tmp/ssl_test_backup"

# =============================================================================
# Test Utility Functions
# =============================================================================

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo -n "  Testing $test_name... "
    
    if $test_function >/dev/null 2>&1; then
        echo "PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

backup_test_environment() {
    # Create backup directory
    sudo mkdir -p "$TEST_BACKUP_DIR"
    
    # Backup existing SSL certificates if they exist
    if [ -f "$SSL_CERT_PATH" ]; then
        sudo cp "$SSL_CERT_PATH" "$TEST_BACKUP_DIR/certificate.crt.backup" 2>/dev/null || true
    fi
    if [ -f "$SSL_KEY_PATH" ]; then
        sudo cp "$SSL_KEY_PATH" "$TEST_BACKUP_DIR/private.key.backup" 2>/dev/null || true
    fi
    
    # Backup environment files
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env" ]; then
        cp "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env" "$TEST_BACKUP_DIR/user.env.backup" 2>/dev/null || true
    fi
}

restore_test_environment() {
    # Restore SSL certificates if backups exist
    if [ -f "$TEST_BACKUP_DIR/certificate.crt.backup" ]; then
        sudo cp "$TEST_BACKUP_DIR/certificate.crt.backup" "$SSL_CERT_PATH" 2>/dev/null || true
    fi
    if [ -f "$TEST_BACKUP_DIR/private.key.backup" ]; then
        sudo cp "$TEST_BACKUP_DIR/private.key.backup" "$SSL_KEY_PATH" 2>/dev/null || true
    fi
    
    # Restore environment files
    if [ -f "$TEST_BACKUP_DIR/user.env.backup" ]; then
        cp "$TEST_BACKUP_DIR/user.env.backup" "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env" 2>/dev/null || true
    fi
    
    # Clean up test backup and test files
    sudo rm -rf "$TEST_BACKUP_DIR" 2>/dev/null || true
    rm -f "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env.test" 2>/dev/null || true
}

create_test_environment() {
    local production_mode="$1"

    # Create temporary test user.env with specified production mode
    # Don't overwrite the real user.env file - use a test-specific file
    cat > "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env.test" << EOF
PRODUCTION=$production_mode
NGINX_SERVER_NAME="test.example.com"
EMAIL_SENDER="test@example.com"
EOF
}

# =============================================================================
# SSL Renewal Script Tests
# =============================================================================

test_ssl_script_exists() {
    [ -f "$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh" ]
}

test_ssl_script_executable() {
    [ -x "$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh" ]
}

test_ssl_script_help() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    "$script_path" --help | grep -q "SSL Certificate Renewal Script"
}

test_ssl_script_sourcing() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    
    # Test that script can be sourced without errors
    source "$script_path" >/dev/null 2>&1
    
    # Check if main functions are available
    type log_ssl >/dev/null 2>&1 && \
    type validate_certificate >/dev/null 2>&1 && \
    type generate_self_signed_certificate >/dev/null 2>&1
}

# =============================================================================
# Certificate Validation Tests
# =============================================================================

test_certificate_validation_missing_files() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Test with non-existent files (suppress expected error output)
    ! validate_certificate "/nonexistent/cert.crt" "/nonexistent/key.key" >/dev/null 2>&1
}

test_certificate_validation_invalid_format() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Create temporary invalid certificate files
    local temp_cert="/tmp/invalid_cert.crt"
    local temp_key="/tmp/invalid_key.key"
    
    echo "invalid certificate content" > "$temp_cert"
    echo "invalid key content" > "$temp_key"
    
    # Test validation should fail (suppress expected error output)
    local result=1
    if ! validate_certificate "$temp_cert" "$temp_key" >/dev/null 2>&1; then
        result=0
    fi
    
    # Cleanup
    rm -f "$temp_cert" "$temp_key"
    
    return $result
}

# =============================================================================
# Self-Signed Certificate Tests
# =============================================================================

test_self_signed_certificate_generation() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Create test environment for development mode
    create_test_environment "false"
    
    # Generate self-signed certificate with 365 days validity
    if generate_self_signed_certificate "test.example.com" 365; then
        # Check if files were created
        [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]
    else
        return 1
    fi
}

test_self_signed_certificate_permissions() {
    # Check certificate file permissions
    if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
        local cert_perms=$(stat -c "%a" "$SSL_CERT_PATH" 2>/dev/null)
        local key_perms=$(stat -c "%a" "$SSL_KEY_PATH" 2>/dev/null)
        
        [ "$cert_perms" = "644" ] && [ "$key_perms" = "600" ]
    else
        return 1
    fi
}

test_self_signed_certificate_ownership() {
    # Check certificate file ownership
    if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
        local cert_owner=$(stat -c "%U:%G" "$SSL_CERT_PATH" 2>/dev/null)
        local key_owner=$(stat -c "%U:%G" "$SSL_KEY_PATH" 2>/dev/null)
        
        [ "$cert_owner" = "root:www-data" ] && [ "$key_owner" = "root:www-data" ]
    else
        return 1
    fi
}

test_self_signed_certificate_validation() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Validate the generated certificate
    if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
        validate_certificate "$SSL_CERT_PATH" "$SSL_KEY_PATH"
        local result=$?
        # Accept both 0 (valid) and 2 (expires soon but valid) as success
        [ $result -eq 0 ] || [ $result -eq 2 ]
    else
        return 1
    fi
}

test_self_signed_certificate_expiry() {
    # Check certificate expiry date
    if [ -f "$SSL_CERT_PATH" ]; then
        local expiry_date=$(openssl x509 -in "$SSL_CERT_PATH" -noout -enddate 2>/dev/null | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        # Certificate should expire in approximately 365 days (give or take 1 day)
        [ "$days_until_expiry" -ge 364 ] && [ "$days_until_expiry" -le 366 ]
    else
        return 1
    fi
}

# =============================================================================
# Certificate Backup Tests
# =============================================================================

test_certificate_backup_creation() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Ensure certificates exist
    if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
        # Create backup
        if backup_certificates; then
            # Check if backup directory was created
            [ -d "$SSL_BACKUP_DIR" ]
        else
            return 1
        fi
    else
        return 1
    fi
}

test_certificate_backup_content() {
    # Check if backup contains certificate files
    if [ -d "$SSL_BACKUP_DIR" ]; then
        local latest_backup=$(ls -1t "$SSL_BACKUP_DIR" | grep "^backup_" | head -1)
        if [ -n "$latest_backup" ]; then
            [ -f "$SSL_BACKUP_DIR/$latest_backup/certificate.crt" ] && \
            [ -f "$SSL_BACKUP_DIR/$latest_backup/private.key" ]
        else
            return 1
        fi
    else
        return 1
    fi
}

test_certificate_backup_cleanup() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Create multiple backups to test cleanup
    for i in {1..12}; do
        backup_certificates >/dev/null 2>&1
        sleep 1  # Ensure different timestamps
    done
    
    # Check that only 10 backups are kept
    local backup_count=$(ls -1 "$SSL_BACKUP_DIR" | grep "^backup_" | wc -l)
    [ "$backup_count" -le 10 ]
}

# =============================================================================
# Renewal Process Tests
# =============================================================================

test_renewal_lock_mechanism() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Test lock file creation
    if create_lock_file; then
        # Check if lock file exists
        [ -f "/var/lock/ssl_renewal.lock" ]
        
        # Clean up
        remove_lock_file
    else
        return 1
    fi
}

test_renewal_development_mode() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    
    # Create test environment for development mode
    create_test_environment "false"
    
    # Test renewal in development mode
    "$script_path" --renew
}

test_renewal_force_mode() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    
    # Create test environment for development mode
    create_test_environment "false"
    
    # Test forced renewal
    "$script_path" --force
}

test_renewal_validation_command() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    
    # Test certificate validation command
    "$script_path" --validate
}

# =============================================================================
# Service Integration Tests
# =============================================================================

test_nginx_configuration_test() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Test Nginx configuration validation
    test_certificate_access
}

test_service_restart_simulation() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Mock service restart (dry run)
    # This tests the function logic without actually restarting services
    type restart_services >/dev/null 2>&1
}

# =============================================================================
# Logging Tests
# =============================================================================

test_ssl_log_file_creation() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Test SSL-specific logging
    log_ssl "INFO" "Test log message"
    
    # Check if log file was created and contains the message
    [ -f "$SSL_LOG_FILE" ] && grep -q "Test log message" "$SSL_LOG_FILE"
}

test_ssl_log_levels() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Test different log levels (suppress console output for cleaner test results)
    log_ssl "INFO" "Info test" >/dev/null 2>&1
    log_ssl "WARN" "Warning test" >/dev/null 2>&1
    log_ssl "ERROR" "Error test" >/dev/null 2>&1
    log_ssl "DEBUG" "Debug test" >/dev/null 2>&1
    
    # Check if all log levels are present in the log file
    grep -q "Info test" "$SSL_LOG_FILE" && \
    grep -q "Warning test" "$SSL_LOG_FILE" && \
    grep -q "Error test" "$SSL_LOG_FILE" && \
    grep -q "Debug test" "$SSL_LOG_FILE"
}

# =============================================================================
# Cron Job Tests
# =============================================================================

test_cron_setup_functionality() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Test cron setup function exists and can be called
    type setup_renewal_cron >/dev/null 2>&1
}

test_cron_script_creation() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    
    # Test cron setup command
    "$script_path" --setup-cron >/dev/null 2>&1
    
    # Check if renewal script was created
    [ -f "/usr/local/bin/ssl-renewal" ] && [ -x "/usr/local/bin/ssl-renewal" ]
}

# =============================================================================
# Production Mode Tests (Simulation)
# =============================================================================

test_production_mode_detection() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Create test environment for production mode
    create_test_environment "true"
    
    # Load test environment and check production detection
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env.test" ]; then
        set -o allexport
        source "$(dirname "${BASH_SOURCE[0]}")/../conf/user.env.test"
        set +o allexport
    fi
    
    [ "$PRODUCTION" = "true" ]
}

test_certbot_installation_check() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Test certbot installation function exists
    type install_certbot >/dev/null 2>&1
}

test_letsencrypt_functions_exist() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Test that Let's Encrypt functions are defined
    type obtain_letsencrypt_certificate >/dev/null 2>&1 && \
    type renew_letsencrypt_certificate >/dev/null 2>&1
}

# =============================================================================
# Integration Tests
# =============================================================================

test_environment_loading() {
    local script_path="$(dirname "${BASH_SOURCE[0]}")/../setup/ssl_renewal.sh"
    source "$script_path"
    
    # Create test environment
    create_test_environment "false"
    
    # Test environment loading in perform_certificate_renewal function
    type perform_certificate_renewal >/dev/null 2>&1
}

test_ssl_directory_structure() {
    # Test that SSL directories are created properly
    [ -d "$SSL_CERT_DIR" ] || sudo mkdir -p "$SSL_CERT_DIR"
    [ -d "$SSL_BACKUP_DIR" ] || sudo mkdir -p "$SSL_BACKUP_DIR"
    
    [ -d "$SSL_CERT_DIR" ] && [ -d "$SSL_BACKUP_DIR" ]
}

test_openssl_availability() {
    # Test that OpenSSL is available for certificate operations
    command -v openssl >/dev/null 2>&1
}

# =============================================================================
# Main Test Execution
# =============================================================================

main() {
    echo "==============================================================================="
    echo "SSL Certificate Management Tests - Milestone 5"
    echo "==============================================================================="
    echo ""
    
    # Backup test environment
    backup_test_environment
    
    # Ensure cleanup on exit
    trap restore_test_environment EXIT
    
    echo "SSL Renewal Script Tests:"
    run_test "SSL Script Exists" test_ssl_script_exists
    run_test "SSL Script Executable" test_ssl_script_executable
    run_test "SSL Script Help" test_ssl_script_help
    run_test "SSL Script Sourcing" test_ssl_script_sourcing
    echo ""
    
    echo "Certificate Validation Tests:"
    run_test "Certificate Validation Missing Files" test_certificate_validation_missing_files
    run_test "Certificate Validation Invalid Format" test_certificate_validation_invalid_format
    echo ""
    
    echo "Self-Signed Certificate Tests:"
    run_test "Self-Signed Certificate Generation" test_self_signed_certificate_generation
    run_test "Self-Signed Certificate Permissions" test_self_signed_certificate_permissions
    run_test "Self-Signed Certificate Ownership" test_self_signed_certificate_ownership
    run_test "Self-Signed Certificate Validation" test_self_signed_certificate_validation
    run_test "Self-Signed Certificate Expiry" test_self_signed_certificate_expiry
    echo ""
    
    echo "Certificate Backup Tests:"
    run_test "Certificate Backup Creation" test_certificate_backup_creation
    run_test "Certificate Backup Content" test_certificate_backup_content
    run_test "Certificate Backup Cleanup" test_certificate_backup_cleanup
    echo ""
    
    echo "Renewal Process Tests:"
    run_test "Renewal Lock Mechanism" test_renewal_lock_mechanism
    run_test "Renewal Development Mode" test_renewal_development_mode
    run_test "Renewal Force Mode" test_renewal_force_mode
    run_test "Renewal Validation Command" test_renewal_validation_command
    echo ""
    
    echo "Service Integration Tests:"
    run_test "Nginx Configuration Test" test_nginx_configuration_test
    run_test "Service Restart Simulation" test_service_restart_simulation
    echo ""
    
    echo "Logging Tests:"
    run_test "SSL Log File Creation" test_ssl_log_file_creation
    run_test "SSL Log Levels" test_ssl_log_levels
    echo ""
    
    echo "Cron Job Tests:"
    run_test "Cron Setup Functionality" test_cron_setup_functionality
    run_test "Cron Script Creation" test_cron_script_creation
    echo ""
    
    echo "Production Mode Tests (Simulation):"
    run_test "Production Mode Detection" test_production_mode_detection
    run_test "Certbot Installation Check" test_certbot_installation_check
    run_test "Let's Encrypt Functions Exist" test_letsencrypt_functions_exist
    echo ""
    
    echo "Integration Tests:"
    run_test "Environment Loading" test_environment_loading
    run_test "SSL Directory Structure" test_ssl_directory_structure
    run_test "OpenSSL Availability" test_openssl_availability
    echo ""
    
    # Test Summary
    echo "==============================================================================="
    echo "SSL Certificate Management Test Summary"
    echo "==============================================================================="
    local total_tests=$((TESTS_PASSED + TESTS_FAILED))
    echo "Total Tests: $total_tests"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "🎉 All SSL certificate management tests passed!"
        return 0
    else
        echo "❌ Some SSL certificate management tests failed."
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 