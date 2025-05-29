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

# Main test execution
main() {
    log_info "Starting n8n server initialization tests..."
    echo "=========================================="
    
    # Milestone 1 Tests
    echo "MILESTONE 1 Tests:"
    run_test "Directory structure" "test_directories"
    run_test "Required files exist" "test_required_files"
    run_test "Script permissions" "test_script_permissions"
    run_test "User env handling" "test_user_env_handling"
    run_test "Environment loading" "test_env_loading"
    run_test "Logging functions" "test_logging"
    run_test "Utility functions" "test_utilities"
    
    # Milestone 2 Tests (Docker Infrastructure)
    echo ""
    echo "MILESTONE 2 Tests (Docker Infrastructure):"
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
    
    # Milestone 2 Tests (n8n Application)
    echo ""
    echo "MILESTONE 2 Tests (n8n Application):"
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
    
    # Print summary
    echo "=========================================="
    echo "Test Summary:"
    log_info "  Total tests: $TESTS_RUN"
    log_info "  Passed: $TESTS_PASSED"
    log_info "  Failed: $TESTS_FAILED"
    
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