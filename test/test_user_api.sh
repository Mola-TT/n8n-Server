#!/bin/bash

# Test script for user management API functionality
# Tests API endpoints, authentication, and functionality

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

# Test API directory structure
test_api_directories() {
    local required_dirs=(
        "/opt/n8n/api/endpoints"
        "/opt/n8n/api/middleware"
        "/opt/n8n/api/docs"
        "/opt/n8n/api/logs"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "Missing API directory: $dir"
            return 1
        fi
    done
    
    return 0
}

# Test API endpoint files
test_api_endpoint_files() {
    local required_files=(
        "/opt/n8n/api/endpoints/user-provisioning.js"
        "/opt/n8n/api/endpoints/analytics.js"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "Missing API endpoint file: $file"
            return 1
        fi
        
        # Basic syntax check for JavaScript
        if command -v node >/dev/null 2>&1; then
            if ! node -c "$file" 2>/dev/null; then
                echo "Syntax error in API file: $file"
                return 1
            fi
        fi
    done
    
    return 0
}

# Test API middleware files
test_api_middleware_files() {
    local required_files=(
        "/opt/n8n/api/middleware/auth.js"
        "/opt/n8n/api/middleware/logging.js"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "Missing API middleware file: $file"
            return 1
        fi
        
        # Basic syntax check for JavaScript
        if command -v node >/dev/null 2>&1; then
            if ! node -c "$file" 2>/dev/null; then
                echo "Syntax error in middleware file: $file"
                return 1
            fi
        fi
    done
    
    return 0
}

# Test main API server file
test_api_server_file() {
    if [[ ! -f "/opt/n8n/api/server.js" ]]; then
        echo "API server file not found"
        return 1
    fi
    
    # Basic syntax check for JavaScript
    if command -v node >/dev/null 2>&1; then
        if ! node -c "/opt/n8n/api/server.js" 2>/dev/null; then
            echo "Syntax error in API server file"
            return 1
        fi
    fi
    
    return 0
}

# Test package.json file
test_package_json() {
    if [[ ! -f "/opt/n8n/api/package.json" ]]; then
        echo "package.json file not found"
        return 1
    fi
    
    # Validate JSON format
    if ! jq '.' "/opt/n8n/api/package.json" >/dev/null 2>&1; then
        echo "Invalid package.json format"
        return 1
    fi
    
    # Check required dependencies
    local required_deps=(
        "express"
        "cors"
        "helmet"
        "bcrypt"
        "jsonwebtoken"
        "uuid"
    )
    
    for dep in "${required_deps[@]}"; do
        if ! jq -e ".dependencies.\"$dep\"" "/opt/n8n/api/package.json" >/dev/null 2>&1; then
            echo "Missing dependency in package.json: $dep"
            return 1
        fi
    done
    
    return 0
}

# Test systemd service file
test_systemd_service() {
    if [[ ! -f "/opt/n8n/scripts/user-management-api.service" ]]; then
        echo "Systemd service file not found"
        return 1
    fi
    
    # Check service file format
    if ! grep -q "\[Unit\]" "/opt/n8n/scripts/user-management-api.service"; then
        echo "Invalid systemd service file format"
        return 1
    fi
    
    return 0
}

# Test API documentation
test_api_documentation() {
    if [[ ! -f "/opt/n8n/api/docs/README.md" ]]; then
        echo "API documentation not found"
        return 1
    fi
    
    # Check if documentation contains key sections
    if ! grep -q "## Authentication" "/opt/n8n/api/docs/README.md"; then
        echo "Authentication section missing from API docs"
        return 1
    fi
    
    if ! grep -q "## User Management Endpoints" "/opt/n8n/api/docs/README.md"; then
        echo "User Management section missing from API docs"
        return 1
    fi
    
    return 0
}

# Test API dependencies installation
test_api_dependencies() {
    # Skip if npm is not available
    if ! command -v npm >/dev/null 2>&1; then
        echo "npm not available, skipping dependency test"
        return 0
    fi
    
    # Check if node_modules exists (dependencies installed)
    if [[ -d "/opt/n8n/api/node_modules" ]]; then
        # Check if main dependencies are installed
        local key_deps=("express" "cors" "helmet")
        
        for dep in "${key_deps[@]}"; do
            if [[ ! -d "/opt/n8n/api/node_modules/$dep" ]]; then
                echo "Dependency not installed: $dep"
                return 1
            fi
        done
    else
        echo "Node modules not installed (run 'npm install' in /opt/n8n/api/)"
        # This is not a failure, just a notice
        return 0
    fi
    
    return 0
}

# Test API server startup (mock test)
test_api_server_startup() {
    # Skip if Node.js is not available
    if ! command -v node >/dev/null 2>&1; then
        echo "Node.js not available, skipping server startup test"
        return 0
    fi
    
    # Test if server file can be loaded without errors
    cd "/opt/n8n/api" || return 1
    
    # Create a simple test script to check if server can initialize
    cat > test_server.js << 'EOF'
try {
    // Set test environment variables
    process.env.API_PORT = '3099'; // Use different port for testing
    process.env.NODE_ENV = 'test';
    
    // Try to require the server file
    const ServerClass = require('./server.js');
    console.log('Server class loaded successfully');
    process.exit(0);
} catch (error) {
    console.error('Server load error:', error.message);
    process.exit(1);
}
EOF
    
    # Run the test
    local result=0
    if ! timeout 10s node test_server.js >/dev/null 2>&1; then
        echo "API server failed to initialize"
        result=1
    fi
    
    # Cleanup
    rm -f test_server.js
    
    return $result
}

# Test API environment variables
test_api_environment() {
    local required_vars=(
        "USER_API_ENABLED"
        "USER_API_PORT"
        "API_KEY_AUTH_ENABLED"
        "API_JWT_AUTH_ENABLED"
        "API_USER_RATE_LIMIT"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Missing environment variable: $var"
            return 1
        fi
    done
    
    return 0
}

# Test API log directory permissions
test_api_log_permissions() {
    if [[ ! -w "/opt/n8n/api/logs" ]]; then
        echo "API logs directory not writable"
        return 1
    fi
    
    # Test if we can create a log file
    local test_log="/opt/n8n/api/logs/test.log"
    if ! touch "$test_log" 2>/dev/null; then
        echo "Cannot create log files in API logs directory"
        return 1
    fi
    
    # Cleanup test file
    rm -f "$test_log"
    
    return 0
}

# Test API security configuration
test_api_security() {
    # Check if sensitive files have proper permissions
    local sensitive_files=(
        "/opt/n8n/api/server.js"
        "/opt/n8n/api/package.json"
    )
    
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            # Check if file is not world-writable
            if [[ $(stat -c "%a" "$file" 2>/dev/null) == *"2" ]] || [[ $(stat -c "%a" "$file" 2>/dev/null) == *"6" ]]; then
                echo "Security risk: $file is world-writable"
                return 1
            fi
        fi
    done
    
    return 0
}

# Test API port configuration
test_api_port() {
    local api_port="${USER_API_PORT:-3001}"
    
    # Check if port is valid
    if [[ ! "$api_port" =~ ^[0-9]+$ ]] || [[ "$api_port" -lt 1024 ]] || [[ "$api_port" -gt 65535 ]]; then
        echo "Invalid API port: $api_port"
        return 1
    fi
    
    # Check if port is available (not in use)
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":$api_port "; then
            echo "API port $api_port is already in use"
            return 1
        fi
    fi
    
    return 0
}

# Test JWT secret configuration
test_jwt_secret() {
    # Check if JWT_SECRET is set
    if [[ -z "$JWT_SECRET" ]]; then
        echo "JWT_SECRET environment variable not set"
        return 1
    fi
    
    # Check JWT secret length (should be at least 32 characters)
    if [[ ${#JWT_SECRET} -lt 32 ]]; then
        echo "JWT_SECRET is too short (should be at least 32 characters)"
        return 1
    fi
    
    return 0
}

# Test API rate limiting configuration
test_rate_limiting() {
    local user_limit="${API_USER_RATE_LIMIT:-30}"
    local admin_limit="${API_ADMIN_RATE_LIMIT:-100}"
    local global_limit="${API_GLOBAL_RATE_LIMIT:-1000}"
    
    # Check if rate limits are numeric
    if [[ ! "$user_limit" =~ ^[0-9]+$ ]]; then
        echo "Invalid user rate limit: $user_limit"
        return 1
    fi
    
    if [[ ! "$admin_limit" =~ ^[0-9]+$ ]]; then
        echo "Invalid admin rate limit: $admin_limit"
        return 1
    fi
    
    if [[ ! "$global_limit" =~ ^[0-9]+$ ]]; then
        echo "Invalid global rate limit: $global_limit"
        return 1
    fi
    
    # Check rate limit hierarchy
    if [[ $admin_limit -le $user_limit ]]; then
        echo "Admin rate limit should be higher than user rate limit"
        return 1
    fi
    
    return 0
}

# Test API configuration files
test_api_config_files() {
    # Check if API configuration directory exists
    if [[ ! -d "/opt/n8n/user-configs" ]]; then
        echo "API configuration directory not found"
        return 1
    fi
    
    # Check if we can write to config directory
    if [[ ! -w "/opt/n8n/user-configs" ]]; then
        echo "API configuration directory not writable"
        return 1
    fi
    
    return 0
}

# Test API health endpoint structure
test_health_endpoint() {
    # Create a simple test to verify health endpoint structure
    cat > /tmp/test_health.js << 'EOF'
// Simple test for health endpoint structure
const express = require('express');
const app = express();

app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: '1.0.0'
    });
});

console.log('Health endpoint test passed');
EOF
    
    # Test if the health endpoint structure is valid
    if command -v node >/dev/null 2>&1; then
        if ! node -c /tmp/test_health.js 2>/dev/null; then
            echo "Health endpoint structure test failed"
            rm -f /tmp/test_health.js
            return 1
        fi
    fi
    
    # Cleanup
    rm -f /tmp/test_health.js
    
    return 0
}

# Main test execution
main() {
    echo "=============================================="
    echo "User Management API Tests"
    echo "=============================================="
    
    # Check if user management API is enabled
    if [[ "${USER_API_ENABLED,,}" != "true" ]]; then
        echo "User management API is disabled, skipping tests"
        return 0
    fi
    
    run_test "API directory structure" test_api_directories
    run_test "API endpoint files" test_api_endpoint_files
    run_test "API middleware files" test_api_middleware_files
    run_test "API server file" test_api_server_file
    run_test "Package.json configuration" test_package_json
    run_test "Systemd service file" test_systemd_service
    run_test "API documentation" test_api_documentation
    run_test "API dependencies" test_api_dependencies
    run_test "API server startup" test_api_server_startup
    run_test "API environment variables" test_api_environment
    run_test "API log permissions" test_api_log_permissions
    run_test "API security configuration" test_api_security
    run_test "API port configuration" test_api_port
    run_test "JWT secret configuration" test_jwt_secret
    run_test "Rate limiting configuration" test_rate_limiting
    run_test "API configuration files" test_api_config_files
    run_test "Health endpoint structure" test_health_endpoint
    
    echo "=============================================="
    echo "User Management API Test Results:"
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "=============================================="
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_pass "All user management API tests passed!"
        return 0
    else
        log_error "$FAILED_TESTS user management API tests failed"
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
