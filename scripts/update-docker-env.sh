#!/bin/bash

# =============================================================================
# Update Docker Environment Script
# =============================================================================
# This script regenerates the Docker .env file from current configuration
# Run this after updating user.env or default.env
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source required libraries
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"
source "$PROJECT_ROOT/setup/docker_config.sh"

# =============================================================================
# Main Function
# =============================================================================

main() {
    log_info "==========================================="
    log_info "n8n Docker Environment Update"
    log_info "==========================================="
    
    # Check if Docker infrastructure exists
    if [[ ! -d "/opt/n8n/docker" ]]; then
        log_error "Docker infrastructure not found!"
        log_error "Please run the main setup first: sudo ./init.sh"
        exit 1
    fi
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        log_error "Usage: sudo $0"
        exit 1
    fi
    
    # Show current configuration
    log_info "Current configuration files:"
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        log_info "  ✓ user.env found - will be used"
    else
        log_info "  ✗ user.env not found - using defaults only"
        log_info "  Create user.env from template: cp conf/user.env.template conf/user.env"
    fi
    
    if [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        log_info "  ✓ default.env found"
    else
        log_error "  ✗ default.env missing - cannot continue"
        exit 1
    fi
    
    echo
    log_info "Regenerating Docker environment file..."
    
    # Regenerate the environment file
    if regenerate_environment_file; then
        log_info "==========================================="
        log_info "Docker environment updated successfully!"
        log_info "==========================================="
        
        log_info "Next steps:"
        log_info "1. Review generated file: /opt/n8n/docker/.env"
        log_info "2. Restart n8n services: /opt/n8n/scripts/service.sh restart"
        log_info "3. Check status: /opt/n8n/scripts/service.sh status"
        
    else
        log_error "Failed to update Docker environment"
        exit 1
    fi
}

# Run main function
main "$@" 