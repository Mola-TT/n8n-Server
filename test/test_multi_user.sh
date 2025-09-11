#!/bin/bash

# Test script for multi-user functionality
# Tests user isolation, provisioning, and management

source "$(dirname "$0")/../lib/logger.sh"
source "$(dirname "$0")/../lib/utilities.sh"

# Load environment variables
if [[ -f "$(dirname "$0")/../conf/user.env" ]]; then
    source "$(dirname "$0")/../conf/user.env"
fi
if [[ -f "$(dirname "$0")/../conf/default.env" ]]; then
    source "$(dirname "$0")/../conf/default.env"
fi

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test helper functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo "Running test: $test_name"
    
    if $test_function; then
        log_pass "✓ $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "✗ $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Test multi-user directory structure
test_multiuser_directories() {
    local required_dirs=(
        "/opt/n8n/users"
        "/opt/n8n/user-configs"
        "/opt/n8n/user-sessions"
        "/opt/n8n/user-logs"
        "/opt/n8n/monitoring/metrics"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "Missing directory: $dir"
            return 1
        fi
    done
    
    return 0
}

# Test directory permissions
test_directory_permissions() {
    local dirs=(
        "/opt/n8n/users"
        "/opt/n8n/user-configs"
        "/opt/n8n/user-sessions"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -w "$dir" ]]; then
            echo "Directory not writable: $dir"
            return 1
        fi
    done
    
    return 0
}

# Test user provisioning script exists
test_provisioning_script() {
    if [[ ! -f "/opt/n8n/scripts/provision-user.sh" ]]; then
        echo "User provisioning script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/provision-user.sh" ]]; then
        echo "User provisioning script not executable"
        return 1
    fi
    
    return 0
}

# Test user deprovisioning script exists
test_deprovisioning_script() {
    if [[ ! -f "/opt/n8n/scripts/deprovision-user.sh" ]]; then
        echo "User deprovisioning script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/deprovision-user.sh" ]]; then
        echo "User deprovisioning script not executable"
        return 1
    fi
    
    return 0
}

# Test user provisioning functionality
test_user_provisioning() {
    local test_user="test_user_$$"
    local user_dir="/opt/n8n/users/$test_user"
    
    # Clean up any existing test user
    if [[ -d "$user_dir" ]]; then
        rm -rf "$user_dir"
    fi
    
    # Provision test user
    if ! /opt/n8n/scripts/provision-user.sh "$test_user" "test@example.com" >/dev/null 2>&1; then
        echo "Failed to provision test user"
        return 1
    fi
    
    # Check if user directory was created
    if [[ ! -d "$user_dir" ]]; then
        echo "User directory not created"
        return 1
    fi
    
    # Check required subdirectories
    local required_subdirs=(
        "workflows"
        "credentials"
        "files"
        "logs"
        "temp"
        "backups"
    )
    
    for subdir in "${required_subdirs[@]}"; do
        if [[ ! -d "$user_dir/$subdir" ]]; then
            echo "Missing user subdirectory: $subdir"
            rm -rf "$user_dir"
            return 1
        fi
    done
    
    # Check user config file
    if [[ ! -f "$user_dir/user-config.json" ]]; then
        echo "User config file not created"
        rm -rf "$user_dir"
        return 1
    fi
    
    # Validate config file format
    if ! jq '.' "$user_dir/user-config.json" >/dev/null 2>&1; then
        echo "Invalid user config JSON"
        rm -rf "$user_dir"
        return 1
    fi
    
    # Check metrics file
    if [[ ! -f "/opt/n8n/monitoring/metrics/${test_user}.json" ]]; then
        echo "User metrics file not created"
        rm -rf "$user_dir"
        return 1
    fi
    
    # Clean up test user
    rm -rf "$user_dir"
    rm -f "/opt/n8n/monitoring/metrics/${test_user}.json"
    
    return 0
}

# Test user deprovisioning functionality
test_user_deprovisioning() {
    local test_user="test_deprovision_$$"
    local user_dir="/opt/n8n/users/$test_user"
    
    # Create test user first
    if ! /opt/n8n/scripts/provision-user.sh "$test_user" "test@example.com" >/dev/null 2>&1; then
        echo "Failed to create test user for deprovisioning test"
        return 1
    fi
    
    # Verify user exists
    if [[ ! -d "$user_dir" ]]; then
        echo "Test user not found for deprovisioning"
        return 1
    fi
    
    # Deprovision user
    if ! /opt/n8n/scripts/deprovision-user.sh "$test_user" >/dev/null 2>&1; then
        echo "Failed to deprovision test user"
        return 1
    fi
    
    # Verify user directory is removed
    if [[ -d "$user_dir" ]]; then
        echo "User directory not removed after deprovisioning"
        rm -rf "$user_dir"
        return 1
    fi
    
    # Verify metrics file is removed
    if [[ -f "/opt/n8n/monitoring/metrics/${test_user}.json" ]]; then
        echo "User metrics file not removed after deprovisioning"
        rm -f "/opt/n8n/monitoring/metrics/${test_user}.json"
        return 1
    fi
    
    return 0
}

# Test user isolation configuration
test_user_isolation_config() {
    if [[ ! -f "/opt/n8n/user-configs/isolation.json" ]]; then
        echo "User isolation config file not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/isolation.json" >/dev/null 2>&1; then
        echo "Invalid isolation config JSON"
        return 1
    fi
    
    # Check required configuration fields
    if ! jq -e '.userIsolation.enabled' "/opt/n8n/user-configs/isolation.json" >/dev/null 2>&1; then
        echo "Missing userIsolation.enabled in config"
        return 1
    fi
    
    return 0
}

# Test session management configuration
test_session_management() {
    if [[ ! -f "/opt/n8n/user-configs/session-config.json" ]]; then
        echo "Session management config not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/session-config.json" >/dev/null 2>&1; then
        echo "Invalid session config JSON"
        return 1
    fi
    
    # Test session cleanup script
    if [[ ! -f "/opt/n8n/scripts/cleanup-sessions.sh" ]]; then
        echo "Session cleanup script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/cleanup-sessions.sh" ]]; then
        echo "Session cleanup script not executable"
        return 1
    fi
    
    return 0
}

# Test user access control script
test_access_control() {
    if [[ ! -f "/opt/n8n/scripts/check-user-access.sh" ]]; then
        echo "User access control script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/check-user-access.sh" ]]; then
        echo "User access control script not executable"
        return 1
    fi
    
    return 0
}

# Test authentication configuration
test_authentication_config() {
    # Check if auth-config.json exists
    if [[ ! -f "/opt/n8n/user-configs/auth-config.json" ]]; then
        # In test environment, auth-config.json might not exist yet
        # Check if JWT_SECRET is configured in environment instead
        local project_root="$(cd "$(dirname "$0")/.." && pwd)"
        if [[ -f "$project_root/conf/user.env" ]]; then
            source "$project_root/conf/user.env"
            if [[ -n "$JWT_SECRET" ]] && [[ ${#JWT_SECRET} -ge 32 ]]; then
                return 0
            fi
        fi
        echo "Authentication config not found and JWT_SECRET not configured"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/auth-config.json" >/dev/null 2>&1; then
        echo "Invalid authentication config JSON"
        return 1
    fi
    
    # Check for JWT secret in config file
    local jwt_secret=$(jq -r '.authentication.jwtSecret' "/opt/n8n/user-configs/auth-config.json")
    if [[ "$jwt_secret" == "null" || -z "$jwt_secret" || "$jwt_secret" == "REPLACE_WITH_ACTUAL_JWT_SECRET" ]]; then
        # JWT secret not properly configured in file, check environment
        local project_root="$(cd "$(dirname "$0")/.." && pwd)"
        if [[ -f "$project_root/conf/user.env" ]]; then
            source "$project_root/conf/user.env"
            if [[ -n "$JWT_SECRET" ]] && [[ ${#JWT_SECRET} -ge 32 ]]; then
                return 0
            fi
        fi
        echo "JWT secret not properly configured in config file or environment"
        return 1
    fi
    
    # Validate JWT secret length
    if [[ ${#jwt_secret} -lt 32 ]]; then
        echo "JWT secret is too short (should be at least 32 characters)"
        return 1
    fi
    
    return 0
}

# Test cron job setup
test_cron_jobs() {
    # Check if session cleanup cron job exists
    if ! crontab -l 2>/dev/null | grep -q "cleanup-sessions.sh"; then
        echo "Session cleanup cron job not found"
        return 1
    fi
    
    return 0
}

# Test Docker volume mounts
test_docker_volumes() {
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        echo "Docker compose file not found"
        return 1
    fi
    
    # Check for multi-user volume mounts
    local required_volumes=(
        "/opt/n8n/users:/opt/n8n/users"
        "/opt/n8n/user-configs:/opt/n8n/user-configs"
        "/opt/n8n/user-sessions:/opt/n8n/user-sessions"
        "/opt/n8n/monitoring:/opt/n8n/monitoring"
    )
    
    for volume in "${required_volumes[@]}"; do
        if ! grep -q "$volume" "$compose_file"; then
            echo "Missing Docker volume mount: $volume"
            return 1
        fi
    done
    
    return 0
}

# Test environment variables
test_environment_variables() {
    local required_vars=(
        "MULTI_USER_ENABLED"
        "MAX_USERS"
        "USER_ISOLATION_ENABLED"
        "DEFAULT_USER_STORAGE_QUOTA"
        "USER_SESSION_TIMEOUT"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Missing environment variable: $var"
            return 1
        fi
    done
    
    return 0
}

# Main test execution
main() {
    echo "=============================================="
    echo "Multi-User n8n Configuration Tests"
    echo "=============================================="
    
    # Check if multi-user is enabled
    if [[ "${MULTI_USER_ENABLED,,}" != "true" ]]; then
        echo "Multi-user functionality is disabled, skipping tests"
        return 0
    fi
    
    run_test "Multi-user directories exist" test_multiuser_directories
    run_test "Directory permissions" test_directory_permissions
    run_test "User provisioning script" test_provisioning_script
    run_test "User deprovisioning script" test_deprovisioning_script
    run_test "User provisioning functionality" test_user_provisioning
    run_test "User deprovisioning functionality" test_user_deprovisioning
    run_test "User isolation configuration" test_user_isolation_config
    run_test "Session management configuration" test_session_management
    run_test "User access control" test_access_control
    run_test "Authentication configuration" test_authentication_config
    run_test "Cron job setup" test_cron_jobs
    run_test "Docker volume mounts" test_docker_volumes
    run_test "Environment variables" test_environment_variables
    
    echo "=============================================="
    echo "Multi-User Test Results:"
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "=============================================="
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_pass "All multi-user tests passed!"
        return 0
    else
        log_error "$FAILED_TESTS multi-user tests failed"
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
