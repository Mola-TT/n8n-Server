#!/bin/bash

# Multi-User n8n Configuration Script
# Implements multi-user architecture with isolated user directories and session management

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Load environment variables
load_environment() {
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        source "$PROJECT_ROOT/conf/user.env"
    fi
    if [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        source "$PROJECT_ROOT/conf/default.env"
    fi
    
    # Set environment file path for JWT_SECRET updates
    ENV_FILE="$PROJECT_ROOT/conf/user.env"
}

# Create multi-user directory structure
create_user_directories() {
    log_info "Creating multi-user directory structure..."
    
    # Main users directory
    execute_silently "sudo mkdir -p /opt/n8n/users"
    execute_silently "sudo chown $USER:docker /opt/n8n/users"
    execute_silently "sudo chmod 755 /opt/n8n/users"
    
    # User management directories
    execute_silently "sudo mkdir -p /opt/n8n/user-sessions"
    execute_silently "sudo mkdir -p /opt/n8n/user-configs"
    execute_silently "sudo mkdir -p /opt/n8n/user-logs"
    
    # Set proper permissions
    execute_silently "sudo chown -R $USER:docker /opt/n8n/user-*"
    execute_silently "sudo chmod -R 755 /opt/n8n/user-*"
    
    log_pass "Multi-user directory structure created successfully"
}

# Configure user isolation settings
configure_user_isolation() {
    log_info "Configuring user isolation settings..."
    
    # Create user isolation configuration
    cat > /opt/n8n/user-configs/isolation.json << 'EOF'
{
  "userIsolation": {
    "enabled": true,
    "dataPath": "/opt/n8n/users/{userId}",
    "maxUsers": 1000,
    "quotas": {
      "storage": "1GB",
      "workflows": 100,
      "executions": 10000
    },
    "cleanup": {
      "inactiveUserDays": 90,
      "tempFilesDays": 7,
      "executionLogDays": 30
    }
  }
}
EOF
    
    log_pass "User isolation configuration created"
}

# Create user provisioning script
create_user_provisioning() {
    log_info "Creating user provisioning script..."
    
    cat > /opt/n8n/scripts/provision-user.sh << 'EOF'
#!/bin/bash

# User Provisioning Script
# Usage: ./provision-user.sh <user_id> [user_email]

USER_ID="$1"
USER_EMAIL="$2"

if [[ -z "$USER_ID" ]]; then
    echo "Error: User ID is required"
    echo "Usage: ./provision-user.sh <user_id> [user_email]"
    exit 1
fi

# Validate user ID format (alphanumeric and underscores only)
if [[ ! "$USER_ID" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "Error: User ID must contain only alphanumeric characters and underscores"
    exit 1
fi

BASE_DIR="/opt/n8n/users/$USER_ID"

# Check if user already exists
if [[ -d "$BASE_DIR" ]]; then
    echo "Warning: User $USER_ID already exists"
    exit 0
fi

echo "Provisioning user: $USER_ID"

# Create user directory structure
mkdir -p "$BASE_DIR"/{workflows,credentials,files,logs,temp,backups}

# Set proper permissions
chown -R $USER:docker "$BASE_DIR"
chmod -R 755 "$BASE_DIR"

# Create user configuration
cat > "$BASE_DIR/user-config.json" << EOL
{
  "userId": "$USER_ID",
  "email": "$USER_EMAIL",
  "createdAt": "$(date -Iseconds)",
  "status": "active",
  "quotas": {
    "storage": "1GB",
    "workflows": 100,
    "executions": 10000
  },
  "settings": {
    "timezone": "UTC",
    "theme": "default"
  }
}
EOL

# Create user metrics file
cat > "/opt/n8n/monitoring/metrics/$USER_ID.json" << EOL
{
  "userId": "$USER_ID",
  "metrics": {
    "storageUsed": 0,
    "workflowCount": 0,
    "executionCount": 0,
    "lastActivity": "$(date -Iseconds)"
  }
}
EOL

echo "User $USER_ID provisioned successfully"
echo "User directory: $BASE_DIR"
EOF

    chmod +x /opt/n8n/scripts/provision-user.sh
    
    log_pass "User provisioning script created"
}

# Create user deprovisioning script
create_user_deprovisioning() {
    log_info "Creating user deprovisioning script..."
    
    cat > /opt/n8n/scripts/deprovision-user.sh << 'EOF'
#!/bin/bash

# User Deprovisioning Script
# Usage: ./deprovision-user.sh <user_id> [--backup]

USER_ID="$1"
CREATE_BACKUP="$2"

if [[ -z "$USER_ID" ]]; then
    echo "Error: User ID is required"
    echo "Usage: ./deprovision-user.sh <user_id> [--backup]"
    exit 1
fi

BASE_DIR="/opt/n8n/users/$USER_ID"

# Check if user exists
if [[ ! -d "$BASE_DIR" ]]; then
    echo "Warning: User $USER_ID does not exist"
    exit 0
fi

echo "Deprovisioning user: $USER_ID"

# Create backup if requested
if [[ "$CREATE_BACKUP" == "--backup" ]]; then
    BACKUP_FILE="/opt/n8n/backups/user_${USER_ID}_$(date +%Y%m%d_%H%M%S).tar.gz"
    echo "Creating backup: $BACKUP_FILE"
    tar -czf "$BACKUP_FILE" -C "/opt/n8n/users" "$USER_ID"
    echo "Backup created successfully"
fi

# Remove user directory
rm -rf "$BASE_DIR"

# Remove user metrics
rm -f "/opt/n8n/monitoring/metrics/$USER_ID.json"

# Remove user session files
rm -f "/opt/n8n/user-sessions/$USER_ID"*

# Remove user logs
rm -f "/opt/n8n/user-logs/$USER_ID"*

echo "User $USER_ID deprovisioned successfully"
EOF

    chmod +x /opt/n8n/scripts/deprovision-user.sh
    
    log_pass "User deprovisioning script created"
}

# Configure session management
configure_session_management() {
    log_info "Configuring session management..."
    
    # Create session management configuration
    cat > /opt/n8n/user-configs/session-config.json << 'EOF'
{
  "sessionManagement": {
    "enabled": true,
    "sessionTimeout": 3600,
    "maxConcurrentSessions": 5,
    "sessionStorePath": "/opt/n8n/user-sessions",
    "security": {
      "httpOnly": true,
      "secure": true,
      "sameSite": "strict"
    }
  }
}
EOF

    # Create session cleanup script
    cat > /opt/n8n/scripts/cleanup-sessions.sh << 'EOF'
#!/bin/bash

# Session Cleanup Script
# Removes expired user sessions

SESSION_DIR="/opt/n8n/user-sessions"
TIMEOUT_SECONDS=3600

echo "Cleaning up expired sessions..."

# Find and remove expired session files
find "$SESSION_DIR" -name "session_*" -type f -mmin +$((TIMEOUT_SECONDS/60)) -delete

echo "Session cleanup completed"
EOF

    chmod +x /opt/n8n/scripts/cleanup-sessions.sh
    
    # Add to crontab for automatic cleanup
    (crontab -l 2>/dev/null; echo "*/15 * * * * /opt/n8n/scripts/cleanup-sessions.sh >> /opt/n8n/logs/session-cleanup.log 2>&1") | crontab -
    
    log_pass "Session management configured"
}

# Configure user authentication
configure_user_authentication() {
    log_info "Configuring user authentication..."
    
    # Create authentication configuration
    cat > /opt/n8n/user-configs/auth-config.json << 'EOF'
{
  "authentication": {
    "type": "external",
    "jwtSecret": "REPLACE_WITH_ACTUAL_JWT_SECRET",
    "tokenExpiration": "24h",
    "refreshTokenExpiration": "7d",
    "endpoints": {
      "login": "/auth/login",
      "logout": "/auth/logout",
      "refresh": "/auth/refresh",
      "validate": "/auth/validate"
    },
    "headers": {
      "userIdHeader": "X-User-ID",
      "authTokenHeader": "X-Auth-Token"
    }
  }
}
EOF

    # Generate JWT secret
    JWT_SECRET=$(openssl rand -base64 32)
    # Escape special characters for sed
    JWT_SECRET_ESCAPED=$(printf '%s\n' "$JWT_SECRET" | sed 's/[[\.*^$()+?{|]/\\&/g')
    sed -i "s/REPLACE_WITH_ACTUAL_JWT_SECRET/$JWT_SECRET_ESCAPED/" /opt/n8n/user-configs/auth-config.json
    
    # Update environment file with JWT secret
    if [[ -f "$ENV_FILE" ]]; then
        # Check if JWT_SECRET exists in the file
        if grep -q "^JWT_SECRET=" "$ENV_FILE"; then
            # Update existing JWT_SECRET using a different approach to avoid sed escaping issues
            grep -v "^JWT_SECRET=" "$ENV_FILE" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "$ENV_FILE"
            echo "JWT_SECRET=\"$JWT_SECRET\"" >> "$ENV_FILE"
        else
            # Append JWT_SECRET if it doesn't exist
            echo "JWT_SECRET=\"$JWT_SECRET\"" >> "$ENV_FILE"
        fi
    fi
    
    # Export for current session
    export JWT_SECRET
    
    log_pass "User authentication configured"
}

# Create user access control script
create_access_control() {
    log_info "Creating user access control script..."
    
    cat > /opt/n8n/scripts/check-user-access.sh << 'EOF'
#!/bin/bash

# User Access Control Script
# Usage: ./check-user-access.sh <user_id> <resource>

USER_ID="$1"
RESOURCE="$2"

if [[ -z "$USER_ID" || -z "$RESOURCE" ]]; then
    echo "Error: User ID and resource are required"
    echo "Usage: ./check-user-access.sh <user_id> <resource>"
    exit 1
fi

USER_DIR="/opt/n8n/users/$USER_ID"
USER_CONFIG="$USER_DIR/user-config.json"

# Check if user exists and is active
if [[ ! -f "$USER_CONFIG" ]]; then
    echo "Access denied: User not found"
    exit 1
fi

# Check user status
STATUS=$(jq -r '.status' "$USER_CONFIG" 2>/dev/null)
if [[ "$STATUS" != "active" ]]; then
    echo "Access denied: User not active"
    exit 1
fi

# Check resource quotas
case "$RESOURCE" in
    "workflow")
        CURRENT_COUNT=$(find "$USER_DIR/workflows" -name "*.json" | wc -l)
        MAX_WORKFLOWS=$(jq -r '.quotas.workflows' "$USER_CONFIG" 2>/dev/null || echo "100")
        if [[ $CURRENT_COUNT -ge $MAX_WORKFLOWS ]]; then
            echo "Access denied: Workflow quota exceeded"
            exit 1
        fi
        ;;
    "storage")
        CURRENT_SIZE=$(du -sb "$USER_DIR" | cut -f1)
        MAX_SIZE_GB=$(jq -r '.quotas.storage' "$USER_CONFIG" 2>/dev/null | sed 's/GB//' || echo "1")
        MAX_SIZE=$((MAX_SIZE_GB * 1024 * 1024 * 1024))
        if [[ $CURRENT_SIZE -ge $MAX_SIZE ]]; then
            echo "Access denied: Storage quota exceeded"
            exit 1
        fi
        ;;
esac

echo "Access granted"
exit 0
EOF

    chmod +x /opt/n8n/scripts/check-user-access.sh
    
    log_pass "User access control script created"
}

# Main execution function
main() {
    log_info "Starting multi-user n8n configuration..."
    
    load_environment
    create_user_directories
    configure_user_isolation
    create_user_provisioning
    create_user_deprovisioning
    configure_session_management
    configure_user_authentication
    create_access_control
    
    log_pass "Multi-user n8n configuration completed successfully"
    log_info "Users can be provisioned using: /opt/n8n/scripts/provision-user.sh <user_id>"
    log_info "User data will be stored in: /opt/n8n/users/<user_id>/"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
