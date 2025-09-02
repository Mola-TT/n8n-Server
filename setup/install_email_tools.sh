#!/bin/bash

# install_email_tools.sh - Install and configure email tools for n8n server
# This script installs msmtp and configures it for sending email notifications

set -euo pipefail

# Get script directory
PROJECT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

# Source logging utilities
if [[ -f "$PROJECT_ROOT/lib/logger.sh" ]]; then
    source "$PROJECT_ROOT/lib/logger.sh"
else
    log_info() { echo "INFO: $1"; }
    log_warn() { echo "WARN: $1"; }
    log_error() { echo "ERROR: $1"; }
fi

# Load environment configuration
load_environment_config() {
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        source "$PROJECT_ROOT/conf/user.env"
        log_info "Loaded environment configuration from user.env"
    elif [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        source "$PROJECT_ROOT/conf/default.env"
        log_info "Loaded environment configuration from default.env"
    else
        log_error "No environment configuration found"
        return 1
    fi
}

install_email_tools() {
    log_info "Installing email tools..."
    
    # Update package list silently
    if ! sudo apt-get update -qq >/dev/null 2>&1; then
        log_warn "Package list update failed, proceeding anyway"
    fi
    
    # Set up unattended installation
    export DEBIAN_FRONTEND=noninteractive
    
    # Install msmtp and dependencies with unattended options and capture output
    log_info "Installing msmtp and dependencies (output suppressed for clean logs)..."
    local install_log="/tmp/email_tools_install_$$.log"
    if sudo -E apt-get install -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        msmtp msmtp-mta ca-certificates apparmor-utils > "$install_log" 2>&1; then
        log_info "✓ Email tools packages installed successfully"
        rm -f "$install_log"
    else
        log_error "Failed to install email tools packages"
        log_error "Installation error details:"
        head -10 "$install_log" | while read -r line; do
            log_error "  $line"
        done
        rm -f "$install_log"
        return 1
    fi
    
    # Enable AppArmor profile for msmtp if available
    if command -v aa-enforce >/dev/null 2>&1; then
        # Check if msmtp AppArmor profile exists
        if [[ -f /etc/apparmor.d/usr.bin.msmtp ]]; then
            log_info "Enabling AppArmor profile for msmtp..."
            if sudo aa-enforce /etc/apparmor.d/usr.bin.msmtp >/dev/null 2>&1; then
                log_info "✓ AppArmor profile enforced for msmtp"
            else
                log_warn "Could not enforce msmtp AppArmor profile"
            fi
        else
            log_info "Creating and enabling AppArmor profile for msmtp..."
            # Create a basic AppArmor profile for msmtp
            sudo tee /etc/apparmor.d/usr.bin.msmtp > /dev/null << 'EOF'
#include <tunables/global>

/usr/bin/msmtp {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/openssl>
  #include <abstractions/ssl_certs>

  capability net_bind_service,
  capability setuid,
  capability setgid,

  /usr/bin/msmtp mr,
  /etc/msmtprc r,
  /home/*/.msmtprc r,
  /root/.msmtprc r,
  /tmp/.msmtprc r,
  /var/log/msmtp.log w,
  /tmp/msmtp.log w,
  /home/*/msmtp.log w,
  /root/.msmtp.log w,
  /etc/ssl/certs/ r,
  /etc/ssl/certs/** r,
  /usr/share/ca-certificates/ r,
  /usr/share/ca-certificates/** r,
  /etc/ca-certificates.conf r,

  # Network access for SMTP
  network inet stream,
  network inet6 stream,
}
EOF
            # Load and enforce the profile
            if sudo apparmor_parser -r /etc/apparmor.d/usr.bin.msmtp >/dev/null 2>&1; then
                log_info "✓ AppArmor profile loaded for msmtp"
            else
                log_warn "Could not load msmtp AppArmor profile"
            fi
            if sudo aa-enforce /etc/apparmor.d/usr.bin.msmtp >/dev/null 2>&1; then
                log_info "✓ AppArmor profile enforced for msmtp"
            else
                log_warn "Could not enforce msmtp AppArmor profile"
            fi
        fi
        log_info "✓ AppArmor profile configured for msmtp"
    else
        log_warn "AppArmor not available - skipping security profile setup"
    fi
    
    # Reset DEBIAN_FRONTEND
    unset DEBIAN_FRONTEND
    
    log_info "✓ Email tools installed successfully with security profiles"
}

configure_system_msmtp() {
    local config_file="/etc/msmtprc"
    
    log_info "Configuring system-wide msmtp..."
    
    # Create system-wide msmtp configuration
    # Determine TLS configuration based on port and SMTP_TLS setting
    local tls_config
    if [[ "${SMTP_PORT:-587}" == "465" ]] || [[ "${SMTP_TLS:-}" == "YES" ]]; then
        # Port 465 uses immediate SSL (SMTPS)
        tls_config="tls on
tls_starttls off"
    else
        # Port 587 uses STARTTLS
        tls_config="tls on
tls_starttls on"
    fi
    
    sudo tee "$config_file" > /dev/null << EOF
# System-wide msmtp configuration for n8n server
defaults
auth on
${tls_config}
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile /var/log/msmtp.log
# Allow root sender for system notifications
allow_from_override on
# Set default from address
from ${EMAIL_SENDER}

account default
host ${SMTP_SERVER}
port ${SMTP_PORT:-587}
from ${EMAIL_SENDER}
user ${SMTP_USERNAME}
password ${SMTP_PASSWORD}
# Accept all recipients including root
domain
EOF
    
    # Set proper permissions
    sudo chmod 644 "$config_file"
    
    # Create log file with proper permissions
    sudo touch /var/log/msmtp.log
    sudo chmod 666 /var/log/msmtp.log
    
    log_info "✓ System msmtp configuration created: $config_file"
}

configure_user_msmtp() {
    local config_file="$HOME/.msmtprc"
    
    log_info "Configuring user msmtp..."
    
    # Create user-specific msmtp configuration
    # Determine TLS configuration based on port and SMTP_TLS setting
    local tls_config
    if [[ "${SMTP_PORT:-587}" == "465" ]] || [[ "${SMTP_TLS:-}" == "YES" ]]; then
        # Port 465 uses immediate SSL (SMTPS)
        tls_config="tls on
tls_starttls off"
    else
        # Port 587 uses STARTTLS
        tls_config="tls on
tls_starttls on"
    fi
    
    cat > "$config_file" << EOF
# User msmtp configuration for n8n server
defaults
auth on
${tls_config}
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile $HOME/.msmtp.log

account default
host ${SMTP_SERVER}
port ${SMTP_PORT:-587}
from ${EMAIL_SENDER}
user ${SMTP_USERNAME}
password ${SMTP_PASSWORD}
EOF
    
    # Set proper permissions
    chmod 600 "$config_file"
    
    log_info "✓ User msmtp configuration created: $config_file"
}

test_email_sending() {
    log_info "Testing email sending..."
    
    local full_domain="${NGINX_SERVER_NAME:-$(hostname -d 2>/dev/null || echo 'server')}"
    local domain_name="${full_domain%%.*}"  # Extract just the domain name without TLD
    local test_subject="[${domain_name}] Email Configuration Test"
    local test_body="This is a test email from your n8n server.

Server: $(hostname)
Timestamp: $(date)
User: $(whoami)

If you receive this email, your email configuration is working correctly."
    
    # Create temporary email file
    local temp_file=$(mktemp)
    cat > "$temp_file" << EOF
To: ${EMAIL_RECIPIENT}
From: ${EMAIL_SENDER}
Subject: ${test_subject}

${test_body}
EOF
    
    # Test with msmtp
    if command -v msmtp >/dev/null 2>&1; then
        log_info "Sending test email via msmtp..."
        if msmtp -t < "$temp_file" 2>/tmp/msmtp_test.log; then
            log_info "✓ Test email sent successfully via msmtp"
            rm -f "$temp_file"
            return 0
        else
            log_error "✗ Failed to send test email via msmtp"
            log_error "Error: $(cat /tmp/msmtp_test.log 2>/dev/null || echo 'no error details')"
        fi
    else
        log_error "msmtp not found"
    fi
    
    rm -f "$temp_file" /tmp/msmtp_test.log
    return 1
}

show_help() {
    cat << EOF
Email Tools Installation and Configuration for n8n Server

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --install           Install email tools (msmtp, ca-certificates)
    --configure         Configure msmtp with current environment settings
    --test              Send a test email
    --all               Install, configure, and test (default)
    --help              Show this help message

EXAMPLES:
    $0                  # Install, configure, and test email
    $0 --install        # Just install email tools
    $0 --test           # Just send a test email

Make sure your email configuration is set in conf/user.env before running this script.
EOF
}

main() {
    local action="all"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install)
                action="install"
                shift
                ;;
            --configure)
                action="configure"
                shift
                ;;
            --test)
                action="test"
                shift
                ;;
            --all)
                action="all"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Load environment configuration
    if ! load_environment_config; then
        log_error "Failed to load environment configuration"
        exit 1
    fi
    
    # Validate email configuration
    if [[ -z "${EMAIL_RECIPIENT:-}" ]] || [[ -z "${EMAIL_SENDER:-}" ]] || [[ -z "${SMTP_SERVER:-}" ]]; then
        log_error "Email configuration incomplete. Please check conf/user.env"
        log_error "Required: EMAIL_RECIPIENT, EMAIL_SENDER, SMTP_SERVER, SMTP_USERNAME, SMTP_PASSWORD"
        exit 1
    fi
    
    # Execute requested action
    case $action in
        "install")
            install_email_tools
            configure_system_msmtp
            configure_user_msmtp
            ;;
        "configure")
            configure_system_msmtp
            configure_user_msmtp
            ;;
        "test")
            test_email_sending
            ;;
        "all")
            install_email_tools
            configure_system_msmtp
            configure_user_msmtp
            test_email_sending
            ;;
        *)
            log_error "Invalid action: $action"
            exit 1
            ;;
    esac
    
    log_info "Email tools setup completed!"
    log_info "You can now run: bash setup/dynamic_optimization.sh --test-email"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi 