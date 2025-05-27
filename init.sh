#!/bin/bash
# init.sh - n8n server initialization script
# Part of Milestone 1
# This script updates the Ubuntu server silently and sets up initial environment

# Exit immediately if a command exits with a non-zero status
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Setup directory
SETUP_DIR="$SCRIPT_DIR/setup"

# Source logger
source "$SCRIPT_DIR/lib/logger.sh"

# Load default environment variables
source "$SCRIPT_DIR/conf/default.env"

# Source utilities
source "$SCRIPT_DIR/lib/utilities.sh"

# Source general configuration
source "$SCRIPT_DIR/setup/general_config.sh"

# Display init banner
display_banner() {
    echo "-----------------------------------------------"
    echo "n8n Server Initialization"
    echo "-----------------------------------------------"
    log_info "Starting initialization process"
}

# Make scripts executable
make_scripts_executable() {
    log_info "Making scripts executable..."
    
    # Make scripts in lib directory executable
    if [ -d "$SCRIPT_DIR/lib" ]; then
        chmod +x "$SCRIPT_DIR/lib"/*.sh 2>/dev/null || true
        log_debug "Made lib scripts executable"
    fi
    
    # Make scripts in setup directory executable
    if [ -d "$SCRIPT_DIR/setup" ]; then
        chmod +x "$SCRIPT_DIR/setup"/*.sh 2>/dev/null || true
        log_debug "Made setup scripts executable"
    fi
    
    # Make scripts in test directory executable
    if [ -d "$SCRIPT_DIR/test" ]; then
        chmod +x "$SCRIPT_DIR/test"/*.sh 2>/dev/null || true
        log_debug "Made test scripts executable"
    fi
    
    log_info "Scripts made executable successfully"
}

# Main function
main() {
    display_banner

    # Make all scripts executable first
    make_scripts_executable

    # Set timezone first
    set_timezone
    log_info "Set system timezone to ${SERVER_TIMEZONE:-UTC}"
    
    # Load user environment variables if they exist (overrides defaults)
    if [ -f "$SCRIPT_DIR/conf/user.env" ]; then
        log_info "Loading user environment variables from conf/user.env"
        source "$SCRIPT_DIR/conf/user.env"
    else
        log_info "No user.env file found. Use default settings"
        log_info "You can create user.env by copying conf/user.env.template and modifying it"
    fi

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    log_debug "Log file: $LOG_FILE"
    
    # Update system packages
    update_system
    
    # Print setup summary
    log_info "-----------------------------------------------"
    log_info "SETUP SUMMARY"
    log_info "-----------------------------------------------"
    log_info "✓ Script permissions: SUCCESS"
    log_info "✓ System update: SUCCESS"
    log_info "✓ Timezone configuration: SUCCESS"
    log_info "✓ Environment loading: SUCCESS"
    log_info "-----------------------------------------------"
    
    log_info "Initialization COMPLETE"
    echo ""
    
    # Run tests if enabled
    if [ "${RUN_TESTS:-true}" = true ]; then
        run_tests
    else
        log_info "Tests skipped (RUN_TESTS is set to false)"
    fi
    
    if [ "$LOG_LEVEL" = "DEBUG" ]; then
        log_debug "For detailed logs, check: $LOG_FILE"
    fi
}

# Run tests after setup
run_tests() {
    log_info "Running test suite..."
    # Flush stdout to ensure immediate display
    sync
    
    # Set the explicit path to the test runner in the test directory
    local script_path="$SCRIPT_DIR/test/run_tests.sh"
    
    # Check if the file exists
    if [ ! -f "$script_path" ]; then
        log_error "Test runner not found at: $script_path"
        return 1
    fi
    
    log_info "Found test runner at: $script_path"
    
    # Run the tests with proper terminal handling
    log_info "Executing test runner: $script_path"
    
    # Always use bash explicitly to avoid permission issues
    bash "$script_path"
    local exit_code=$?
    
    # Ensure final logs are displayed
    sync
    
    # Don't print "Tests executed successfully" here as it's already printed by run_tests.sh
    if [ $exit_code -ne 0 ]; then
        log_warn "Some tests failed with exit code $exit_code. Please check the logs for details."
    fi
    
    # Final flush of output
    sync
    return $exit_code
}

# Execute main function
main "$@" 