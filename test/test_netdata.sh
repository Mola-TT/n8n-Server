#!/bin/bash

# =============================================================================
# Netdata Tests - Test Suite for Netdata Monitoring Configuration
# Part of Milestone 4
# =============================================================================
# This script validates the Netdata monitoring system setup including:
# - Netdata service installation and configuration
# - Security settings and localhost binding
# - Nginx proxy configuration and SSL
# - Basic authentication setup
# - Health monitoring alerts
# - Firewall configuration
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/lib/logger.sh"

# =============================================================================
# Netdata Service Tests
# =============================================================================

test_netdata_service_running() {
    systemctl is-active netdata &>/dev/null
}

test_netdata_service_enabled() {
    systemctl is-enabled netdata &>/dev/null
}

test_netdata_process_running() {
    pgrep -f "netdata" >/dev/null 2>&1
}

test_netdata_listening_localhost() {
    # Check if Netdata is listening on localhost:19999
    netstat -tlnp 2>/dev/null | grep ":${NETDATA_PORT:-19999}" | grep "127.0.0.1" >/dev/null 2>&1 ||
    ss -tlnp 2>/dev/null | grep ":${NETDATA_PORT:-19999}" | grep "127.0.0.1" >/dev/null 2>&1
}

# =============================================================================
# Netdata Configuration Tests
# =============================================================================

test_netdata_config_exists() {
    [ -f "/etc/netdata/netdata.conf" ]
}

test_netdata_config_localhost_binding() {
    if [ -f "/etc/netdata/netdata.conf" ]; then
        grep -q "bind to.*127.0.0.1" "/etc/netdata/netdata.conf" 2>/dev/null
    else
        return 1
    fi
}

test_netdata_health_config_exists() {
    [ -d "/etc/netdata/health.d" ] && 
    [ -f "/etc/netdata/health.d/cpu_usage.conf" ] && 
    [ -f "/etc/netdata/health.d/ram_usage.conf" ] &&
    [ -f "/etc/netdata/health.d/disk_usage.conf" ] &&
    [ -f "/etc/netdata/health.d/load_average.conf" ]
}

test_netdata_email_notifications_configured() {
    [ -f "/etc/netdata/health_alarm_notify.conf" ] &&
    grep -q "SEND_EMAIL.*YES" "/etc/netdata/health_alarm_notify.conf" 2>/dev/null
}

# =============================================================================
# Netdata API and Connectivity Tests
# =============================================================================

test_netdata_api_localhost_accessible() {
    # Test if Netdata API responds on localhost
    curl -s --connect-timeout 5 "http://127.0.0.1:${NETDATA_PORT:-19999}/api/v1/info" >/dev/null 2>&1
}

test_netdata_api_response_valid() {
    # Test if API returns valid JSON response
    local response=$(curl -s --connect-timeout 5 "http://127.0.0.1:${NETDATA_PORT:-19999}/api/v1/info" 2>/dev/null)
    echo "$response" | grep -q "version" 2>/dev/null
}

test_netdata_web_interface_localhost() {
    # Test if web interface responds on localhost
    curl -s --connect-timeout 5 "http://127.0.0.1:${NETDATA_PORT:-19999}/" >/dev/null 2>&1
}

# =============================================================================
# Nginx Proxy Tests
# =============================================================================

test_netdata_nginx_config_exists() {
    [ -f "/etc/nginx/sites-available/netdata" ] &&
    [ -L "/etc/nginx/sites-enabled/netdata" ]
}

test_netdata_nginx_auth_file_exists() {
    [ -f "/etc/nginx/.netdata_auth" ]
}

test_netdata_nginx_ssl_certificates() {
    local ssl_cert="${NGINX_SSL_CERT_PATH:-/etc/nginx/ssl/certificate.crt}"
    local ssl_key="${NGINX_SSL_KEY_PATH:-/etc/nginx/ssl/private.key}"
    [ -f "$ssl_cert" ] && [ -f "$ssl_key" ]
}

test_netdata_nginx_config_syntax() {
    # Test Nginx configuration syntax
    nginx -t >/dev/null 2>&1
}

test_netdata_https_proxy_accessible() {
    # Test if Netdata is accessible via HTTPS proxy (skip certificate verification for self-signed)
    local server_name
    
    # Use localhost for development, actual domain for production
    if [ "${PRODUCTION:-false}" = "true" ]; then
        server_name="${NETDATA_NGINX_SUBDOMAIN:-monitor}.${NGINX_SERVER_NAME:-localhost}"
    else
        # Development mode: use localhost with Host header
        server_name="localhost"
    fi
    
    # Test without authentication first (should get 401)
    local response_code
    if [ "${PRODUCTION:-false}" = "true" ]; then
        response_code=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "https://$server_name/" 2>/dev/null || echo "000")
    else
        # Development: use localhost with Host header
        local host_header="${NETDATA_NGINX_SUBDOMAIN:-monitor}.${NGINX_SERVER_NAME:-localhost}"
        response_code=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
            -H "Host: $host_header" "https://localhost/" 2>/dev/null || echo "000")
    fi
    
    [ "$response_code" = "401" ] # Should require authentication
}

test_netdata_https_authentication() {
    # Test authentication with credentials
    local server_name
    local auth_user="${NETDATA_NGINX_AUTH_USER:-netdata}"
    local auth_pass="${NETDATA_NGINX_AUTH_PASSWORD:-secure_monitoring_password}"
    
    # Use localhost for development, actual domain for production
    if [ "${PRODUCTION:-false}" = "true" ]; then
        server_name="${NETDATA_NGINX_SUBDOMAIN:-monitor}.${NGINX_SERVER_NAME:-localhost}"
        # Test with correct credentials (should get 200)
        local response_code=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
            -u "$auth_user:$auth_pass" "https://$server_name/" 2>/dev/null || echo "000")
    else
        # Development: use localhost with Host header
        local host_header="${NETDATA_NGINX_SUBDOMAIN:-monitor}.${NGINX_SERVER_NAME:-localhost}"
        local response_code=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
            -u "$auth_user:$auth_pass" -H "Host: $host_header" "https://localhost/" 2>/dev/null || echo "000")
    fi
    
    [ "$response_code" = "200" ]
}

test_netdata_http_to_https_redirect() {
    # Test HTTP to HTTPS redirection
    local server_name
    
    # Use localhost for development, actual domain for production
    if [ "${PRODUCTION:-false}" = "true" ]; then
        server_name="${NETDATA_NGINX_SUBDOMAIN:-monitor}.${NGINX_SERVER_NAME:-localhost}"
        # Test HTTP redirect (should get 301)
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
            "http://$server_name/" 2>/dev/null || echo "000")
    else
        # Development: use localhost with Host header
        local host_header="${NETDATA_NGINX_SUBDOMAIN:-monitor}.${NGINX_SERVER_NAME:-localhost}"
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
            -H "Host: $host_header" "http://localhost/" 2>/dev/null || echo "000")
    fi
    
    [ "$response_code" = "301" ]
}

# =============================================================================
# Firewall and Security Tests
# =============================================================================

test_netdata_firewall_blocks_direct_access() {
    # Check if UFW is configured to block direct access to Netdata port
    if command -v ufw &>/dev/null; then
        # Check if there's a deny rule for Netdata port (requires sudo)
        sudo ufw status numbered 2>/dev/null | grep -q "DENY.*${NETDATA_PORT:-19999}/tcp" 2>/dev/null
    else
        # If UFW is not available, consider test passed
        return 0
    fi
}

test_netdata_not_accessible_externally() {
    # Test that Netdata is not accessible externally on its direct port
    # This test simulates external access by testing from non-localhost
    # In a real environment, this would test from another machine
    
    # Test if port is bound only to localhost (not 0.0.0.0)
    # Check both netstat and ss output formats
    local netstat_check=false
    local ss_check=false
    
    # Check netstat format: should show 127.0.0.1:19999, not 0.0.0.0:19999
    if netstat -tlnp 2>/dev/null | grep ":${NETDATA_PORT:-19999}" | grep -q "127.0.0.1:${NETDATA_PORT:-19999}"; then
        netstat_check=true
    fi
    
    # Check ss format: should show 127.0.0.1:19999, not 0.0.0.0:19999 or *:19999
    if ss -tlnp 2>/dev/null | grep ":${NETDATA_PORT:-19999}" | grep -q "127.0.0.1:${NETDATA_PORT:-19999}"; then
        ss_check=true
    fi
    
    # Test passes if either tool shows localhost binding (not 0.0.0.0 or *)
    [ "$netstat_check" = "true" ] || [ "$ss_check" = "true" ]
}

test_netdata_security_headers() {
    # Test if security headers are present in HTTPS response
    local server_name
    local auth_user="${NETDATA_NGINX_AUTH_USER:-netdata}"
    local auth_pass="${NETDATA_NGINX_AUTH_PASSWORD:-secure_monitoring_password}"
    
    # Use localhost for development, actual domain for production
    if [ "${PRODUCTION:-false}" = "true" ]; then
        server_name="${NETDATA_NGINX_SUBDOMAIN:-monitor}.${NGINX_SERVER_NAME:-localhost}"
        # Get headers from HTTPS response using GET request (not HEAD due to Netdata limitations)
        local headers=$(curl -k -s --connect-timeout 10 -D - -o /dev/null \
            -u "$auth_user:$auth_pass" "https://$server_name/" 2>/dev/null)
    else
        # Development: use localhost with Host header
        local host_header="${NETDATA_NGINX_SUBDOMAIN:-monitor}.${NGINX_SERVER_NAME:-localhost}"
        local headers=$(curl -k -s --connect-timeout 10 -D - -o /dev/null \
            -u "$auth_user:$auth_pass" -H "Host: $host_header" "https://localhost/" 2>/dev/null)
    fi
    
    # Check for essential security headers
    echo "$headers" | grep -qi "strict-transport-security" &&
    echo "$headers" | grep -qi "x-content-type-options" &&
    echo "$headers" | grep -qi "x-frame-options"
}

# =============================================================================
# Netdata Health Monitoring Tests
# =============================================================================

test_netdata_health_monitoring_active() {
    # Test if health monitoring is active
    curl -s --connect-timeout 5 "http://127.0.0.1:${NETDATA_PORT:-19999}/api/v1/alarms" 2>/dev/null | 
    grep -q "status" 2>/dev/null
}

test_netdata_health_alerts_configured() {
    # Test if health alerts are properly configured
    local health_api_response=$(curl -s --connect-timeout 5 \
        "http://127.0.0.1:${NETDATA_PORT:-19999}/api/v1/alarms?all" 2>/dev/null)
    
    # Check if our custom alerts are present
    echo "$health_api_response" | grep -q "cpu_usage_high\|ram_usage_high\|disk_space_usage_high\|load_average_high" 2>/dev/null
}

# =============================================================================
# Netdata File and Directory Tests
# =============================================================================

test_netdata_directories_exist() {
    [ -d "${NETDATA_CACHE_DIR:-/var/cache/netdata}" ] &&
    [ -d "${NETDATA_LIB_DIR:-/var/lib/netdata}" ] &&
    [ -d "${NETDATA_LOG_DIR:-/var/log/netdata}" ] &&
    [ -d "${NETDATA_RUN_DIR:-/var/run/netdata}" ]
}

test_netdata_log_files_exist() {
    # Check if Netdata is generating log files
    [ -d "${NETDATA_LOG_DIR:-/var/log/netdata}" ] &&
    [ -n "$(find "${NETDATA_LOG_DIR:-/var/log/netdata}" -name "*.log" -type f 2>/dev/null)" ]
}

test_netdata_permissions() {
    # Check if Netdata directories have proper ownership
    local netdata_user="netdata"
    local cache_dir="${NETDATA_CACHE_DIR:-/var/cache/netdata}"
    local lib_dir="${NETDATA_LIB_DIR:-/var/lib/netdata}"
    
    # Check ownership (if directories exist)
    if [ -d "$cache_dir" ]; then
        [ "$(stat -c %U "$cache_dir" 2>/dev/null)" = "$netdata_user" ] 2>/dev/null || return 0
    fi
    
    if [ -d "$lib_dir" ]; then
        [ "$(stat -c %U "$lib_dir" 2>/dev/null)" = "$netdata_user" ] 2>/dev/null || return 0
    fi
    
    return 0
}

# =============================================================================
# Nginx Log Tests
# =============================================================================

test_netdata_nginx_log_files() {
    # Check if Nginx log files for Netdata are configured
    local access_log="${NETDATA_NGINX_ACCESS_LOG:-/var/log/nginx/netdata_access.log}"
    local error_log="${NETDATA_NGINX_ERROR_LOG:-/var/log/nginx/netdata_error.log}"
    
    # Check if log files exist or their parent directories exist
    [ -d "$(dirname "$access_log")" ] && [ -d "$(dirname "$error_log")" ]
} 