#!/bin/bash

# ==============================================================================
# Security Test Suite for n8n Server - Milestone 9
# ==============================================================================
# This script tests security configurations including fail2ban, nginx security,
# rate limiting, and security monitoring
# ==============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Test configuration
TEST_SECTION="Security System"
TESTS_PASSED=0
TESTS_FAILED=0

# Security paths for testing
SECURITY_SCRIPTS_DIR="/opt/n8n/scripts"
SECURITY_LOG_FILE="/var/log/n8n_security.log"
FAIL2BAN_FILTER_DIR="/etc/fail2ban/filter.d"
FAIL2BAN_JAIL_DIR="/etc/fail2ban/jail.d"

# ==============================================================================
# Test Utility Functions
# ==============================================================================

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "Running test: $test_name"
    
    if $test_function >/dev/null 2>&1; then
        log_pass "✓ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

run_test_verbose() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "Running test: $test_name"
    
    local output
    output=$($test_function 2>&1)
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_pass "✓ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ $test_name"
        log_error "  Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ==============================================================================
# fail2ban Installation Tests
# ==============================================================================

test_fail2ban_installed() {
    command -v fail2ban-client &>/dev/null
}

test_fail2ban_service_exists() {
    systemctl list-unit-files | grep -q "fail2ban.service"
}

test_fail2ban_service_running() {
    systemctl is-active fail2ban &>/dev/null
}

test_fail2ban_jail_local_exists() {
    [ -f /etc/fail2ban/jail.local ]
}

# ==============================================================================
# fail2ban Jail Configuration Tests
# ==============================================================================

test_ssh_jail_configured() {
    [ -f "${FAIL2BAN_JAIL_DIR}/n8n-sshd.conf" ] || \
    grep -q "\[sshd\]" /etc/fail2ban/jail.local 2>/dev/null
}

test_nginx_jail_configured() {
    [ -f "${FAIL2BAN_JAIL_DIR}/n8n-nginx.conf" ]
}

test_api_jail_configured() {
    [ -f "${FAIL2BAN_JAIL_DIR}/n8n-api.conf" ]
}

test_ssh_jail_enabled() {
    fail2ban-client status sshd &>/dev/null
}

# ==============================================================================
# fail2ban Filter Tests
# ==============================================================================

test_nginx_auth_filter_exists() {
    [ -f "${FAIL2BAN_FILTER_DIR}/nginx-http-auth-n8n.conf" ]
}

test_badbots_filter_exists() {
    [ -f "${FAIL2BAN_FILTER_DIR}/nginx-badbots-n8n.conf" ]
}

test_webhook_abuse_filter_exists() {
    [ -f "${FAIL2BAN_FILTER_DIR}/nginx-webhook-abuse.conf" ]
}

test_api_auth_filter_exists() {
    [ -f "${FAIL2BAN_FILTER_DIR}/n8n-api-auth.conf" ]
}

# ==============================================================================
# fail2ban Functionality Tests
# ==============================================================================

test_fail2ban_can_list_jails() {
    fail2ban-client status &>/dev/null
}

test_fail2ban_jail_count() {
    local jail_count=$(fail2ban-client status 2>/dev/null | grep "Number of jail" | awk '{print $NF}')
    [ "$jail_count" -gt 0 ] 2>/dev/null
}

test_fail2ban_ignoreip_configured() {
    grep -q "ignoreip" /etc/fail2ban/jail.local 2>/dev/null
}

# ==============================================================================
# Nginx Security Configuration Tests
# ==============================================================================

test_nginx_security_conf_exists() {
    [ -f /etc/nginx/conf.d/security.conf ]
}

test_nginx_bad_user_agents_conf_exists() {
    [ -f /etc/nginx/conf.d/bad_user_agents.conf ]
}

test_nginx_rate_limits_conf_exists() {
    [ -f /etc/nginx/conf.d/rate_limits.conf ]
}

test_nginx_security_snippet_exists() {
    [ -f /etc/nginx/snippets/n8n-security.conf ]
}

test_nginx_config_valid() {
    nginx -t 2>/dev/null
}

test_nginx_service_running() {
    systemctl is-active nginx &>/dev/null
}

# ==============================================================================
# Security Headers Tests
# ==============================================================================

test_nginx_hides_version() {
    grep -q "server_tokens off" /etc/nginx/conf.d/security.conf 2>/dev/null
}

test_nginx_has_xss_protection() {
    grep -q "X-XSS-Protection" /etc/nginx/conf.d/security.conf 2>/dev/null
}

test_nginx_has_content_type_options() {
    grep -q "X-Content-Type-Options" /etc/nginx/conf.d/security.conf 2>/dev/null
}

test_nginx_has_referrer_policy() {
    grep -q "Referrer-Policy" /etc/nginx/conf.d/security.conf 2>/dev/null
}

test_nginx_has_permissions_policy() {
    grep -q "Permissions-Policy" /etc/nginx/conf.d/security.conf 2>/dev/null
}

# ==============================================================================
# Rate Limiting Tests
# ==============================================================================

test_rate_limit_webhook_zone() {
    grep -q "webhook_limit" /etc/nginx/conf.d/rate_limits.conf 2>/dev/null
}

test_rate_limit_api_zone() {
    grep -q "api_limit" /etc/nginx/conf.d/rate_limits.conf 2>/dev/null
}

test_rate_limit_login_zone() {
    grep -q "login_limit" /etc/nginx/conf.d/rate_limits.conf 2>/dev/null
}

test_connection_limit_zone() {
    grep -q "conn_per_ip" /etc/nginx/conf.d/rate_limits.conf 2>/dev/null
}

# ==============================================================================
# Security Monitoring Tests
# ==============================================================================

test_security_monitor_script_exists() {
    [ -f "${SECURITY_SCRIPTS_DIR}/security_monitor.sh" ]
}

test_security_monitor_script_executable() {
    [ -x "${SECURITY_SCRIPTS_DIR}/security_monitor.sh" ]
}

test_security_report_script_exists() {
    [ -f "${SECURITY_SCRIPTS_DIR}/security_report.sh" ]
}

test_security_report_script_executable() {
    [ -x "${SECURITY_SCRIPTS_DIR}/security_report.sh" ]
}

test_security_monitor_timer_exists() {
    [ -f /etc/systemd/system/n8n-security-monitor.timer ]
}

test_security_monitor_timer_enabled() {
    systemctl is-enabled n8n-security-monitor.timer &>/dev/null
}

test_security_log_exists() {
    [ -f "$SECURITY_LOG_FILE" ]
}

# ==============================================================================
# IP Whitelist Tests
# ==============================================================================

test_whitelist_script_exists() {
    [ -f "${SECURITY_SCRIPTS_DIR}/manage_whitelist.sh" ]
}

test_whitelist_script_executable() {
    [ -x "${SECURITY_SCRIPTS_DIR}/manage_whitelist.sh" ]
}

test_whitelist_directory_exists() {
    [ -d /etc/n8n ]
}

# ==============================================================================
# Security Report Cron Tests
# ==============================================================================

test_security_report_cron_exists() {
    [ -f /etc/cron.d/n8n-security-report ]
}

# ==============================================================================
# Geo-Blocking Tests (Optional)
# ==============================================================================

test_geo_blocking_script_exists() {
    [ -f "$PROJECT_ROOT/setup/geo_blocking.sh" ]
}

test_geo_management_script_exists() {
    [ -f "${SECURITY_SCRIPTS_DIR}/manage_geo_blocking.sh" ]
}

test_ipset_installed() {
    # ipset is only required when geo-blocking is enabled
    # Check if geo-blocking is enabled in environment
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        source "$PROJECT_ROOT/conf/user.env" 2>/dev/null
    fi
    if [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        source "$PROJECT_ROOT/conf/default.env" 2>/dev/null
    fi
    
    # If geo-blocking is disabled, test passes (ipset not required)
    if [[ "${GEO_BLOCKING_ENABLED:-false}" != "true" ]]; then
        return 0
    fi
    
    # If geo-blocking is enabled, ipset must be installed
    command -v ipset &>/dev/null
}

# ==============================================================================
# Integration Tests
# ==============================================================================

test_fail2ban_can_check_status() {
    local output
    output=$(fail2ban-client status 2>&1)
    [ $? -eq 0 ] && echo "$output" | grep -q "Jail list"
}

test_security_monitor_can_run() {
    if [ -x "${SECURITY_SCRIPTS_DIR}/security_monitor.sh" ]; then
        "${SECURITY_SCRIPTS_DIR}/security_monitor.sh" --status &>/dev/null
        return $?
    fi
    return 1
}

test_security_report_can_generate() {
    if [ -x "${SECURITY_SCRIPTS_DIR}/security_report.sh" ]; then
        local output
        output=$("${SECURITY_SCRIPTS_DIR}/security_report.sh" 2>&1)
        echo "$output" | grep -q "Security Report"
    fi
    return 1
}

# ==============================================================================
# Live Security Tests (Simulated)
# ==============================================================================

test_nginx_blocks_bad_user_agent() {
    # Test that nginx blocks requests with bad user agents
    # This is a passive test - checks config, doesn't actually send requests
    grep -q "nikto\|sqlmap" /etc/nginx/conf.d/bad_user_agents.conf 2>/dev/null
}

test_nginx_blocks_common_exploits() {
    grep -q "block_common_exploits" /etc/nginx/conf.d/security.conf 2>/dev/null
}

test_fail2ban_has_valid_config() {
    fail2ban-client -t &>/dev/null
}

# ==============================================================================
# Main Test Runner
# ==============================================================================

print_section_header() {
    echo "================================================================================"
    echo "$1"
    echo "================================================================================"
}

run_all_tests() {
    print_section_header "Security System Tests - Milestone 9"
    
    # fail2ban Installation Tests
    print_section_header "fail2ban Installation Tests"
    run_test "fail2ban is installed" test_fail2ban_installed
    run_test "fail2ban service exists" test_fail2ban_service_exists
    run_test "fail2ban service is running" test_fail2ban_service_running
    run_test "fail2ban jail.local exists" test_fail2ban_jail_local_exists
    
    # fail2ban Jail Configuration Tests
    print_section_header "fail2ban Jail Configuration Tests"
    run_test "SSH jail is configured" test_ssh_jail_configured
    run_test "Nginx jail is configured" test_nginx_jail_configured
    run_test "API jail is configured" test_api_jail_configured
    run_test "SSH jail is enabled" test_ssh_jail_enabled
    
    # fail2ban Filter Tests
    print_section_header "fail2ban Filter Tests"
    run_test "Nginx auth filter exists" test_nginx_auth_filter_exists
    run_test "Bad bots filter exists" test_badbots_filter_exists
    run_test "Webhook abuse filter exists" test_webhook_abuse_filter_exists
    run_test "API auth filter exists" test_api_auth_filter_exists
    
    # fail2ban Functionality Tests
    print_section_header "fail2ban Functionality Tests"
    run_test "fail2ban can list jails" test_fail2ban_can_list_jails
    run_test "fail2ban has active jails" test_fail2ban_jail_count
    run_test "fail2ban ignoreip is configured" test_fail2ban_ignoreip_configured
    run_test "fail2ban config is valid" test_fail2ban_has_valid_config
    
    # Nginx Security Configuration Tests
    print_section_header "Nginx Security Configuration Tests"
    run_test "Nginx security config exists" test_nginx_security_conf_exists
    run_test "Nginx bad user agents config exists" test_nginx_bad_user_agents_conf_exists
    run_test "Nginx rate limits config exists" test_nginx_rate_limits_conf_exists
    run_test "Nginx security snippet exists" test_nginx_security_snippet_exists
    run_test "Nginx config is valid" test_nginx_config_valid
    run_test "Nginx service is running" test_nginx_service_running
    
    # Security Headers Tests
    print_section_header "Security Headers Tests"
    run_test "Nginx hides version" test_nginx_hides_version
    run_test "XSS protection header configured" test_nginx_has_xss_protection
    run_test "Content-Type-Options header configured" test_nginx_has_content_type_options
    run_test "Referrer-Policy header configured" test_nginx_has_referrer_policy
    run_test "Permissions-Policy header configured" test_nginx_has_permissions_policy
    
    # Rate Limiting Tests
    print_section_header "Rate Limiting Tests"
    run_test "Webhook rate limit zone exists" test_rate_limit_webhook_zone
    run_test "API rate limit zone exists" test_rate_limit_api_zone
    run_test "Login rate limit zone exists" test_rate_limit_login_zone
    run_test "Connection limit zone exists" test_connection_limit_zone
    
    # Security Monitoring Tests
    print_section_header "Security Monitoring Tests"
    run_test "Security monitor script exists" test_security_monitor_script_exists
    run_test "Security monitor script is executable" test_security_monitor_script_executable
    run_test "Security report script exists" test_security_report_script_exists
    run_test "Security report script is executable" test_security_report_script_executable
    run_test "Security monitor timer exists" test_security_monitor_timer_exists
    run_test "Security monitor timer is enabled" test_security_monitor_timer_enabled
    run_test "Security log file exists" test_security_log_exists
    
    # IP Whitelist Tests
    print_section_header "IP Whitelist Tests"
    run_test "Whitelist script exists" test_whitelist_script_exists
    run_test "Whitelist script is executable" test_whitelist_script_executable
    run_test "Whitelist directory exists" test_whitelist_directory_exists
    
    # Security Report Cron Tests
    print_section_header "Security Report Cron Tests"
    run_test "Security report cron exists" test_security_report_cron_exists
    
    # Geo-Blocking Tests (Optional)
    print_section_header "Geo-Blocking Tests (Optional)"
    run_test "Geo-blocking script exists" test_geo_blocking_script_exists
    run_test "ipset is installed" test_ipset_installed
    
    # Integration Tests
    print_section_header "Integration Tests"
    run_test "fail2ban status check works" test_fail2ban_can_check_status
    run_test "Nginx blocks bad user agents (config)" test_nginx_blocks_bad_user_agent
    run_test "Nginx blocks common exploits (config)" test_nginx_blocks_common_exploits
    
    # Print summary
    print_section_header "Test Summary"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo "================================================================================"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_pass "All security tests passed!"
        return 0
    else
        log_warn "Some security tests failed. Review the output above."
        return 1
    fi
}

# Run tests
run_all_tests
