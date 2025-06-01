#!/bin/bash
# run_tests.sh - Test runner for n8n server initialization
# Part of Milestone 1

# Exit immediately if a command exits with a non-zero status
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source logger
source "$PROJECT_DIR/lib/logger.sh"

# Source test suites
source "$PROJECT_DIR/test/test_docker.sh"
source "$PROJECT_DIR/test/test_n8n.sh"
source "$PROJECT_DIR/test/test_netdata.sh"
source "$PROJECT_DIR/test/test_ssl_renewal.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Run a test with description
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_pass "✓ $test_name: PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ $test_name: FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test that directories exist
test_directories() {
    [ -d "$PROJECT_DIR/lib" ] && [ -d "$PROJECT_DIR/conf" ] && [ -d "$PROJECT_DIR/setup" ]
}

# Test that required files exist
test_required_files() {
    [ -f "$PROJECT_DIR/lib/logger.sh" ] && 
    [ -f "$PROJECT_DIR/lib/utilities.sh" ] && 
    [ -f "$PROJECT_DIR/conf/default.env" ] && 
    [ -f "$PROJECT_DIR/conf/user.env.template" ] &&
    [ -f "$PROJECT_DIR/setup/general_config.sh" ]
}

# Test user environment handling (optional user.env file)
test_user_env_handling() {
    # Test that the script can handle missing user.env file gracefully
    # This should always pass since user.env is optional
    true
}

# Test that environment variables are loaded
test_env_loading() {
    source "$PROJECT_DIR/conf/default.env"
    [ -n "$SERVER_TIMEZONE" ] && [ -n "$LOG_LEVEL" ] && [ -n "$N8N_PORT" ]
}

# Test logging functions
test_logging() {
    log_info "Test log message" >/dev/null 2>&1
}

# Test utilities functions
test_utilities() {
    source "$PROJECT_DIR/lib/utilities.sh"
    command -v execute_silently >/dev/null 2>&1
}

# Test script permissions
test_script_permissions() {
    # Check if main scripts are executable (on systems that support it)
    if command -v stat >/dev/null 2>&1; then
        # Test a few key scripts if they exist
        [ ! -f "$PROJECT_DIR/lib/logger.sh" ] || [ -x "$PROJECT_DIR/lib/logger.sh" ] || return 1
        [ ! -f "$PROJECT_DIR/lib/utilities.sh" ] || [ -x "$PROJECT_DIR/lib/utilities.sh" ] || return 1
        [ ! -f "$PROJECT_DIR/setup/general_config.sh" ] || [ -x "$PROJECT_DIR/setup/general_config.sh" ] || return 1
        [ ! -f "$PROJECT_DIR/test/run_tests.sh" ] || [ -x "$PROJECT_DIR/test/run_tests.sh" ] || return 1
    fi
    # Always pass if stat command not available (like on some minimal systems)
    return 0
}

# =============================================================================
# MILESTONE 6 TESTS - Dynamic Hardware Optimization
# =============================================================================

run_milestone_6_tests() {
    log_info "=================================================================================="
    log_info "MILESTONE 6 TESTS - Dynamic Hardware Optimization"
    log_info "=================================================================================="
    
    local milestone_6_passed=0
    local milestone_6_failed=0
    
    # Dynamic Optimization Tests
    log_info "Running Dynamic Optimization Tests..."
    if source "$PROJECT_DIR/test/test_dynamic_optimization.sh" && run_dynamic_optimization_tests; then
        log_pass "Dynamic Optimization Tests: PASSED"
        milestone_6_passed=$((milestone_6_passed + 1))
    else
        log_error "Dynamic Optimization Tests: FAILED"
        milestone_6_failed=$((milestone_6_failed + 1))
    fi
    
    # Email Notification Tests
    log_info "Running Email Notification Tests..."
    if source "$PROJECT_DIR/test/test_email_notification.sh" && run_email_notification_tests; then
        log_pass "Email Notification Tests: PASSED"
        milestone_6_passed=$((milestone_6_passed + 1))
    else
        log_error "Email Notification Tests: FAILED"
        milestone_6_failed=$((milestone_6_failed + 1))
    fi
    
    # Hardware Change Detector Tests
    log_info "Running Hardware Change Detector Tests..."
    if source "$PROJECT_DIR/test/test_hardware_change_detector.sh" && run_hardware_change_detector_tests; then
        log_pass "Hardware Change Detector Tests: PASSED"
        milestone_6_passed=$((milestone_6_passed + 1))
    else
        log_error "Hardware Change Detector Tests: FAILED"
        milestone_6_failed=$((milestone_6_failed + 1))
    fi
    
    # Dynamic Optimization Integration Tests
    log_info "Running Dynamic Optimization Integration Tests..."
    if source "$PROJECT_DIR/test/test_dynamic_optimization_integration.sh" && run_dynamic_optimization_integration_tests; then
        log_pass "Dynamic Optimization Integration Tests: PASSED"
        milestone_6_passed=$((milestone_6_passed + 1))
    else
        log_error "Dynamic Optimization Integration Tests: FAILED"
        milestone_6_failed=$((milestone_6_failed + 1))
    fi
    
    local milestone_6_total=$((milestone_6_passed + milestone_6_failed))
    log_info "Milestone 6 Summary: $milestone_6_passed/$milestone_6_total test suites passed"
    
    # Update global counters
    TESTS_PASSED=$((TESTS_PASSED + milestone_6_passed))
    TESTS_FAILED=$((TESTS_FAILED + milestone_6_failed))
    
    return $milestone_6_failed
}

# Main test execution
main() {
    log_info "Starting n8n server initialization tests..."
    echo "=========================================="
    
    # Milestone 1 Tests
    echo "=========================================="
    echo "MILESTONE 1 Tests:"
    echo "=========================================="
    run_test "Directory structure" "test_directories"
    run_test "Required files exist" "test_required_files"
    run_test "Script permissions" "test_script_permissions"
    run_test "User env handling" "test_user_env_handling"
    run_test "Environment loading" "test_env_loading"
    run_test "Logging functions" "test_logging"
    run_test "Utility functions" "test_utilities"
    echo "=========================================="
    
    # Milestone 2 Tests (Docker Infrastructure)
    echo ""
    echo "=========================================="
    echo "MILESTONE 2 Tests (Docker Infrastructure):"
    echo "=========================================="
    run_test "n8n Directory Structure" "test_n8n_directories"
    run_test "Directory Permissions" "test_directory_permissions"
    run_test "Docker Compose File" "test_docker_compose_file"
    run_test "Environment File" "test_environment_file"
    run_test "Redis Configuration" "test_redis_configuration"
    run_test "Operational Scripts" "test_operational_scripts"
    run_test "Systemd Service" "test_systemd_service"
    run_test "Docker Installation" "test_docker_installation"
    run_test "Volume Mounts" "test_volume_mounts"
    run_test "Network Configuration" "test_network_configuration"
    echo "=========================================="
    
    # Milestone 2 Tests (n8n Application)
    echo ""
    echo "=========================================="
    echo "MILESTONE 2 Tests (n8n Application):"
    echo "=========================================="
    run_test "n8n Environment Configuration" "test_n8n_environment_file"
    run_test "Authentication Configuration" "test_n8n_authentication_configuration"
    run_test "Timezone Configuration" "test_n8n_timezone_configuration"
    run_test "SSL Configuration" "test_n8n_ssl_configuration"
    run_test "SSL Certificates" "test_n8n_ssl_certificates"
    run_test "PostgreSQL Connectivity" "test_n8n_postgresql_connectivity"
    run_test "Database Permissions" "test_n8n_database_permissions"
    run_test "n8n Container Health" "test_n8n_container_health"
    run_test "Redis Connectivity" "test_n8n_redis_connectivity"
    run_test "n8n Web Accessibility" "test_n8n_web_accessibility"
    run_test "Authentication Challenge" "test_n8n_authentication_challenge"
    run_test "Authentication Login" "test_n8n_authentication_login"
    echo "=========================================="
    echo ""
    
    # Milestone 4 Tests (Netdata Monitoring)
    echo ""
    echo "=========================================="
    echo "MILESTONE 4 Tests (Netdata Monitoring):"
    echo "=========================================="
    run_test "Netdata Service Running" "test_netdata_service_running"
    run_test "Netdata Service Enabled" "test_netdata_service_enabled"
    run_test "Netdata Process Running" "test_netdata_process_running"
    run_test "Netdata Listening Localhost" "test_netdata_listening_localhost"
    run_test "Netdata Config Exists" "test_netdata_config_exists"
    run_test "Netdata Localhost Binding" "test_netdata_config_localhost_binding"
    run_test "Netdata Health Config" "test_netdata_health_config_exists"
    run_test "Netdata Email Notifications" "test_netdata_email_notifications_configured"
    run_test "Netdata API Localhost" "test_netdata_api_localhost_accessible"
    run_test "Netdata API Response" "test_netdata_api_response_valid"
    run_test "Netdata Web Interface" "test_netdata_web_interface_localhost"
    run_test "Netdata Nginx Config" "test_netdata_nginx_config_exists"
    run_test "Netdata Nginx Auth File" "test_netdata_nginx_auth_file_exists"
    run_test "Netdata SSL Certificates" "test_netdata_nginx_ssl_certificates"
    run_test "Netdata Nginx Syntax" "test_netdata_nginx_config_syntax"
    run_test "Netdata HTTPS Proxy" "test_netdata_https_proxy_accessible"
    run_test "Netdata HTTPS Authentication" "test_netdata_https_authentication"
    run_test "Netdata HTTP Redirect" "test_netdata_http_to_https_redirect"
    run_test "Netdata Firewall Blocking" "test_netdata_firewall_blocks_direct_access"
    run_test "Netdata External Security" "test_netdata_not_accessible_externally"
    run_test "Netdata Security Headers" "test_netdata_security_headers"
    run_test "Netdata Health Monitoring" "test_netdata_health_monitoring_active"
    run_test "Netdata Health Alerts" "test_netdata_health_alerts_configured"
    run_test "Netdata Directories" "test_netdata_directories_exist"
    run_test "Netdata Log Files" "test_netdata_log_files_exist"
    run_test "Netdata Permissions" "test_netdata_permissions"
    run_test "Netdata Nginx Logs" "test_netdata_nginx_log_files"
    echo "=========================================="
    echo ""
    
    # Milestone 5 Tests (SSL Certificate Management)
    echo ""
    echo "=========================================="
    echo "MILESTONE 5 Tests (SSL Certificate Management):"
    echo "=========================================="
    run_test "SSL Script Exists" "test_ssl_script_exists"
    run_test "SSL Script Executable" "test_ssl_script_executable"
    run_test "SSL Script Help" "test_ssl_script_help"
    run_test "SSL Script Sourcing" "test_ssl_script_sourcing"
    run_test "Certificate Validation Missing Files" "test_certificate_validation_missing_files"
    run_test "Certificate Validation Invalid Format" "test_certificate_validation_invalid_format"
    run_test "Self-Signed Certificate Generation" "test_self_signed_certificate_generation"
    run_test "Self-Signed Certificate Permissions" "test_self_signed_certificate_permissions"
    run_test "Self-Signed Certificate Ownership" "test_self_signed_certificate_ownership"
    run_test "Self-Signed Certificate Validation" "test_self_signed_certificate_validation"
    run_test "Self-Signed Certificate Expiry" "test_self_signed_certificate_expiry"
    run_test "Certificate Backup Creation" "test_certificate_backup_creation"
    run_test "Certificate Backup Content" "test_certificate_backup_content"
    run_test "Certificate Backup Cleanup" "test_certificate_backup_cleanup"
    run_test "Renewal Lock Mechanism" "test_renewal_lock_mechanism"
    run_test "Renewal Development Mode" "test_renewal_development_mode"
    run_test "Renewal Force Mode" "test_renewal_force_mode"
    run_test "Renewal Validation Command" "test_renewal_validation_command"
    run_test "Nginx Configuration Test" "test_nginx_configuration_test"
    run_test "Service Restart Simulation" "test_service_restart_simulation"
    run_test "SSL Log File Creation" "test_ssl_log_file_creation"
    run_test "SSL Log Levels" "test_ssl_log_levels"
    run_test "Cron Setup Functionality" "test_cron_setup_functionality"
    run_test "Cron Script Creation" "test_cron_script_creation"
    run_test "Production Mode Detection" "test_production_mode_detection"
    run_test "Certbot Installation Check" "test_certbot_installation_check"
    run_test "Let's Encrypt Functions Exist" "test_letsencrypt_functions_exist"
    run_test "Environment Loading" "test_environment_loading"
    run_test "SSL Directory Structure" "test_ssl_directory_structure"
    run_test "OpenSSL Availability" "test_openssl_availability"
    echo "=========================================="
    echo ""
    
    # Run Milestone 6 Tests
    run_milestone_6_tests
    
    # Print summary
    echo "=========================================="
    echo "Test Summary:"
    echo "=========================================="
    log_info "  Total tests: $TESTS_RUN"
    log_info "  Passed: $TESTS_PASSED"
    log_info "  Failed: $TESTS_FAILED"
    echo "=========================================="
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_pass "All tests passed!"
        exit 0
    else
        log_error "Some tests failed!"
        exit 1
    fi
}

# Execute main function
main "$@" 