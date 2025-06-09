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

# Load user environment variables if they exist (overrides defaults)
if [ -f "$SCRIPT_DIR/conf/user.env" ]; then
    source "$SCRIPT_DIR/conf/user.env"
fi

# Source utilities
source "$SCRIPT_DIR/lib/utilities.sh"

# Make scripts executable BEFORE sourcing them
make_scripts_executable_early() {
    # Make scripts in lib directory executable
    if [ -d "$SCRIPT_DIR/lib" ]; then
        chmod +x "$SCRIPT_DIR/lib"/*.sh 2>/dev/null || true
    fi
    
    # Make scripts in setup directory executable
    if [ -d "$SCRIPT_DIR/setup" ]; then
        chmod +x "$SCRIPT_DIR/setup"/*.sh 2>/dev/null || true
    fi
    
    # Make scripts in test directory executable
    if [ -d "$SCRIPT_DIR/test" ]; then
        chmod +x "$SCRIPT_DIR/test"/*.sh 2>/dev/null || true
    fi
}

# Make scripts executable first
make_scripts_executable_early

# Source general configuration
source "$SCRIPT_DIR/setup/general_config.sh"

# Source Docker configuration (Milestone 2)
source "$SCRIPT_DIR/setup/docker_config.sh"

# Source Nginx configuration (Milestone 3)
source "$SCRIPT_DIR/setup/nginx_config.sh"

# Source Netdata configuration (Milestone 4)
source "$SCRIPT_DIR/setup/netdata_config.sh"

# Source SSL renewal configuration (Milestone 5)
source "$SCRIPT_DIR/setup/ssl_renewal.sh"

# Source dynamic optimization configuration (Milestone 6)
source "$SCRIPT_DIR/setup/dynamic_optimization.sh"

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

    # Set timezone first
    set_timezone
    log_info "Set system timezone to ${SERVER_TIMEZONE:-UTC}"

    # Make all scripts executable first
    make_scripts_executable

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    log_debug "Log file: $LOG_FILE"
    
    # Update system packages
    update_system
    
    # Set up Docker infrastructure (Milestone 2)
    echo "-----------------------------------------------"
    echo "MILESTONE 2: Docker Infrastructure Setup"
    echo "-----------------------------------------------"
    log_info "Note: Docker and Docker Compose will be automatically installed if not present"
    setup_docker_infrastructure
    
    # Set up Nginx infrastructure (Milestone 3)
    echo "-----------------------------------------------"
    echo "MILESTONE 3: Nginx Reverse Proxy Setup"
    echo "-----------------------------------------------"
    log_info "Note: Nginx will be configured as a secure reverse proxy for n8n"
    setup_nginx_infrastructure
    
    # Set up Netdata monitoring (Milestone 4)
    echo "-----------------------------------------------"
    echo "MILESTONE 4: Netdata Monitoring Setup"
    echo "-----------------------------------------------"
    log_info "Note: Netdata will be configured for system resource monitoring with secure access"
    setup_netdata_monitoring
    
    # Set up SSL certificate management (Milestone 5)
    echo "-----------------------------------------------"
    echo "MILESTONE 5: SSL Certificate Management Setup"
    echo "-----------------------------------------------"
    log_info "Note: SSL certificates will be configured for automatic renewal"
    setup_ssl_certificate_management
    
    # Set up dynamic hardware optimization (Milestone 6)
    echo "-----------------------------------------------"
    echo "MILESTONE 6: Dynamic Hardware Optimization Setup"
    echo "-----------------------------------------------"
    log_info "Note: Dynamic optimization will be configured for automatic hardware-based tuning"
    setup_dynamic_optimization
    
    # Print setup summary
    echo "-----------------------------------------------"
    echo "SETUP SUMMARY"
    echo "-----------------------------------------------"
    log_info "✓ Script permissions: SUCCESS"
    log_info "✓ System update: SUCCESS"
    log_info "✓ Timezone configuration: SUCCESS"
    log_info "✓ Environment loading: SUCCESS"
    log_info "✓ Docker infrastructure: SUCCESS"
    log_info "✓ Docker containers: STARTED"
    log_info "✓ Nginx reverse proxy: SUCCESS"
    log_info "✓ Netdata monitoring: SUCCESS"
    log_info "✓ SSL certificate management: SUCCESS"
    log_info "✓ Dynamic hardware optimization: SUCCESS"
    echo "-----------------------------------------------"
    
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