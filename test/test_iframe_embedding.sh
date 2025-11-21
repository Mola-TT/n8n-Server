#!/bin/bash

# Test script for iframe embedding functionality
# Tests CORS, CSP, authentication, and communication features

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
    
    log_info "Running test: $test_name"
    
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

# Test CORS configuration
test_cors_configuration() {
    if [[ ! -f "/opt/n8n/user-configs/cors-config.json" ]]; then
        echo "CORS configuration file not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/cors-config.json" >/dev/null 2>&1; then
        echo "Invalid CORS config JSON"
        return 1
    fi
    
    # Check required CORS settings
    if ! jq -e '.cors.enabled' "/opt/n8n/user-configs/cors-config.json" >/dev/null 2>&1; then
        echo "CORS not enabled in config"
        return 1
    fi
    
    if ! jq -e '.cors.allowedOrigins' "/opt/n8n/user-configs/cors-config.json" >/dev/null 2>&1; then
        echo "CORS allowed origins not configured"
        return 1
    fi
    
    return 0
}

# Test CSP configuration
test_csp_configuration() {
    if [[ ! -f "/opt/n8n/user-configs/csp-config.json" ]]; then
        echo "CSP configuration file not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/csp-config.json" >/dev/null 2>&1; then
        echo "Invalid CSP config JSON"
        return 1
    fi
    
    # Check for frame-ancestors directive
    if ! jq -e '.contentSecurityPolicy.directives."frame-ancestors"' "/opt/n8n/user-configs/csp-config.json" >/dev/null 2>&1; then
        echo "CSP frame-ancestors directive not configured"
        return 1
    fi
    
    return 0
}

# Test frame options configuration
test_frame_options() {
    if [[ ! -f "/opt/n8n/user-configs/frame-options.json" ]]; then
        echo "Frame options configuration file not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/frame-options.json" >/dev/null 2>&1; then
        echo "Invalid frame options config JSON"
        return 1
    fi
    
    # Check allowed domains
    if ! jq -e '.frameOptions.allowedDomains' "/opt/n8n/user-configs/frame-options.json" >/dev/null 2>&1; then
        echo "Frame options allowed domains not configured"
        return 1
    fi
    
    return 0
}

# Test token passing configuration
test_token_passing() {
    if [[ ! -f "/opt/n8n/user-configs/token-config.json" ]]; then
        echo "Token passing configuration file not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/token-config.json" >/dev/null 2>&1; then
        echo "Invalid token config JSON"
        return 1
    fi
    
    # Check token passing methods
    if ! jq -e '.tokenPassing.methods.header.enabled' "/opt/n8n/user-configs/token-config.json" >/dev/null 2>&1; then
        echo "Header token passing not configured"
        return 1
    fi
    
    if ! jq -e '.tokenPassing.methods.postMessage.enabled' "/opt/n8n/user-configs/token-config.json" >/dev/null 2>&1; then
        echo "PostMessage token passing not configured"
        return 1
    fi
    
    return 0
}

# Test session synchronization configuration
test_session_sync() {
    if [[ ! -f "/opt/n8n/user-configs/session-sync.json" ]]; then
        echo "Session sync configuration file not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/session-sync.json" >/dev/null 2>&1; then
        echo "Invalid session sync config JSON"
        return 1
    fi
    
    # Check session sync script
    if [[ ! -f "/opt/n8n/scripts/session-sync.js" ]]; then
        echo "Session sync script not found"
        return 1
    fi
    
    return 0
}

# Test user routing configuration
test_user_routing() {
    if [[ ! -f "/opt/n8n/user-configs/routing-config.json" ]]; then
        echo "User routing configuration file not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/routing-config.json" >/dev/null 2>&1; then
        echo "Invalid routing config JSON"
        return 1
    fi
    
    # Check user path pattern
    local user_path=$(jq -r '.routing.userPath' "/opt/n8n/user-configs/routing-config.json")
    if [[ "$user_path" != "/user/{userId}" ]]; then
        echo "Incorrect user path pattern: $user_path"
        return 1
    fi
    
    return 0
}

# Test postMessage API script
test_postmessage_api() {
    if [[ ! -f "/opt/n8n/scripts/postmessage-api.js" ]]; then
        echo "PostMessage API script not found"
        return 1
    fi
    
    # Basic syntax check for JavaScript
    if command -v node >/dev/null 2>&1; then
        if ! node -c "/opt/n8n/scripts/postmessage-api.js" 2>/dev/null; then
            echo "PostMessage API script has syntax errors"
            return 1
        fi
    fi
    
    return 0
}

# Test security middleware
test_security_middleware() {
    if [[ ! -f "/opt/n8n/scripts/iframe-security.js" ]]; then
        echo "Security middleware script not found"
        return 1
    fi
    
    # Basic syntax check for JavaScript
    if command -v node >/dev/null 2>&1; then
        if ! node -c "/opt/n8n/scripts/iframe-security.js" 2>/dev/null; then
            echo "Security middleware script has syntax errors"
            return 1
        fi
    fi
    
    return 0
}

# Test Nginx iframe configuration
test_nginx_iframe_config() {
    local nginx_config="/etc/nginx/sites-available/n8n"
    
    if [[ ! -f "$nginx_config" ]]; then
        echo "Nginx configuration file not found"
        return 1
    fi
    
    # Check for iframe-related headers
    if ! grep -q "X-Frame-Options" "$nginx_config"; then
        echo "X-Frame-Options header not found in Nginx config"
        return 1
    fi
    
    # Check for CSP headers
    if ! grep -q "Content-Security-Policy" "$nginx_config"; then
        echo "Content-Security-Policy header not found in Nginx config"
        return 1
    fi
    
    # Check for frame-ancestors in CSP
    if ! grep -q "frame-ancestors" "$nginx_config"; then
        echo "frame-ancestors directive not found in Nginx CSP"
        return 1
    fi
    
    return 0
}

# Test user-specific routing in Nginx
test_nginx_user_routing() {
    local nginx_config="/etc/nginx/sites-available/n8n"
    
    if [[ ! -f "$nginx_config" ]]; then
        echo "Nginx configuration file not found"
        return 1
    fi
    
    # Check for user-specific location block
    if ! grep -q "location ~ .*user/.*" "$nginx_config"; then
        echo "User-specific routing not found in Nginx config"
        return 1
    fi
    
    # Check for user ID header
    if ! grep -q "X-User-ID" "$nginx_config"; then
        echo "X-User-ID header not found in Nginx config"
        return 1
    fi
    
    return 0
}

# Test CORS headers in Nginx
test_nginx_cors() {
    local nginx_config="/etc/nginx/sites-available/n8n"
    
    if [[ ! -f "$nginx_config" ]]; then
        echo "Nginx configuration file not found"
        return 1
    fi
    
    # Check if WEBAPP_DOMAIN values are referenced (strip any Windows CR)
    local cors_primary=$(printf "%s" "${WEBAPP_DOMAIN:-}" | tr -d '\r')
    local cors_secondary=$(printf "%s" "${WEBAPP_DOMAIN_ALT:-}" | tr -d '\r')

    if [[ -n "$cors_primary" ]]; then
        if ! grep -Fq "$cors_primary" "$nginx_config"; then
            echo "WEBAPP_DOMAIN not found in Nginx config"
            return 1
        fi
    fi

    if [[ -n "$cors_secondary" ]]; then
        if ! grep -Fq "$cors_secondary" "$nginx_config"; then
            echo "WEBAPP_DOMAIN_ALT not found in Nginx config"
            return 1
        fi
    fi
    
    return 0
}

# Test iframe embedding environment variables
test_iframe_environment() {
    local required_vars=(
        "IFRAME_EMBEDDING_ENABLED"
        "WEBAPP_DOMAIN"
        "CORS_ENABLED"
        "CSP_ENABLED"
        "POSTMESSAGE_API_ENABLED"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Missing environment variable: $var"
            return 1
        fi
    done
    
    return 0
}

# Test HTTP response headers (requires running server)
test_http_headers() {
    # Skip if server is not running
    if ! curl -s -I "http://localhost:${NGINX_HTTP_PORT:-80}" >/dev/null 2>&1; then
        log_info "Server not accessible, skipping HTTP header tests"
        return 0
    fi
    
    # Test HTTP to HTTPS redirect
    local response=$(curl -s -I "http://localhost:${NGINX_HTTP_PORT:-80}" 2>/dev/null | head -n 1)
    if [[ "$response" != *"301"* && "$response" != *"302"* ]]; then
        echo "HTTP to HTTPS redirect not working"
        return 1
    fi
    
    return 0
}

# Test HTTPS headers (requires running server)
test_https_headers() {
    # Skip if HTTPS server is not accessible
    if ! curl -s -k -I "https://localhost:${NGINX_HTTPS_PORT:-443}" >/dev/null 2>&1; then
        log_info "HTTPS server not accessible, skipping HTTPS header tests"
        return 0
    fi
    
    # Test X-Frame-Options header
    local frame_header=$(curl -s -k -I "https://localhost:${NGINX_HTTPS_PORT:-443}" 2>/dev/null | grep -i "x-frame-options")
    if [[ -z "$frame_header" ]]; then
        echo "X-Frame-Options header not present"
        return 1
    fi
    
    # Test CSP header
    local csp_header=$(curl -s -k -I "https://localhost:${NGINX_HTTPS_PORT:-443}" 2>/dev/null | grep -i "content-security-policy")
    if [[ -z "$csp_header" ]]; then
        echo "Content-Security-Policy header not present"
        return 1
    fi
    
    return 0
}

# Test JavaScript configuration files
test_javascript_configs() {
    local js_files=(
        "/opt/n8n/scripts/session-sync.js"
        "/opt/n8n/scripts/postmessage-api.js"
        "/opt/n8n/scripts/iframe-security.js"
    )
    
    for js_file in "${js_files[@]}"; do
        if [[ ! -f "$js_file" ]]; then
            echo "JavaScript file not found: $js_file"
            return 1
        fi
        
        # Check if variables are replaced (no template variables left)
        if grep -q '\${WEBAPP_DOMAIN}' "$js_file"; then
            echo "Template variables not replaced in: $js_file"
            return 1
        fi
    done
    
    return 0
}

# Main test execution
main() {
    log_section "Iframe Embedding Configuration Tests"
    
    # Check if iframe embedding is enabled
    if [[ "${IFRAME_EMBEDDING_ENABLED,,}" != "true" ]]; then
        log_info "Iframe embedding is disabled, skipping tests"
        return 0
    fi
    
    run_test "CORS configuration" test_cors_configuration
    run_test "CSP configuration" test_csp_configuration
    run_test "Frame options configuration" test_frame_options
    run_test "Token passing configuration" test_token_passing
    run_test "Session synchronization" test_session_sync
    run_test "User routing configuration" test_user_routing
    run_test "PostMessage API script" test_postmessage_api
    run_test "Security middleware" test_security_middleware
    run_test "Nginx iframe configuration" test_nginx_iframe_config
    run_test "Nginx user routing" test_nginx_user_routing
    run_test "Nginx CORS configuration" test_nginx_cors
    run_test "Environment variables" test_iframe_environment
    run_test "JavaScript configurations" test_javascript_configs
    run_test "HTTP headers" test_http_headers
    run_test "HTTPS headers" test_https_headers
    
    log_subsection "Iframe Embedding Test Results:"
    log_info "Total tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_pass "All iframe embedding tests passed!"
        return 0
    else
        log_error "$FAILED_TESTS iframe embedding tests failed"
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
