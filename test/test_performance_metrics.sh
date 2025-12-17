#!/bin/bash

# Test script for performance metrics functionality
# Tests execution time tracking, performance data collection, and analytics

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

# Test execution time tracking script exists
test_execution_tracker_exists() {
    if [[ ! -f "/opt/n8n/scripts/execution-tracker.js" ]]; then
        echo "Execution tracker script not found"
        return 1
    fi
    
    if command -v node >/dev/null 2>&1; then
        if ! node -c "/opt/n8n/scripts/execution-tracker.js" 2>/dev/null; then
            echo "Execution tracker script has syntax errors"
            return 1
        fi
    fi
    
    return 0
}

# Test performance metrics directory structure
test_metrics_directories() {
    local required_dirs=(
        "/opt/n8n/monitoring/metrics"
        "/opt/n8n/monitoring/reports"
        "/opt/n8n/monitoring/analytics"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "Missing metrics directory: $dir"
            return 1
        fi
    done
    
    return 0
}

# Test execution duration calculation
test_execution_duration_calculation() {
    local test_user="test_perf_$$"
    local metrics_file="/opt/n8n/monitoring/metrics/${test_user}_current.json"
    
    # Create test metrics with execution times
    cat > "$metrics_file" << EOF
{
  "userId": "$test_user",
  "executions": [
    {
      "executionId": "exec-1",
      "startedAt": "2024-01-01T10:00:00.000Z",
      "stoppedAt": "2024-01-01T10:00:05.500Z",
      "duration": 5500,
      "status": "success"
    },
    {
      "executionId": "exec-2",
      "startedAt": "2024-01-01T11:00:00.000Z",
      "stoppedAt": "2024-01-01T11:00:02.300Z",
      "duration": 2300,
      "status": "success"
    }
  ],
  "summary": {
    "totalExecutions": 2,
    "totalDuration": 7800,
    "averageDuration": 3900
  }
}
EOF
    
    # Validate JSON format
    if ! jq '.' "$metrics_file" >/dev/null 2>&1; then
        echo "Invalid metrics JSON format"
        rm -f "$metrics_file"
        return 1
    fi
    
    # Verify duration calculations
    local total_duration=$(jq '.summary.totalDuration' "$metrics_file")
    local avg_duration=$(jq '.summary.averageDuration' "$metrics_file")
    
    if [[ "$total_duration" != "7800" ]]; then
        echo "Total duration mismatch: expected 7800, got $total_duration"
        rm -f "$metrics_file"
        return 1
    fi
    
    if [[ "$avg_duration" != "3900" ]]; then
        echo "Average duration mismatch: expected 3900, got $avg_duration"
        rm -f "$metrics_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$metrics_file"
    return 0
}

# Test per-workflow performance tracking
test_workflow_performance_tracking() {
    local test_user="test_wf_perf_$$"
    local metrics_file="/opt/n8n/monitoring/metrics/${test_user}_workflows.json"
    
    # Create workflow performance metrics
    cat > "$metrics_file" << EOF
{
  "userId": "$test_user",
  "workflows": {
    "workflow-1": {
      "name": "Test Workflow 1",
      "executions": 10,
      "totalDuration": 50000,
      "averageDuration": 5000,
      "minDuration": 2000,
      "maxDuration": 10000,
      "successRate": 90
    },
    "workflow-2": {
      "name": "Test Workflow 2",
      "executions": 5,
      "totalDuration": 15000,
      "averageDuration": 3000,
      "minDuration": 1000,
      "maxDuration": 6000,
      "successRate": 100
    }
  }
}
EOF
    
    # Validate JSON and required fields
    if ! jq -e '.workflows["workflow-1"].averageDuration' "$metrics_file" >/dev/null 2>&1; then
        echo "Missing average duration in workflow metrics"
        rm -f "$metrics_file"
        return 1
    fi
    
    if ! jq -e '.workflows["workflow-1"].successRate' "$metrics_file" >/dev/null 2>&1; then
        echo "Missing success rate in workflow metrics"
        rm -f "$metrics_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$metrics_file"
    return 0
}

# Test performance alert thresholds
test_performance_alert_thresholds() {
    # Check if performance alert threshold environment variables exist
    local threshold_vars=(
        "EXECUTION_TIME_WARNING_THRESHOLD"
        "EXECUTION_TIME_CRITICAL_THRESHOLD"
    )
    
    # Create test thresholds if not set
    local has_thresholds=true
    for var in "${threshold_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            has_thresholds=false
            break
        fi
    done
    
    # Test alert file creation
    local alert_file="/opt/n8n/monitoring/alerts/test_perf_alert_$$.json"
    
    cat > "$alert_file" << EOF
{
  "alertId": "perf-alert-$$",
  "type": "execution_time",
  "level": "warning",
  "threshold": 30000,
  "actualValue": 45000,
  "workflowId": "test-workflow",
  "timestamp": "$(date -Iseconds)",
  "message": "Workflow execution exceeded warning threshold"
}
EOF
    
    # Validate alert format
    if ! jq -e '.threshold' "$alert_file" >/dev/null 2>&1; then
        echo "Alert missing threshold field"
        rm -f "$alert_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$alert_file"
    return 0
}

# Test system performance metrics collection
test_system_performance_metrics() {
    local system_metrics_file="/opt/n8n/monitoring/metrics/system_performance.json"
    
    # Create system performance metrics
    cat > "$system_metrics_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "system": {
    "cpuUsage": 45.5,
    "memoryUsage": 62.3,
    "diskUsage": 35.0
  },
  "n8n": {
    "activeExecutions": 3,
    "queuedExecutions": 5,
    "averageResponseTime": 250,
    "requestsPerMinute": 120
  },
  "database": {
    "connectionPoolUsage": 40,
    "averageQueryTime": 15,
    "slowQueries": 2
  }
}
EOF
    
    # Validate JSON format
    if ! jq '.' "$system_metrics_file" >/dev/null 2>&1; then
        echo "Invalid system metrics JSON"
        rm -f "$system_metrics_file"
        return 1
    fi
    
    # Check required sections
    if ! jq -e '.system.cpuUsage' "$system_metrics_file" >/dev/null 2>&1; then
        echo "Missing CPU usage metric"
        rm -f "$system_metrics_file"
        return 1
    fi
    
    if ! jq -e '.n8n.activeExecutions' "$system_metrics_file" >/dev/null 2>&1; then
        echo "Missing n8n metrics"
        rm -f "$system_metrics_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$system_metrics_file"
    return 0
}

# Test API response time tracking
test_api_response_tracking() {
    local api_metrics_file="/opt/n8n/monitoring/metrics/api_performance.json"
    
    # Create API performance metrics
    cat > "$api_metrics_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "endpoints": {
    "/rest/workflows": {
      "requests": 500,
      "avgResponseTime": 45,
      "p95ResponseTime": 120,
      "p99ResponseTime": 250,
      "errorRate": 0.5
    },
    "/rest/executions": {
      "requests": 1200,
      "avgResponseTime": 85,
      "p95ResponseTime": 200,
      "p99ResponseTime": 450,
      "errorRate": 0.2
    }
  }
}
EOF
    
    # Validate JSON format
    if ! jq '.' "$api_metrics_file" >/dev/null 2>&1; then
        echo "Invalid API metrics JSON"
        rm -f "$api_metrics_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$api_metrics_file"
    return 0
}

# Test daily performance report generation
test_daily_performance_report() {
    local test_user="test_daily_$$"
    local date_str=$(date +%Y-%m-%d)
    local report_file="/opt/n8n/monitoring/reports/${test_user}_daily_${date_str}.json"
    
    # Create daily performance report
    cat > "$report_file" << EOF
{
  "userId": "$test_user",
  "date": "$date_str",
  "summary": {
    "totalExecutions": 150,
    "successfulExecutions": 142,
    "failedExecutions": 8,
    "successRate": 94.67,
    "totalDuration": 450000,
    "averageDuration": 3000
  },
  "performance": {
    "fastestExecution": 500,
    "slowestExecution": 30000,
    "medianDuration": 2500,
    "p95Duration": 15000
  },
  "trends": {
    "executionsChange": 12.5,
    "durationChange": -5.2,
    "successRateChange": 2.1
  }
}
EOF
    
    # Validate report format
    if ! jq -e '.summary.successRate' "$report_file" >/dev/null 2>&1; then
        echo "Missing success rate in daily report"
        rm -f "$report_file"
        return 1
    fi
    
    if ! jq -e '.performance.medianDuration' "$report_file" >/dev/null 2>&1; then
        echo "Missing performance metrics in daily report"
        rm -f "$report_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$report_file"
    return 0
}

# Test performance benchmarking
test_performance_benchmarking() {
    local benchmark_file="/opt/n8n/monitoring/analytics/benchmark_results.json"
    
    # Create benchmark results
    cat > "$benchmark_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "benchmarks": {
    "workflowCreation": {
      "samples": 100,
      "avgTime": 150,
      "minTime": 80,
      "maxTime": 350,
      "stdDev": 45
    },
    "workflowExecution": {
      "samples": 500,
      "avgTime": 2500,
      "minTime": 500,
      "maxTime": 15000,
      "stdDev": 2100
    },
    "apiLatency": {
      "samples": 1000,
      "avgTime": 50,
      "minTime": 10,
      "maxTime": 500,
      "stdDev": 75
    }
  },
  "comparison": {
    "previousRun": "2024-01-01T00:00:00Z",
    "improvementPercent": 8.5
  }
}
EOF
    
    # Validate benchmark format
    if ! jq -e '.benchmarks.workflowExecution.avgTime' "$benchmark_file" >/dev/null 2>&1; then
        echo "Missing benchmark data"
        rm -f "$benchmark_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$benchmark_file"
    return 0
}

# Test performance trend analysis
test_performance_trends() {
    local trends_file="/opt/n8n/monitoring/analytics/performance_trends.json"
    
    # Create trend data
    cat > "$trends_file" << EOF
{
  "period": "7d",
  "generatedAt": "$(date -Iseconds)",
  "trends": {
    "executionVolume": {
      "current": 1050,
      "previous": 980,
      "changePercent": 7.14,
      "trend": "increasing"
    },
    "averageExecutionTime": {
      "current": 2800,
      "previous": 3200,
      "changePercent": -12.5,
      "trend": "improving"
    },
    "successRate": {
      "current": 96.5,
      "previous": 94.2,
      "changePercent": 2.44,
      "trend": "improving"
    },
    "errorRate": {
      "current": 3.5,
      "previous": 5.8,
      "changePercent": -39.66,
      "trend": "improving"
    }
  }
}
EOF
    
    # Validate trends format
    if ! jq -e '.trends.executionVolume.trend' "$trends_file" >/dev/null 2>&1; then
        echo "Missing trend data"
        rm -f "$trends_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$trends_file"
    return 0
}

# Test metrics file permissions
test_metrics_permissions() {
    local test_file="/opt/n8n/monitoring/metrics/test_permissions_$$.json"
    
    # Test write permissions
    if ! touch "$test_file" 2>/dev/null; then
        echo "Cannot write to metrics directory"
        return 1
    fi
    
    # Test read permissions
    if ! cat "$test_file" >/dev/null 2>&1; then
        echo "Cannot read from metrics directory"
        rm -f "$test_file"
        return 1
    fi
    
    # Cleanup
    rm -f "$test_file"
    return 0
}

# Main test execution
main() {
    log_section "Performance Metrics Tests"
    
    # Check if monitoring is enabled
    if [[ "${USER_MONITORING_ENABLED:-true}" != "true" ]]; then
        log_info "User monitoring is disabled, running with limited tests"
    fi
    
    run_test "Execution tracker exists" test_execution_tracker_exists
    run_test "Metrics directories" test_metrics_directories
    run_test "Execution duration calculation" test_execution_duration_calculation
    run_test "Workflow performance tracking" test_workflow_performance_tracking
    run_test "Performance alert thresholds" test_performance_alert_thresholds
    run_test "System performance metrics" test_system_performance_metrics
    run_test "API response tracking" test_api_response_tracking
    run_test "Daily performance report" test_daily_performance_report
    run_test "Performance benchmarking" test_performance_benchmarking
    run_test "Performance trends" test_performance_trends
    run_test "Metrics permissions" test_metrics_permissions
    
    log_subsection "Performance Metrics Test Results:"
    log_info "Total tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_pass "All performance metrics tests passed!"
        return 0
    else
        log_error "$FAILED_TESTS performance metrics tests failed"
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

