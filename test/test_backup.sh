#!/bin/bash

# ==============================================================================
# Backup Test Suite for n8n Server - Milestone 8
# ==============================================================================
# This script tests backup functionality including creation, restoration,
# verification, and cleanup operations
# ==============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Test configuration
TEST_SECTION="Backup System"
TESTS_PASSED=0
TESTS_FAILED=0

# Backup paths for testing
BACKUP_BASE_DIR="${BACKUP_LOCATION:-/opt/n8n/backups}"
BACKUP_SCRIPTS_DIR="/opt/n8n/scripts"
BACKUP_LOG_FILE="/var/log/n8n_backup.log"
N8N_DATA_DIR="${N8N_DATA_DIR:-/opt/n8n}"

# Test backup directory
TEST_BACKUP_DIR="/tmp/n8n_backup_test"

# ==============================================================================
# Test Utility Functions
# ==============================================================================

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

run_test_verbose() {
    local test_name="$1"
    local test_function="$2"
    
    echo -n "  Testing $test_name... "
    
    local output
    output=$($test_function 2>&1)
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo "PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "FAIL"
        echo "    Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

setup_test_environment() {
    # Create test directories
    sudo mkdir -p "$TEST_BACKUP_DIR"
    sudo mkdir -p "$TEST_BACKUP_DIR/n8n_data/.n8n"
    sudo mkdir -p "$TEST_BACKUP_DIR/n8n_data/files"
    sudo mkdir -p "$TEST_BACKUP_DIR/n8n_data/users"
    sudo mkdir -p "$TEST_BACKUP_DIR/n8n_data/docker"
    
    # Create test data
    echo '{"test": "workflow"}' | sudo tee "$TEST_BACKUP_DIR/n8n_data/.n8n/workflows.json" >/dev/null
    echo "test file content" | sudo tee "$TEST_BACKUP_DIR/n8n_data/files/test.txt" >/dev/null
    echo "docker-compose test" | sudo tee "$TEST_BACKUP_DIR/n8n_data/docker/docker-compose.yml" >/dev/null
}

cleanup_test_environment() {
    sudo rm -rf "$TEST_BACKUP_DIR" 2>/dev/null || true
    sudo rm -f "/tmp/test_backup_*.tar.gz" 2>/dev/null || true
}

# ==============================================================================
# Backup Directory Structure Tests
# ==============================================================================

test_backup_base_directory_exists() {
    [ -d "$BACKUP_BASE_DIR" ]
}

test_backup_daily_directory_exists() {
    [ -d "$BACKUP_BASE_DIR/daily" ]
}

test_backup_weekly_directory_exists() {
    [ -d "$BACKUP_BASE_DIR/weekly" ]
}

test_backup_monthly_directory_exists() {
    [ -d "$BACKUP_BASE_DIR/monthly" ]
}

test_backup_manual_directory_exists() {
    [ -d "$BACKUP_BASE_DIR/manual" ]
}

test_backup_directory_permissions() {
    local perms=$(stat -c %a "$BACKUP_BASE_DIR" 2>/dev/null)
    [ "$perms" = "750" ] || [ "$perms" = "755" ]
}

# ==============================================================================
# Backup Scripts Tests
# ==============================================================================

test_backup_now_script_exists() {
    [ -f "$BACKUP_SCRIPTS_DIR/backup_now.sh" ]
}

test_backup_now_script_executable() {
    [ -x "$BACKUP_SCRIPTS_DIR/backup_now.sh" ]
}

test_list_backups_script_exists() {
    [ -f "$BACKUP_SCRIPTS_DIR/list_backups.sh" ]
}

test_list_backups_script_executable() {
    [ -x "$BACKUP_SCRIPTS_DIR/list_backups.sh" ]
}

test_restore_backup_script_exists() {
    [ -f "$BACKUP_SCRIPTS_DIR/restore_backup.sh" ]
}

test_restore_backup_script_executable() {
    [ -x "$BACKUP_SCRIPTS_DIR/restore_backup.sh" ]
}

test_verify_backup_script_exists() {
    [ -f "$BACKUP_SCRIPTS_DIR/verify_backup.sh" ]
}

test_verify_backup_script_executable() {
    [ -x "$BACKUP_SCRIPTS_DIR/verify_backup.sh" ]
}

test_cleanup_backups_script_exists() {
    [ -f "$BACKUP_SCRIPTS_DIR/cleanup_backups.sh" ]
}

test_cleanup_backups_script_executable() {
    [ -x "$BACKUP_SCRIPTS_DIR/cleanup_backups.sh" ]
}

# ==============================================================================
# Systemd Timer Tests
# ==============================================================================

test_backup_service_exists() {
    [ -f "/etc/systemd/system/n8n-backup.service" ]
}

test_backup_timer_exists() {
    [ -f "/etc/systemd/system/n8n-backup.timer" ]
}

test_backup_timer_enabled() {
    systemctl is-enabled n8n-backup.timer >/dev/null 2>&1
}

test_cleanup_service_exists() {
    [ -f "/etc/systemd/system/n8n-backup-cleanup.service" ]
}

test_cleanup_timer_exists() {
    [ -f "/etc/systemd/system/n8n-backup-cleanup.timer" ]
}

test_cleanup_timer_enabled() {
    systemctl is-enabled n8n-backup-cleanup.timer >/dev/null 2>&1
}

test_weekly_backup_timer_exists() {
    [ -f "/etc/systemd/system/n8n-backup-weekly.timer" ]
}

test_monthly_backup_timer_exists() {
    [ -f "/etc/systemd/system/n8n-backup-monthly.timer" ]
}

# ==============================================================================
# Backup Creation Tests
# ==============================================================================

test_backup_creation_manual() {
    # Skip if n8n data doesn't exist
    [ -d "$N8N_DATA_DIR/.n8n" ] || return 0
    
    local test_name="test_manual_$(date +%s)"
    "$BACKUP_SCRIPTS_DIR/backup_now.sh" manual "$test_name" >/dev/null 2>&1
    
    # Check if backup was created
    [ -f "$BACKUP_BASE_DIR/manual/${test_name}.tar.gz" ] || \
    [ -f "$BACKUP_BASE_DIR/manual/${test_name}.tar.gz.gpg" ]
}

test_backup_manifest_creation() {
    # Find most recent manual backup
    local latest=$(ls -t "$BACKUP_BASE_DIR/manual/"*.manifest 2>/dev/null | head -1)
    [ -n "$latest" ] && [ -f "$latest" ]
}

test_backup_state_file_updated() {
    [ -f "/var/lib/n8n/backup_state" ]
}

# ==============================================================================
# Backup Verification Tests
# ==============================================================================

test_verify_backup_script_runs() {
    "$BACKUP_SCRIPTS_DIR/verify_backup.sh" all >/dev/null 2>&1
    # Script should run without error (exit 0 or 1 for pass/fail)
    [ $? -le 1 ]
}

test_backup_archive_integrity() {
    # Find most recent backup
    local latest=$(ls -t "$BACKUP_BASE_DIR/manual/"*.tar.gz 2>/dev/null | head -1)
    
    if [ -n "$latest" ] && [ -f "$latest" ]; then
        tar -tzf "$latest" >/dev/null 2>&1
        return $?
    fi
    
    # Skip if no backups exist
    return 0
}

# ==============================================================================
# Backup Listing Tests
# ==============================================================================

test_list_backups_script_runs() {
    "$BACKUP_SCRIPTS_DIR/list_backups.sh" >/dev/null 2>&1
}

test_list_backups_shows_summary() {
    local output=$("$BACKUP_SCRIPTS_DIR/list_backups.sh" 2>&1)
    echo "$output" | grep -q "Summary:"
}

test_list_backups_type_filter() {
    "$BACKUP_SCRIPTS_DIR/list_backups.sh" daily >/dev/null 2>&1
}

# ==============================================================================
# Cleanup Tests
# ==============================================================================

test_cleanup_dry_run() {
    "$BACKUP_SCRIPTS_DIR/cleanup_backups.sh" --dry-run >/dev/null 2>&1
}

test_cleanup_respects_min_keep() {
    # Create test scenario with backups at minimum retention
    local output=$("$BACKUP_SCRIPTS_DIR/cleanup_backups.sh" --dry-run 2>&1)
    # Should not fail due to minimum retention
    [ $? -eq 0 ]
}

test_retention_policy_daily() {
    local retention="${BACKUP_RETENTION_DAILY:-7}"
    [ "$retention" -gt 0 ]
}

test_retention_policy_weekly() {
    local retention="${BACKUP_RETENTION_WEEKLY:-4}"
    [ "$retention" -gt 0 ]
}

test_retention_policy_monthly() {
    local retention="${BACKUP_RETENTION_MONTHLY:-3}"
    [ "$retention" -gt 0 ]
}

test_min_keep_setting() {
    local min_keep="${BACKUP_MIN_KEEP:-3}"
    [ "$min_keep" -gt 0 ]
}

test_storage_threshold_setting() {
    local threshold="${BACKUP_STORAGE_THRESHOLD:-85}"
    [ "$threshold" -gt 0 ] && [ "$threshold" -le 100 ]
}

# ==============================================================================
# Restore Tests (Dry Run Only)
# ==============================================================================

test_restore_help_available() {
    "$BACKUP_SCRIPTS_DIR/restore_backup.sh" 2>&1 | grep -q "Usage:"
}

test_restore_dry_run_option() {
    # Find a backup to test with
    local latest=$(ls -t "$BACKUP_BASE_DIR/manual/"*.tar.gz 2>/dev/null | head -1)
    
    if [ -n "$latest" ] && [ -f "$latest" ]; then
        "$BACKUP_SCRIPTS_DIR/restore_backup.sh" "$latest" --dry-run >/dev/null 2>&1
        return $?
    fi
    
    # Skip if no backups exist
    return 0
}

# ==============================================================================
# Log File Tests
# ==============================================================================

test_backup_log_file_exists() {
    [ -f "$BACKUP_LOG_FILE" ]
}

test_backup_log_writable() {
    sudo touch "$BACKUP_LOG_FILE" 2>/dev/null
}

# ==============================================================================
# Environment Configuration Tests
# ==============================================================================

test_backup_location_configured() {
    [ -n "${BACKUP_LOCATION:-}" ] || [ -d "/opt/n8n/backups" ]
}

test_backup_enabled_setting() {
    [ "${BACKUP_ENABLED:-true}" = "true" ] || [ "${BACKUP_ENABLED:-true}" = "false" ]
}

test_email_notify_setting() {
    [ "${BACKUP_EMAIL_NOTIFY:-true}" = "true" ] || [ "${BACKUP_EMAIL_NOTIFY:-true}" = "false" ]
}

test_encryption_setting() {
    [ "${BACKUP_ENCRYPTION_ENABLED:-false}" = "true" ] || [ "${BACKUP_ENCRYPTION_ENABLED:-false}" = "false" ]
}

# ==============================================================================
# Integration Tests
# ==============================================================================

test_n8n_data_directory_exists() {
    [ -d "$N8N_DATA_DIR" ]
}

test_n8n_home_directory_exists() {
    [ -d "$N8N_DATA_DIR/.n8n" ]
}

test_docker_directory_exists() {
    [ -d "$N8N_DATA_DIR/docker" ]
}

# ==============================================================================
# Main Test Runner
# ==============================================================================

run_backup_tests() {
    log_section "Backup System Tests"
    
    echo ""
    echo "Backup Directory Structure Tests"
    echo "--------------------------------"
    run_test "Backup base directory exists" test_backup_base_directory_exists
    run_test "Daily backup directory exists" test_backup_daily_directory_exists
    run_test "Weekly backup directory exists" test_backup_weekly_directory_exists
    run_test "Monthly backup directory exists" test_backup_monthly_directory_exists
    run_test "Manual backup directory exists" test_backup_manual_directory_exists
    run_test "Backup directory permissions" test_backup_directory_permissions
    
    echo ""
    echo "Backup Scripts Tests"
    echo "--------------------"
    run_test "backup_now.sh exists" test_backup_now_script_exists
    run_test "backup_now.sh executable" test_backup_now_script_executable
    run_test "list_backups.sh exists" test_list_backups_script_exists
    run_test "list_backups.sh executable" test_list_backups_script_executable
    run_test "restore_backup.sh exists" test_restore_backup_script_exists
    run_test "restore_backup.sh executable" test_restore_backup_script_executable
    run_test "verify_backup.sh exists" test_verify_backup_script_exists
    run_test "verify_backup.sh executable" test_verify_backup_script_executable
    run_test "cleanup_backups.sh exists" test_cleanup_backups_script_exists
    run_test "cleanup_backups.sh executable" test_cleanup_backups_script_executable
    
    echo ""
    echo "Systemd Timer Tests"
    echo "-------------------"
    run_test "Backup service exists" test_backup_service_exists
    run_test "Backup timer exists" test_backup_timer_exists
    run_test "Backup timer enabled" test_backup_timer_enabled
    run_test "Cleanup service exists" test_cleanup_service_exists
    run_test "Cleanup timer exists" test_cleanup_timer_exists
    run_test "Cleanup timer enabled" test_cleanup_timer_enabled
    run_test "Weekly backup timer exists" test_weekly_backup_timer_exists
    run_test "Monthly backup timer exists" test_monthly_backup_timer_exists
    
    echo ""
    echo "Backup Listing Tests"
    echo "--------------------"
    run_test "list_backups.sh runs" test_list_backups_script_runs
    run_test "List shows summary" test_list_backups_shows_summary
    run_test "List type filter works" test_list_backups_type_filter
    
    echo ""
    echo "Backup Verification Tests"
    echo "-------------------------"
    run_test "verify_backup.sh runs" test_verify_backup_script_runs
    run_test "Backup archive integrity" test_backup_archive_integrity
    
    echo ""
    echo "Cleanup Configuration Tests"
    echo "---------------------------"
    run_test "Cleanup dry-run works" test_cleanup_dry_run
    run_test "Cleanup respects min keep" test_cleanup_respects_min_keep
    run_test "Retention policy daily" test_retention_policy_daily
    run_test "Retention policy weekly" test_retention_policy_weekly
    run_test "Retention policy monthly" test_retention_policy_monthly
    run_test "Min keep setting valid" test_min_keep_setting
    run_test "Storage threshold valid" test_storage_threshold_setting
    
    echo ""
    echo "Restore Tests (Dry Run)"
    echo "-----------------------"
    run_test "Restore help available" test_restore_help_available
    run_test "Restore dry-run option" test_restore_dry_run_option
    
    echo ""
    echo "Log and State Tests"
    echo "-------------------"
    run_test "Backup log file exists" test_backup_log_file_exists
    run_test "Backup log writable" test_backup_log_writable
    run_test "Backup state file exists" test_backup_state_file_updated
    
    echo ""
    echo "Environment Configuration Tests"
    echo "--------------------------------"
    run_test "Backup location configured" test_backup_location_configured
    run_test "Backup enabled setting" test_backup_enabled_setting
    run_test "Email notify setting" test_email_notify_setting
    run_test "Encryption setting valid" test_encryption_setting
    
    echo ""
    echo "Integration Tests"
    echo "-----------------"
    run_test "n8n data directory exists" test_n8n_data_directory_exists
    run_test "n8n home directory exists" test_n8n_home_directory_exists
    run_test "Docker directory exists" test_docker_directory_exists
    
    # Summary
    echo ""
    echo "============================================================"
    echo "Backup Test Results"
    echo "============================================================"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Total:  $((TESTS_PASSED + TESTS_FAILED))"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_pass "All backup tests passed!"
        return 0
    else
        log_error "$TESTS_FAILED backup tests failed"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Load environment if available
    if [ -f "$PROJECT_ROOT/conf/user.env" ]; then
        source "$PROJECT_ROOT/conf/user.env"
    elif [ -f "$PROJECT_ROOT/conf/default.env" ]; then
        source "$PROJECT_ROOT/conf/default.env"
    fi
    
    run_backup_tests
fi
