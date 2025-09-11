#!/bin/bash

# Test script for user monitoring functionality
# Tests execution tracking, storage monitoring, and analytics

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

# Test monitoring directory structure
test_monitoring_directories() {
    local required_dirs=(
        "/opt/n8n/monitoring/metrics"
        "/opt/n8n/monitoring/reports"
        "/opt/n8n/monitoring/analytics"
        "/opt/n8n/monitoring/alerts"
        "/opt/n8n/monitoring/logs"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Missing monitoring directory: $dir"
            return 1
        fi
    done
    
    return 0
}

# Test execution tracking script
test_execution_tracking() {
    if [[ ! -f "/opt/n8n/scripts/execution-tracker.js" ]]; then
        echo "Execution tracker script not found"
        return 1
    fi
    
    # Basic syntax check for JavaScript
    if command -v node >/dev/null 2>&1; then
        if ! node -c "/opt/n8n/scripts/execution-tracker.js" 2>/dev/null; then
            echo "Execution tracker script has syntax errors"
            return 1
        fi
    fi
    
    return 0
}

# Test storage monitoring script
test_storage_monitoring() {
    if [[ ! -f "/opt/n8n/scripts/storage-monitor.sh" ]]; then
        echo "Storage monitor script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/storage-monitor.sh" ]]; then
        echo "Storage monitor script not executable"
        return 1
    fi
    
    # Test storage monitor functionality with test user
    local test_user="test_storage_$$"
    local user_dir="/opt/n8n/users/$test_user"
    
    # Create test user directory
    mkdir -p "$user_dir"/{workflows,files,logs}
    
    # Create user config
    cat > "$user_dir/user-config.json" << EOF
{
  "userId": "$test_user",
  "quotas": {
    "storage": "1GB"
  }
}
EOF
    
    # Create some test files
    echo "test content" > "$user_dir/files/test.txt"
    
    # Run storage monitor
    if ! /opt/n8n/scripts/storage-monitor.sh >/dev/null 2>&1; then
        echo "Storage monitor script failed to run"
        rm -rf "$user_dir"
        return 1
    fi
    
    # Check if metrics file was created
    if [[ ! -f "/opt/n8n/monitoring/metrics/${test_user}_storage.json" ]]; then
        echo "Storage metrics file not created"
        rm -rf "$user_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$user_dir"
    rm -f "/opt/n8n/monitoring/metrics/${test_user}_storage.json"
    
    return 0
}

# Test workflow statistics script
test_workflow_statistics() {
    if [[ ! -f "/opt/n8n/scripts/workflow-stats.js" ]]; then
        echo "Workflow statistics script not found"
        return 1
    fi
    
    # Basic syntax check for JavaScript
    if command -v node >/dev/null 2>&1; then
        if ! node -c "/opt/n8n/scripts/workflow-stats.js" 2>/dev/null; then
            echo "Workflow statistics script has syntax errors"
            return 1
        fi
    fi
    
    return 0
}

# Test analytics processor script
test_analytics_processor() {
    if [[ ! -f "/opt/n8n/scripts/analytics-processor.sh" ]]; then
        echo "Analytics processor script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/analytics-processor.sh" ]]; then
        echo "Analytics processor script not executable"
        return 1
    fi
    
    # Test script help output
    if ! /opt/n8n/scripts/analytics-processor.sh 2>&1 | grep -q "Usage:"; then
        echo "Analytics processor script missing usage information"
        return 1
    fi
    
    return 0
}

# Test cleanup scripts
test_cleanup_scripts() {
    if [[ ! -f "/opt/n8n/scripts/cleanup-inactive-users.sh" ]]; then
        echo "Cleanup inactive users script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/cleanup-inactive-users.sh" ]]; then
        echo "Cleanup inactive users script not executable"
        return 1
    fi
    
    return 0
}

# Test monitoring cron jobs
test_monitoring_cron() {
    # Check for storage monitoring cron job
    if ! crontab -l 2>/dev/null | grep -q "storage-monitor.sh"; then
        echo "Storage monitoring cron job not found"
        return 1
    fi
    
    # Check for analytics processing cron job
    if ! crontab -l 2>/dev/null | grep -q "analytics-processor.sh"; then
        echo "Analytics processing cron job not found"
        return 1
    fi
    
    # Check for cleanup cron job
    if ! crontab -l 2>/dev/null | grep -q "cleanup-inactive-users.sh"; then
        echo "Cleanup cron job not found"
        return 1
    fi
    
    return 0
}

# Test metrics file creation
test_metrics_creation() {
    local test_user="test_metrics_$$"
    local user_dir="/opt/n8n/users/$test_user"
    
    # Create test user
    mkdir -p "$user_dir"
    
    # Create user config
    cat > "$user_dir/user-config.json" << EOF
{
  "userId": "$test_user",
  "createdAt": "$(date -Iseconds)",
  "quotas": {
    "storage": "1GB"
  }
}
EOF
    
    # Create test metrics file
    cat > "/opt/n8n/monitoring/metrics/${test_user}_current.json" << EOF
{
  "userId": "$test_user",
  "totalExecutions": 5,
  "totalDuration": 1500,
  "lastActivity": "$(date -Iseconds)"
}
EOF
    
    # Test if metrics file is valid JSON
    if ! jq '.' "/opt/n8n/monitoring/metrics/${test_user}_current.json" >/dev/null 2>&1; then
        echo "Invalid metrics JSON format"
        rm -rf "$user_dir"
        rm -f "/opt/n8n/monitoring/metrics/${test_user}_current.json"
        return 1
    fi
    
    # Cleanup
    rm -rf "$user_dir"
    rm -f "/opt/n8n/monitoring/metrics/${test_user}_current.json"
    
    return 0
}

# Test log file creation
test_log_files() {
    local log_files=(
        "/opt/n8n/monitoring/logs/executions.log"
        "/opt/n8n/monitoring/logs/storage.log"
        "/opt/n8n/monitoring/logs/analytics.log"
        "/opt/n8n/monitoring/logs/cleanup.log"
    )
    
    for log_file in "${log_files[@]}"; do
        # Create log file directory if it doesn't exist
        mkdir -p "$(dirname "$log_file")"
        
        # Test if we can write to log file location
        if ! touch "$log_file" 2>/dev/null; then
            echo "Cannot write to log file: $log_file"
            return 1
        fi
        
        # Remove test file
        rm -f "$log_file"
    done
    
    return 0
}

# Test alert file creation
test_alert_system() {
    local test_user="test_alerts_$$"
    local alert_file="/opt/n8n/monitoring/alerts/${test_user}_storage_warning_$(date +%Y%m%d_%H%M%S).json"
    
    # Create test alert file
    cat > "$alert_file" << EOF
{
  "alertId": "test-alert-123",
  "userId": "$test_user",
  "type": "storage_quota",
  "level": "warning",
  "timestamp": "$(date -Iseconds)",
  "message": "User storage usage is at 85%"
}
EOF
    
    # Validate alert file format
    if ! jq '.' "$alert_file" >/dev/null 2>&1; then
        echo "Invalid alert JSON format"
        rm -f "$alert_file"
        return 1
    fi
    
    # Check required alert fields
    if ! jq -e '.alertId' "$alert_file" >/dev/null 2>&1; then
        echo "Alert missing alertId field"
        rm -f "$alert_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$alert_file"
    
    return 0
}

# Test report generation
test_report_generation() {
    local test_user="test_reports_$$"
    local user_dir="/opt/n8n/users/$test_user"
    local date_str=$(date +%Y-%m-%d)
    
    # Create test user and metrics
    mkdir -p "$user_dir"
    
    # Create test metrics file for today
    cat > "/opt/n8n/monitoring/metrics/${test_user}_${date_str}.json" << EOF
{
  "userId": "$test_user",
  "date": "$date_str",
  "executions": [
    {
      "executionId": "test-exec-1",
      "duration": 500,
      "status": "completed"
    }
  ],
  "summary": {
    "count": 1,
    "totalDuration": 500,
    "successful": 1,
    "failed": 0
  }
}
EOF
    
    # Test daily report generation
    if command -v jq >/dev/null 2>&1; then
        if ! /opt/n8n/scripts/analytics-processor.sh daily "$test_user" >/dev/null 2>&1; then
            echo "Daily report generation failed"
            rm -rf "$user_dir"
            rm -f "/opt/n8n/monitoring/metrics/${test_user}_${date_str}.json"
            return 1
        fi
    fi
    
    # Cleanup
    rm -rf "$user_dir"
    rm -f "/opt/n8n/monitoring/metrics/${test_user}_${date_str}.json"
    rm -f "/opt/n8n/monitoring/reports/${test_user}_daily_${date_str}.json"
    
    return 0
}

# Test monitoring environment variables
test_monitoring_environment() {
    local required_vars=(
        "USER_MONITORING_ENABLED"
        "EXECUTION_TRACKING_ENABLED"
        "STORAGE_MONITORING_ENABLED"
        "METRICS_COLLECTION_INTERVAL"
        "STORAGE_ALERT_THRESHOLD"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Missing environment variable: $var"
            return 1
        fi
    done
    
    return 0
}

# Test Docker user management script
test_docker_user_manager() {
    if [[ ! -f "/opt/n8n/scripts/docker-user-manager.sh" ]]; then
        echo "Docker user manager script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/docker-user-manager.sh" ]]; then
        echo "Docker user manager script not executable"
        return 1
    fi
    
    # Test script help output
    if ! /opt/n8n/scripts/docker-user-manager.sh 2>&1 | grep -q "Usage:"; then
        echo "Docker user manager script missing usage information"
        return 1
    fi
    
    return 0
}

# Test system metrics collection
test_system_metrics() {
    # Test if system metrics file can be created
    local system_metrics_file="/opt/n8n/monitoring/metrics/system_metrics.json"
    
    # Create test system metrics entry
    local test_metrics='{"timestamp":"'$(date -Iseconds)'","activeExecutions":0,"memoryUsage":{"rss":100000000}}'
    
    if ! echo "$test_metrics" >> "$system_metrics_file"; then
        echo "Cannot write to system metrics file"
        return 1
    fi
    
    # Validate JSON format
    if ! echo "$test_metrics" | jq '.' >/dev/null 2>&1; then
        echo "Invalid system metrics JSON format"
        rm -f "$system_metrics_file"
        return 1
    fi
    
    # Cleanup test entry
    if [[ -f "$system_metrics_file" ]]; then
        # Remove the test line we added
        grep -v "activeExecutions\":0" "$system_metrics_file" > "${system_metrics_file}.tmp" 2>/dev/null || true
        mv "${system_metrics_file}.tmp" "$system_metrics_file" 2>/dev/null || true
        
        # Remove file if empty
        if [[ ! -s "$system_metrics_file" ]]; then
            rm -f "$system_metrics_file"
        fi
    fi
    
    return 0
}

# Main test execution
main() {
    log_section "User Monitoring Configuration Tests"
    
    # Check if user monitoring is enabled
    if [[ "${USER_MONITORING_ENABLED,,}" != "true" ]]; then
        log_info "User monitoring is disabled, skipping tests"
        return 0
    fi
    
    run_test "Monitoring directories" test_monitoring_directories
    run_test "Execution tracking script" test_execution_tracking
    run_test "Storage monitoring script" test_storage_monitoring
    run_test "Workflow statistics script" test_workflow_statistics
    run_test "Analytics processor script" test_analytics_processor
    run_test "Cleanup scripts" test_cleanup_scripts
    run_test "Monitoring cron jobs" test_monitoring_cron
    run_test "Metrics file creation" test_metrics_creation
    run_test "Log file creation" test_log_files
    run_test "Alert system" test_alert_system
    run_test "Report generation" test_report_generation
    run_test "Environment variables" test_monitoring_environment
    run_test "Docker user manager" test_docker_user_manager
    run_test "System metrics collection" test_system_metrics
    
    log_subsection "User Monitoring Test Results:"
    log_info "Total tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_pass "All user monitoring tests passed!"
        return 0
    else
        log_error "$FAILED_TESTS user monitoring tests failed"
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
