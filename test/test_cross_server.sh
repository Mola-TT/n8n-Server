#!/bin/bash

# Test script for cross-server communication functionality
# Tests API authentication, webhook forwarding, and network security

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

# Test API authentication configuration
test_api_authentication() {
    if [[ ! -f "/opt/n8n/user-configs/api-auth.json" ]]; then
        echo "API authentication config not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/api-auth.json" >/dev/null 2>&1; then
        echo "Invalid API auth config JSON"
        return 1
    fi
    
    # Check JWT configuration
    if ! jq -e '.apiAuthentication.methods.jwt.enabled' "/opt/n8n/user-configs/api-auth.json" >/dev/null 2>&1; then
        echo "JWT authentication not enabled"
        return 1
    fi
    
    # Check API key configuration
    if ! jq -e '.apiAuthentication.methods.apiKey.enabled' "/opt/n8n/user-configs/api-auth.json" >/dev/null 2>&1; then
        echo "API key authentication not enabled"
        return 1
    fi
    
    # Check for JWT secret
    local jwt_secret=$(jq -r '.apiAuthentication.methods.jwt.secret' "/opt/n8n/user-configs/api-auth.json")
    if [[ "$jwt_secret" == "null" || -z "$jwt_secret" ]]; then
        echo "JWT secret not configured"
        return 1
    fi
    
    return 0
}

# Test webhook forwarding configuration
test_webhook_forwarding() {
    if [[ ! -f "/opt/n8n/user-configs/webhook-config.json" ]]; then
        echo "Webhook forwarding config not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/webhook-config.json" >/dev/null 2>&1; then
        echo "Invalid webhook config JSON"
        return 1
    fi
    
    # Check webhook forwarding is enabled
    if ! jq -e '.webhookForwarding.enabled' "/opt/n8n/user-configs/webhook-config.json" >/dev/null 2>&1; then
        echo "Webhook forwarding not enabled"
        return 1
    fi
    
    # Check forwardTo URL
    local forward_url=$(jq -r '.webhookForwarding.forwardTo' "/opt/n8n/user-configs/webhook-config.json")
    if [[ "$forward_url" == "null" || -z "$forward_url" ]]; then
        echo "Webhook forward URL not configured"
        return 1
    fi
    
    return 0
}

# Test webhook forwarder script
test_webhook_forwarder_script() {
    if [[ ! -f "/opt/n8n/scripts/webhook-forwarder.js" ]]; then
        echo "Webhook forwarder script not found"
        return 1
    fi
    
    # Basic syntax check for JavaScript
    if command -v node >/dev/null 2>&1; then
        if ! node -c "/opt/n8n/scripts/webhook-forwarder.js" 2>/dev/null; then
            echo "Webhook forwarder script has syntax errors"
            return 1
        fi
    fi
    
    return 0
}

# Test network security configuration
test_network_security() {
    if [[ ! -f "/opt/n8n/user-configs/network-security.json" ]]; then
        echo "Network security config not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/network-security.json" >/dev/null 2>&1; then
        echo "Invalid network security config JSON"
        return 1
    fi
    
    # Check allowed IPs
    if ! jq -e '.networkSecurity.allowedIPs' "/opt/n8n/user-configs/network-security.json" >/dev/null 2>&1; then
        echo "Allowed IPs not configured"
        return 1
    fi
    
    return 0
}

# Test firewall setup script
test_firewall_setup() {
    if [[ ! -f "/opt/n8n/scripts/setup-firewall.sh" ]]; then
        echo "Firewall setup script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/setup-firewall.sh" ]]; then
        echo "Firewall setup script not executable"
        return 1
    fi
    
    return 0
}

# Test load balancing configuration
test_load_balancing() {
    if [[ ! -f "/opt/n8n/user-configs/load-balancer.json" ]]; then
        echo "Load balancer config not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/load-balancer.json" >/dev/null 2>&1; then
        echo "Invalid load balancer config JSON"
        return 1
    fi
    
    # Test load balancer configuration script
    if [[ ! -f "/opt/n8n/scripts/configure-load-balancer.sh" ]]; then
        echo "Load balancer configuration script not found"
        return 1
    fi
    
    return 0
}

# Test health check script
test_health_checks() {
    if [[ ! -f "/opt/n8n/scripts/health-check.sh" ]]; then
        echo "Health check script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/health-check.sh" ]]; then
        echo "Health check script not executable"
        return 1
    fi
    
    # Test health check execution (dry run)
    if ! timeout 10s /opt/n8n/scripts/health-check.sh --dry-run >/dev/null 2>&1; then
        echo "Health check script failed to execute"
        return 1
    fi
    
    return 0
}

# Test session storage configuration
test_session_storage() {
    if [[ ! -f "/opt/n8n/user-configs/session-storage.json" ]]; then
        echo "Session storage config not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/session-storage.json" >/dev/null 2>&1; then
        echo "Invalid session storage config JSON"
        return 1
    fi
    
    # Check session manager script
    if [[ ! -f "/opt/n8n/scripts/session-manager.js" ]]; then
        echo "Session manager script not found"
        return 1
    fi
    
    # Basic syntax check for JavaScript
    if command -v node >/dev/null 2>&1; then
        if ! node -c "/opt/n8n/scripts/session-manager.js" 2>/dev/null; then
            echo "Session manager script has syntax errors"
            return 1
        fi
    fi
    
    return 0
}

# Test file transfer configuration
test_file_transfer() {
    if [[ ! -f "/opt/n8n/user-configs/file-transfer.json" ]]; then
        echo "File transfer config not found"
        return 1
    fi
    
    if ! jq '.' "/opt/n8n/user-configs/file-transfer.json" >/dev/null 2>&1; then
        echo "Invalid file transfer config JSON"
        return 1
    fi
    
    # Check file transfer script
    if [[ ! -f "/opt/n8n/scripts/file-transfer.sh" ]]; then
        echo "File transfer script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/file-transfer.sh" ]]; then
        echo "File transfer script not executable"
        return 1
    fi
    
    # Check encryption key
    if [[ ! -f "/opt/n8n/ssl/file-encryption.key" ]]; then
        echo "File encryption key not found"
        return 1
    fi
    
    return 0
}

# Test health check cron job
test_health_check_cron() {
    # Check if health check cron job exists
    if ! crontab -l 2>/dev/null | grep -q "health-check.sh"; then
        echo "Health check cron job not found"
        return 1
    fi
    
    return 0
}

# Test UFW firewall rules
test_ufw_rules() {
    # Skip if UFW is not installed
    if ! command -v ufw >/dev/null 2>&1; then
        echo "UFW not installed, skipping firewall tests"
        return 0
    fi
    
    # Check if UFW is active
    if ! ufw status | grep -q "Status: active"; then
        echo "UFW firewall is not active"
        return 1
    fi
    
    # Check for SSH rule
    if ! ufw status | grep -q "22/tcp.*ALLOW"; then
        echo "SSH rule not found in UFW"
        return 1
    fi
    
    # Check for HTTP rule
    if ! ufw status | grep -q "80/tcp.*ALLOW"; then
        echo "HTTP rule not found in UFW"
        return 1
    fi
    
    # Check for HTTPS rule
    if ! ufw status | grep -q "443/tcp.*ALLOW"; then
        echo "HTTPS rule not found in UFW"
        return 1
    fi
    
    return 0
}

# Test API endpoint accessibility
test_api_endpoints() {
    # Skip if n8n is not running
    if ! curl -s "http://localhost:5678" >/dev/null 2>&1; then
        echo "n8n server not accessible, skipping API endpoint tests"
        return 0
    fi
    
    # Test health endpoint
    if ! curl -s "http://localhost:5678/health" >/dev/null 2>&1; then
        echo "Health endpoint not accessible"
        return 1
    fi
    
    return 0
}

# Test webhook signature generation
test_webhook_signatures() {
    # Test if openssl is available for signature generation
    if ! command -v openssl >/dev/null 2>&1; then
        echo "OpenSSL not available for webhook signatures"
        return 1
    fi
    
    # Test signature generation
    local test_payload='{"test": "data"}'
    local test_secret="test-secret"
    
    local signature=$(echo -n "$test_payload" | openssl dgst -sha256 -hmac "$test_secret" | cut -d' ' -f2)
    
    if [[ -z "$signature" ]]; then
        echo "Failed to generate webhook signature"
        return 1
    fi
    
    return 0
}

# Test cross-server environment variables
test_cross_server_environment() {
    local required_vars=(
        "WEBAPP_SERVER_IP"
        "WEBAPP_WEBHOOK_URL"
        "API_AUTH_ENABLED"
        "WEBHOOK_FORWARDING_ENABLED"
        "HEALTH_CHECK_ENABLED"
        "FILE_TRANSFER_ENABLED"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Missing environment variable: $var"
            return 1
        fi
    done
    
    return 0
}

# Test SSL certificate paths
test_ssl_certificates() {
    # Check if SSL directory exists
    if [[ ! -d "/opt/n8n/ssl" ]]; then
        echo "SSL directory not found"
        return 1
    fi
    
    # Check if we can write to SSL directory (for key generation)
    if [[ ! -w "/opt/n8n/ssl" ]]; then
        echo "SSL directory not writable"
        return 1
    fi
    
    return 0
}

# Test configuration file permissions
test_config_permissions() {
    local config_files=(
        "/opt/n8n/user-configs/api-auth.json"
        "/opt/n8n/user-configs/webhook-config.json"
        "/opt/n8n/user-configs/network-security.json"
        "/opt/n8n/user-configs/session-storage.json"
        "/opt/n8n/user-configs/file-transfer.json"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ ! -r "$config_file" ]]; then
            echo "Config file not readable: $config_file"
            return 1
        fi
    done
    
    return 0
}

# Test network connectivity
test_network_connectivity() {
    # Test if we can resolve DNS
    if ! nslookup google.com >/dev/null 2>&1; then
        echo "DNS resolution not working"
        return 1
    fi
    
    # Test outbound HTTPS connectivity
    if ! curl -s --max-time 5 "https://www.google.com" >/dev/null 2>&1; then
        echo "Outbound HTTPS connectivity not working"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_section "Cross-Server Communication Tests"
    
    # Check if cross-server communication is enabled
    if [[ "${API_AUTH_ENABLED,,}" != "true" ]]; then
        log_info "Cross-server communication is disabled, skipping tests"
        return 0
    fi
    
    run_test "API authentication configuration" test_api_authentication
    run_test "Webhook forwarding configuration" test_webhook_forwarding
    run_test "Webhook forwarder script" test_webhook_forwarder_script
    run_test "Network security configuration" test_network_security
    run_test "Firewall setup script" test_firewall_setup
    run_test "Load balancing configuration" test_load_balancing
    run_test "Health check script" test_health_checks
    run_test "Session storage configuration" test_session_storage
    run_test "File transfer configuration" test_file_transfer
    run_test "Health check cron job" test_health_check_cron
    run_test "UFW firewall rules" test_ufw_rules
    run_test "API endpoint accessibility" test_api_endpoints
    run_test "Webhook signature generation" test_webhook_signatures
    run_test "Environment variables" test_cross_server_environment
    run_test "SSL certificates" test_ssl_certificates
    run_test "Configuration file permissions" test_config_permissions
    run_test "Network connectivity" test_network_connectivity
    
    log_subsection "Cross-Server Communication Test Results:"
    log_info "Total tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_pass "All cross-server communication tests passed!"
        return 0
    else
        log_error "$FAILED_TESTS cross-server communication tests failed"
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
