#!/bin/bash
# init.sh - n8n server initialization script
# Part of Milestone 1
# This script updates the Ubuntu server silently and sets up initial environment

# Exit immediately if a command exits with a non-zero status
set -e

# Script directory - ensure we get the project root, not setup subdirectory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# If SCRIPT_DIR ends with /setup, move up one level to project root
if [[ "$SCRIPT_DIR" == */setup ]]; then
    SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
fi
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
source "$SETUP_DIR/general_config.sh"

# Source Docker configuration (Milestone 2)
source "$SETUP_DIR/docker_config.sh"

# Source Nginx configuration (Milestone 3)
source "$SETUP_DIR/nginx_config.sh"

# Source Netdata configuration (Milestone 4)
source "$SETUP_DIR/netdata_config.sh"

# Source SSL renewal configuration (Milestone 5)
source "$SETUP_DIR/ssl_renewal.sh"

# Source dynamic optimization configuration (Milestone 6)
source "$SETUP_DIR/dynamic_optimization.sh"

# Source multi-user configuration (Milestone 7)
source "$SETUP_DIR/multi_user_config.sh"
source "$SETUP_DIR/iframe_embedding_config.sh"
source "$SETUP_DIR/user_monitoring.sh"
source "$SETUP_DIR/cross_server_setup.sh"
source "$SETUP_DIR/user_management_api.sh"

# Source backup configuration (Milestone 8)
source "$SETUP_DIR/backup_config.sh"

# Display init banner with enhanced logging
display_banner() {
    if command -v log_section >/dev/null 2>&1; then
        log_section "n8n Server Initialization"
    else
        echo "================================================================================"
        echo "n8n Server Initialization"
        echo "================================================================================"
    fi
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

# Setup multi-user n8n configuration (Milestone 7)
setup_multiuser_n8n() {
    log_info "Setting up multi-user n8n configuration..."
    
    # Check if multi-user is enabled
    if [[ "${MULTI_USER_ENABLED,,}" != "true" ]]; then
        log_info "Multi-user functionality is disabled (MULTI_USER_ENABLED=false)"
        return 0
    fi
    
    # Configure multi-user isolation and directory structure
    log_info "Configuring multi-user isolation..."
    if ! bash "$SETUP_DIR/multi_user_config.sh"; then
        log_error "Failed to configure multi-user isolation"
        return 1
    fi
    
    # Setup iframe embedding if enabled
    if [[ "${IFRAME_EMBEDDING_ENABLED,,}" == "true" ]]; then
        log_info "Configuring iframe embedding..."
        if ! bash "$SETUP_DIR/iframe_embedding_config.sh"; then
            log_error "Failed to configure iframe embedding"
            return 1
        fi
    else
        log_info "Iframe embedding is disabled"
    fi
    
    # Setup user monitoring if enabled
    if [[ "${USER_MONITORING_ENABLED,,}" == "true" ]]; then
        log_info "Configuring user monitoring..."
        if ! bash "$SETUP_DIR/user_monitoring.sh"; then
            log_error "Failed to configure user monitoring"
            return 1
        fi
    else
        log_info "User monitoring is disabled"
    fi
    
    # Setup cross-server communication if enabled
    if [[ "${API_AUTH_ENABLED,,}" == "true" ]]; then
        log_info "Configuring cross-server communication..."
        if ! bash "$SETUP_DIR/cross_server_setup.sh"; then
            log_error "Failed to configure cross-server communication"
            return 1
        fi
    else
        log_info "Cross-server communication is disabled"
    fi
    
    # Setup user management API if enabled
    if [[ "${USER_API_ENABLED,,}" == "true" ]]; then
        log_info "Configuring user management API..."
        if ! bash "$SETUP_DIR/user_management_api.sh"; then
            log_error "Failed to configure user management API"
            return 1
        fi
    else
        log_info "User management API is disabled"
    fi
    
    log_pass "Multi-user n8n configuration completed successfully"
    return 0
}

# Main function
main() {
    display_banner

    # Set timezone first
    set_timezone
    log_info "Set system timezone to ${SERVER_TIMEZONE:-UTC}"

    # Configure hostname to prevent sudo warnings
    configure_hostname

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
    
    # Install email tools for notifications
    log_info "Installing email tools for system notifications..."
    bash "$SETUP_DIR/install_email_tools.sh" --install
    
    # Set up Docker infrastructure (Milestone 2)
    if command -v log_subsection >/dev/null 2>&1; then
        log_subsection "MILESTONE 2: Docker Infrastructure Setup"
    else
        echo "================================================================================"
        echo "MILESTONE 2: Docker Infrastructure Setup"
        echo "================================================================================"
    fi
    log_info "Note: Docker and Docker Compose will be automatically installed if not present"
    setup_docker_infrastructure
    
    # Set up Nginx infrastructure (Milestone 3)
    echo "================================================================================"
    echo "MILESTONE 3: Nginx Reverse Proxy Setup"
    echo "================================================================================"
    log_info "Note: Nginx will be configured as a secure reverse proxy for n8n"
    setup_nginx_infrastructure
    
    # Set up Netdata monitoring (Milestone 4)
    echo "================================================================================"
    echo "MILESTONE 4: Netdata Monitoring Setup"
    echo "================================================================================"
    log_info "Note: Netdata will be configured for system resource monitoring with secure access"
    setup_netdata_monitoring
    
    # Set up SSL certificate management (Milestone 5)
    echo "================================================================================"
    echo "MILESTONE 5: SSL Certificate Management Setup"
    echo "================================================================================"
    log_info "Note: SSL certificates will be configured for automatic renewal"
    setup_ssl_certificate_management
    
    # Set up dynamic hardware optimization (Milestone 6)
    echo "================================================================================"
    echo "MILESTONE 6: Dynamic Hardware Optimization Setup"
    echo "================================================================================"
    log_info "Note: Dynamic optimization will be configured for automatic hardware-based tuning"
    setup_dynamic_optimization
    
    # Set up multi-user n8n configuration (Milestone 7)
    echo "================================================================================"
    echo "MILESTONE 7: Multi-User n8n Configuration Setup"
    echo "================================================================================"
    log_info "Note: Multi-user functionality with iframe embedding and monitoring will be configured"
    setup_multiuser_n8n
    
    # Set up backup system (Milestone 8)
    echo "================================================================================"
    echo "MILESTONE 8: Backup System Setup"
    echo "================================================================================"
    log_info "Note: Automated backup system with retention policies will be configured"
    if [[ "${BACKUP_ENABLED:-true}" == "true" ]]; then
        configure_backup
    else
        log_info "Backup system is disabled (BACKUP_ENABLED=false)"
    fi
    
    # Print setup summary
    echo "================================================================================"
    echo "SETUP SUMMARY"
    echo "================================================================================"
    log_info "✓ Script permissions: SUCCESS"
    log_info "✓ System update: SUCCESS"
    log_info "✓ Timezone configuration: SUCCESS"
    log_info "✓ Hostname configuration: SUCCESS"
    log_info "✓ Environment loading: SUCCESS"
    log_info "✓ Docker infrastructure: SUCCESS"
    log_info "✓ Docker containers: STARTED"
    log_info "✓ Nginx reverse proxy: SUCCESS"
    log_info "✓ Netdata monitoring: SUCCESS"
    log_info "✓ SSL certificate management: SUCCESS"
    log_info "✓ Dynamic hardware optimization: SUCCESS"
    log_info "✓ Multi-user n8n configuration: SUCCESS"
    log_info "✓ Backup system: SUCCESS"
    echo "================================================================================"
    
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
    
    # Find the project root directory (where init.sh is located)
    local project_root
    if [[ "$SCRIPT_DIR" == */setup ]]; then
        project_root="$(dirname "$SCRIPT_DIR")"
    else
        project_root="$SCRIPT_DIR"
    fi
    
    # Set the explicit path to the test runner in the test directory
    local script_path="$project_root/test/run_tests.sh"
    
    # Debug: show current paths
    log_debug "Current working directory: $(pwd)"
    log_debug "Script directory: $SCRIPT_DIR"
    log_debug "Project root: $project_root"
    log_debug "Looking for test runner at: $script_path"
    
    # Check if the file exists
    if [ ! -f "$script_path" ]; then
        log_error "Test runner not found at: $script_path"
        log_error "Current working directory: $(pwd)"
        log_error "Script directory: $SCRIPT_DIR"
        log_error "Please ensure the test directory exists with run_tests.sh"
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