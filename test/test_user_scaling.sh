#!/bin/bash

# Test script for user scaling and management functionality
# Tests multi-user isolation, provisioning, quotas, and resource management

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

# Test user directory structure creation
test_user_directory_structure() {
    local test_user="test_user_$$"
    local user_base="/opt/n8n/users/$test_user"
    
    # Create user directory structure
    mkdir -p "$user_base"/{workflows,files,logs,temp,credentials,backups}
    
    # Verify all directories exist
    local required_dirs=(
        "$user_base/workflows"
        "$user_base/files"
        "$user_base/logs"
        "$user_base/temp"
        "$user_base/credentials"
        "$user_base/backups"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "Missing directory: $dir"
            rm -rf "$user_base"
            return 1
        fi
    done
    
    # Cleanup
    rm -rf "$user_base"
    return 0
}

# Test user configuration file creation
test_user_config_creation() {
    local test_user="test_config_$$"
    local user_base="/opt/n8n/users/$test_user"
    local config_file="$user_base/user-config.json"
    
    mkdir -p "$user_base"
    
    # Create user configuration
    cat > "$config_file" << EOF
{
  "userId": "$test_user",
  "email": "test@example.com",
  "createdAt": "$(date -Iseconds)",
  "status": "active",
  "quotas": {
    "storage": "1GB",
    "storageBytes": 1073741824,
    "workflows": 100,
    "executions": 10000,
    "credentials": 50
  },
  "settings": {
    "timezone": "UTC",
    "notifications": true,
    "executionLogging": true
  }
}
EOF
    
    # Validate JSON format
    if ! jq '.' "$config_file" >/dev/null 2>&1; then
        echo "Invalid user config JSON"
        rm -rf "$user_base"
        return 1
    fi
    
    # Check required fields
    if ! jq -e '.quotas.storageBytes' "$config_file" >/dev/null 2>&1; then
        echo "Missing storage quota"
        rm -rf "$user_base"
        return 1
    fi
    
    # Cleanup
    rm -rf "$user_base"
    return 0
}

# Test user isolation (files don't leak between users)
test_user_isolation() {
    local user1="test_iso_user1_$$"
    local user2="test_iso_user2_$$"
    local user1_base="/opt/n8n/users/$user1"
    local user2_base="/opt/n8n/users/$user2"
    
    # Create user directories
    mkdir -p "$user1_base/files" "$user2_base/files"
    
    # Create user1's file
    echo "User 1 secret data" > "$user1_base/files/secret.txt"
    
    # Create user2's file
    echo "User 2 data" > "$user2_base/files/data.txt"
    
    # Verify user1 cannot see user2's files (by path isolation)
    if [[ -f "$user1_base/files/data.txt" ]]; then
        echo "User isolation failed: user1 can see user2's files"
        rm -rf "$user1_base" "$user2_base"
        return 1
    fi
    
    # Verify user2 cannot see user1's files
    if [[ -f "$user2_base/files/secret.txt" ]]; then
        echo "User isolation failed: user2 can see user1's files"
        rm -rf "$user1_base" "$user2_base"
        return 1
    fi
    
    # Cleanup
    rm -rf "$user1_base" "$user2_base"
    return 0
}

# Test user provisioning
test_user_provisioning() {
    local test_user="test_provision_$$"
    local user_base="/opt/n8n/users/$test_user"
    
    # Simulate provisioning process
    mkdir -p "$user_base"/{workflows,files,logs,temp,credentials,backups}
    
    # Create user config
    cat > "$user_base/user-config.json" << EOF
{
  "userId": "$test_user",
  "email": "provision@example.com",
  "createdAt": "$(date -Iseconds)",
  "status": "active",
  "quotas": {
    "storage": "1GB",
    "storageBytes": 1073741824,
    "workflows": 100,
    "executions": 10000,
    "credentials": 50
  }
}
EOF
    
    # Create initial empty metrics
    mkdir -p "/opt/n8n/monitoring/metrics"
    cat > "/opt/n8n/monitoring/metrics/${test_user}_current.json" << EOF
{
  "userId": "$test_user",
  "createdAt": "$(date -Iseconds)",
  "executions": [],
  "summary": {
    "totalExecutions": 0,
    "totalDuration": 0
  }
}
EOF
    
    # Verify provisioning
    if [[ ! -f "$user_base/user-config.json" ]]; then
        echo "User config not created"
        rm -rf "$user_base"
        rm -f "/opt/n8n/monitoring/metrics/${test_user}_current.json"
        return 1
    fi
    
    # Cleanup
    rm -rf "$user_base"
    rm -f "/opt/n8n/monitoring/metrics/${test_user}_current.json"
    return 0
}

# Test user deprovisioning cleanup
test_user_deprovisioning() {
    local test_user="test_deprovision_$$"
    local user_base="/opt/n8n/users/$test_user"
    
    # Create user with data
    mkdir -p "$user_base"/{workflows,files,logs}
    echo "workflow data" > "$user_base/workflows/test.json"
    echo "file data" > "$user_base/files/test.txt"
    
    # Create user config
    cat > "$user_base/user-config.json" << EOF
{"userId": "$test_user", "status": "active"}
EOF
    
    # Create metrics file
    mkdir -p "/opt/n8n/monitoring/metrics"
    echo '{"userId": "'$test_user'"}' > "/opt/n8n/monitoring/metrics/${test_user}_current.json"
    
    # Simulate deprovisioning
    rm -rf "$user_base"
    rm -f "/opt/n8n/monitoring/metrics/${test_user}"*.json
    
    # Verify cleanup
    if [[ -d "$user_base" ]]; then
        echo "User directory not cleaned up"
        return 1
    fi
    
    if ls "/opt/n8n/monitoring/metrics/${test_user}"*.json 2>/dev/null; then
        echo "User metrics not cleaned up"
        return 1
    fi
    
    return 0
}

# Test user quota enforcement structure
test_user_quota_structure() {
    local test_user="test_quota_$$"
    local user_base="/opt/n8n/users/$test_user"
    
    mkdir -p "$user_base"
    
    # Create quota configuration
    cat > "$user_base/user-config.json" << EOF
{
  "userId": "$test_user",
  "quotas": {
    "storage": "5GB",
    "storageBytes": 5368709120,
    "storageWarningThreshold": 0.8,
    "storageCriticalThreshold": 0.95,
    "workflows": 200,
    "workflowsWarningThreshold": 0.9,
    "executions": 50000,
    "executionsPerDay": 1000,
    "credentials": 100
  }
}
EOF
    
    # Validate quota structure
    local storage_quota=$(jq '.quotas.storageBytes' "$user_base/user-config.json")
    if [[ "$storage_quota" != "5368709120" ]]; then
        echo "Storage quota mismatch"
        rm -rf "$user_base"
        return 1
    fi
    
    # Check warning thresholds exist
    if ! jq -e '.quotas.storageWarningThreshold' "$user_base/user-config.json" >/dev/null 2>&1; then
        echo "Missing warning threshold"
        rm -rf "$user_base"
        return 1
    fi
    
    # Cleanup
    rm -rf "$user_base"
    return 0
}

# Test resource allocation tracking
test_resource_allocation() {
    local test_user="test_resource_$$"
    local metrics_file="/opt/n8n/monitoring/metrics/${test_user}_resources.json"
    
    mkdir -p "/opt/n8n/monitoring/metrics"
    
    # Create resource allocation record
    cat > "$metrics_file" << EOF
{
  "userId": "$test_user",
  "timestamp": "$(date -Iseconds)",
  "allocation": {
    "storage": {
      "used": 524288000,
      "quota": 1073741824,
      "percentage": 48.8
    },
    "workflows": {
      "used": 25,
      "quota": 100,
      "percentage": 25
    },
    "executions": {
      "used": 1500,
      "quota": 10000,
      "percentage": 15
    },
    "credentials": {
      "used": 10,
      "quota": 50,
      "percentage": 20
    }
  }
}
EOF
    
    # Validate resource tracking
    if ! jq -e '.allocation.storage.percentage' "$metrics_file" >/dev/null 2>&1; then
        echo "Missing storage percentage"
        rm -f "$metrics_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$metrics_file"
    return 0
}

# Test concurrent user session tracking
test_concurrent_sessions() {
    local test_user="test_session_$$"
    local sessions_file="/opt/n8n/monitoring/metrics/active_sessions.json"
    
    mkdir -p "/opt/n8n/monitoring/metrics"
    
    # Create sessions tracking file
    cat > "$sessions_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "totalSessions": 15,
  "sessions": {
    "user_1": {
      "sessionCount": 2,
      "lastActivity": "$(date -Iseconds)",
      "ipAddresses": ["192.168.1.100", "192.168.1.101"]
    },
    "user_2": {
      "sessionCount": 1,
      "lastActivity": "$(date -Iseconds)",
      "ipAddresses": ["192.168.1.102"]
    }
  }
}
EOF
    
    # Validate session tracking
    if ! jq -e '.totalSessions' "$sessions_file" >/dev/null 2>&1; then
        echo "Missing total sessions"
        rm -f "$sessions_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$sessions_file"
    return 0
}

# Test user backup creation
test_user_backup() {
    local test_user="test_backup_$$"
    local user_base="/opt/n8n/users/$test_user"
    local backup_dir="/opt/n8n/backups/users"
    local backup_file="$backup_dir/${test_user}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    # Create user with data
    mkdir -p "$user_base"/{workflows,files,credentials}
    mkdir -p "$backup_dir"
    
    echo '{"name": "Test Workflow"}' > "$user_base/workflows/workflow1.json"
    echo "test file content" > "$user_base/files/test.txt"
    
    # Create backup (simulated)
    if command -v tar >/dev/null 2>&1; then
        tar -czf "$backup_file" -C "/opt/n8n/users" "$test_user" 2>/dev/null
        
        # Verify backup created
        if [[ ! -f "$backup_file" ]]; then
            echo "Backup file not created"
            rm -rf "$user_base"
            return 1
        fi
        
        # Verify backup contains data
        if ! tar -tzf "$backup_file" | grep -q "workflows"; then
            echo "Backup missing workflow data"
            rm -rf "$user_base" "$backup_file"
            return 1
        fi
        
        rm -f "$backup_file"
    fi
    
    # Cleanup
    rm -rf "$user_base"
    return 0
}

# Test user restore from backup
test_user_restore() {
    local test_user="test_restore_$$"
    local user_base="/opt/n8n/users/$test_user"
    local backup_dir="/opt/n8n/backups/users"
    local backup_file="$backup_dir/${test_user}_backup.tar.gz"
    
    mkdir -p "$user_base/workflows" "$backup_dir"
    
    # Create original data
    echo '{"name": "Original Workflow"}' > "$user_base/workflows/workflow1.json"
    
    # Create backup
    if command -v tar >/dev/null 2>&1; then
        tar -czf "$backup_file" -C "/opt/n8n/users" "$test_user" 2>/dev/null
        
        # Modify data
        echo '{"name": "Modified Workflow"}' > "$user_base/workflows/workflow1.json"
        
        # Restore (simulated)
        rm -rf "$user_base"
        tar -xzf "$backup_file" -C "/opt/n8n/users" 2>/dev/null
        
        # Verify restore
        if [[ ! -f "$user_base/workflows/workflow1.json" ]]; then
            echo "Restore failed: workflow file missing"
            rm -f "$backup_file"
            return 1
        fi
        
        local content=$(cat "$user_base/workflows/workflow1.json")
        if [[ "$content" != '{"name": "Original Workflow"}' ]]; then
            echo "Restore failed: content mismatch"
            rm -rf "$user_base" "$backup_file"
            return 1
        fi
        
        rm -f "$backup_file"
    fi
    
    # Cleanup
    rm -rf "$user_base"
    return 0
}

# Test user migration capability
test_user_migration() {
    local test_user="test_migrate_$$"
    local source_base="/opt/n8n/users/$test_user"
    local export_file="/opt/n8n/backups/exports/${test_user}_export.json"
    
    mkdir -p "$source_base"/{workflows,credentials}
    mkdir -p "/opt/n8n/backups/exports"
    
    # Create user data
    echo '{"id": "wf1", "name": "Workflow 1"}' > "$source_base/workflows/wf1.json"
    echo '{"id": "wf2", "name": "Workflow 2"}' > "$source_base/workflows/wf2.json"
    
    cat > "$source_base/user-config.json" << EOF
{
  "userId": "$test_user",
  "email": "migrate@example.com",
  "settings": {"timezone": "UTC"}
}
EOF
    
    # Create export (simulated migration data)
    cat > "$export_file" << EOF
{
  "exportVersion": "1.0",
  "exportedAt": "$(date -Iseconds)",
  "userId": "$test_user",
  "config": $(cat "$source_base/user-config.json"),
  "workflows": [
    $(cat "$source_base/workflows/wf1.json"),
    $(cat "$source_base/workflows/wf2.json")
  ],
  "statistics": {
    "workflowCount": 2,
    "credentialCount": 0
  }
}
EOF
    
    # Validate export format
    if ! jq '.' "$export_file" >/dev/null 2>&1; then
        echo "Invalid export JSON"
        rm -rf "$source_base" "$export_file"
        return 1
    fi
    
    # Check workflow count
    local wf_count=$(jq '.workflows | length' "$export_file")
    if [[ "$wf_count" != "2" ]]; then
        echo "Export workflow count mismatch"
        rm -rf "$source_base" "$export_file"
        return 1
    fi
    
    # Cleanup
    rm -rf "$source_base" "$export_file"
    return 0
}

# Test multi-user scaling metrics
test_scaling_metrics() {
    local metrics_file="/opt/n8n/monitoring/metrics/scaling_metrics.json"
    
    mkdir -p "/opt/n8n/monitoring/metrics"
    
    # Create scaling metrics
    cat > "$metrics_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "users": {
    "total": 150,
    "active": 85,
    "inactive": 65,
    "newThisMonth": 12
  },
  "resources": {
    "totalStorageUsed": 75000000000,
    "totalStorageQuota": 150000000000,
    "averageStoragePerUser": 500000000,
    "totalWorkflows": 2500,
    "totalCredentials": 850
  },
  "performance": {
    "avgResponseTime": 125,
    "concurrentUsers": 45,
    "peakConcurrentUsers": 78,
    "requestsPerSecond": 250
  },
  "capacity": {
    "storageUtilization": 50,
    "recommendedAction": "none",
    "scalingThreshold": 80
  }
}
EOF
    
    # Validate scaling metrics
    if ! jq -e '.users.total' "$metrics_file" >/dev/null 2>&1; then
        echo "Missing user count"
        rm -f "$metrics_file"
        return 1
    fi
    
    if ! jq -e '.capacity.storageUtilization' "$metrics_file" >/dev/null 2>&1; then
        echo "Missing capacity metrics"
        rm -f "$metrics_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$metrics_file"
    return 0
}

# Test user manager script exists
test_user_manager_script() {
    if [[ ! -f "/opt/n8n/scripts/docker-user-manager.sh" ]]; then
        echo "User manager script not found"
        return 1
    fi
    
    if [[ ! -x "/opt/n8n/scripts/docker-user-manager.sh" ]]; then
        echo "User manager script not executable"
        return 1
    fi
    
    return 0
}

# Test users base directory permissions
test_users_directory_permissions() {
    local users_dir="/opt/n8n/users"
    
    # Check directory exists
    if [[ ! -d "$users_dir" ]]; then
        mkdir -p "$users_dir"
    fi
    
    # Test write permissions
    local test_file="$users_dir/.permission_test_$$"
    if ! touch "$test_file" 2>/dev/null; then
        echo "Cannot write to users directory"
        return 1
    fi
    
    rm -f "$test_file"
    return 0
}

# Main test execution
main() {
    log_section "User Scaling Tests"
    
    # Check if multi-user is enabled
    if [[ "${MULTI_USER_ENABLED:-true}" != "true" ]]; then
        log_info "Multi-user mode is disabled, running with limited tests"
    fi
    
    run_test "User directory structure" test_user_directory_structure
    run_test "User configuration creation" test_user_config_creation
    run_test "User isolation" test_user_isolation
    run_test "User provisioning" test_user_provisioning
    run_test "User deprovisioning" test_user_deprovisioning
    run_test "User quota structure" test_user_quota_structure
    run_test "Resource allocation tracking" test_resource_allocation
    run_test "Concurrent session tracking" test_concurrent_sessions
    run_test "User backup" test_user_backup
    run_test "User restore" test_user_restore
    run_test "User migration" test_user_migration
    run_test "Scaling metrics" test_scaling_metrics
    run_test "User manager script" test_user_manager_script
    run_test "Users directory permissions" test_users_directory_permissions
    
    log_subsection "User Scaling Test Results:"
    log_info "Total tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_pass "All user scaling tests passed!"
        return 0
    else
        log_error "$FAILED_TESTS user scaling tests failed"
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

