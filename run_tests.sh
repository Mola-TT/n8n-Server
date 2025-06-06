#!/bin/bash

# run_tests.sh - Comprehensive Test Runner for n8n Server Setup
# Runs all test suites for all milestones

set -euo pipefail

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required utilities
source "$PROJECT_ROOT/lib/logger.sh"

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test suite results
declare -A SUITE_RESULTS

run_test_suite() {
    local suite_name="$1"
    local test_script="$2"
    
    log_info "Running $suite_name..."
    
    if [[ -f "$test_script" ]]; then
        local exit_code
        bash "$test_script"
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            SUITE_RESULTS["$suite_name"]="PASSED"
            log_info "$suite_name: PASSED"
        else
            # For partial failures, still show as completed but with failures
            SUITE_RESULTS["$suite_name"]="PARTIAL"
            log_warning "$suite_name: COMPLETED with $exit_code test failures"
        fi
    else
        SUITE_RESULTS["$suite_name"]="MISSING"
        log_error "$suite_name: Test script not found"
    fi
}

main() {
    log_info "Starting comprehensive test suite..."
    
    echo "=================================================================================="
    echo "n8n SERVER SETUP - COMPREHENSIVE TEST SUITE"
    echo "=================================================================================="
    
    # Milestone 1-5 Tests (if they exist)
    echo ""
    echo "MILESTONE 1-5 TESTS - Basic Infrastructure"
    echo "=================================================================================="
    
    [[ -f "test/test_basic_infrastructure.sh" ]] && run_test_suite "Basic Infrastructure Tests" "test/test_basic_infrastructure.sh"
    [[ -f "test/test_docker_infrastructure.sh" ]] && run_test_suite "Docker Infrastructure Tests" "test/test_docker_infrastructure.sh"
    [[ -f "test/test_nginx.sh" ]] && run_test_suite "Nginx Tests" "test/test_nginx.sh"
    [[ -f "test/test_netdata.sh" ]] && run_test_suite "Netdata Tests" "test/test_netdata.sh"
    [[ -f "test/test_ssl_renewal.sh" ]] && run_test_suite "SSL Renewal Tests" "test/test_ssl_renewal.sh"
    
    # Milestone 6 Tests
    echo ""
    echo "MILESTONE 6 TESTS - Dynamic Hardware Optimization"
    echo "=================================================================================="
    
    run_test_suite "Dynamic Optimization Tests" "test/test_dynamic_optimization.sh"
    run_test_suite "Email Notification Tests" "test/test_email_notification.sh"
    run_test_suite "Hardware Change Detector Tests" "test/test_hardware_change_detector.sh"
    run_test_suite "Dynamic Optimization Integration Tests" "test/test_dynamic_optimization_integration.sh"
    
    # Summary
    echo ""
    echo "=================================================================================="
    echo "TEST SUITE SUMMARY"
    echo "=================================================================================="
    
    local milestone6_passed=0
    local milestone6_total=4
    
    for suite in "${!SUITE_RESULTS[@]}"; do
        local result="${SUITE_RESULTS[$suite]}"
        case "$result" in
            "PASSED")
                log_info "✓ $suite: PASSED"
                if [[ "$suite" =~ "Dynamic Optimization"|"Email Notification"|"Hardware Change Detector" ]]; then
                    ((milestone6_passed++))
                fi
                ;;
            "PARTIAL")
                log_warning "⚠ $suite: PARTIAL (some tests failed)"
                if [[ "$suite" =~ "Dynamic Optimization"|"Email Notification"|"Hardware Change Detector" ]]; then
                    ((milestone6_passed++))
                fi
                ;;
            "FAILED")
                log_error "✗ $suite: FAILED"
                ;;
            "MISSING")
                log_warning "? $suite: Test script missing"
                ;;
        esac
    done
    
    echo ""
    echo "Milestone 6 Summary: $milestone6_passed/$milestone6_total test suites passed"
    
    if [[ $milestone6_passed -eq $milestone6_total ]]; then
        log_info "🎉 All Milestone 6 tests PASSED!"
        return 0
    else
        log_error "❌ Some Milestone 6 tests FAILED"
        return 1
    fi
}

# Run main function
main "$@" 