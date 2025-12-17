#!/bin/bash

# Iframe Embedding Configuration Script
# Configures n8n for secure iframe embedding in external web applications

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Load environment variables
load_environment() {
    if [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        source "$PROJECT_ROOT/conf/default.env"
    fi
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        source "$PROJECT_ROOT/conf/user.env"
    fi
    # Derive WEBAPP_* URLs from WEBAPP_SERVER_IP if not set
    derive_webapp_urls "http"
}

# Configure CORS policies
configure_cors_policies() {
    log_info "Configuring CORS policies for iframe embedding..."
    
    # Create CORS configuration
    cat > /opt/n8n/user-configs/cors-config.json << EOF
{
  "cors": {
    "enabled": true,
    "allowedOrigins": [
      "${WEBAPP_DOMAIN:-https://app.example.com}",
      "${WEBAPP_DOMAIN_ALT:-https://webapp.example.com}"
    ],
    "allowedMethods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    "allowedHeaders": [
      "Content-Type",
      "Authorization",
      "X-User-ID",
      "X-Auth-Token",
      "X-Requested-With"
    ],
    "credentials": true,
    "maxAge": 86400
  }
}
EOF
    
    log_pass "CORS policies configured"
}

# Configure Content Security Policy
configure_csp_headers() {
    log_info "Configuring Content Security Policy headers..."
    
    # Build frame-ancestors array based on PRODUCTION flag
    local frame_ancestors_json
    if [[ "${PRODUCTION:-false}" == "false" ]]; then
        # Development mode: include localhost domains
        log_info "Development mode: Adding localhost domains to CSP frame-ancestors"
        frame_ancestors_json=$(
cat << 'FRAME_EOF'
        "${WEBAPP_DOMAIN:-https://app.example.com}",
        "${WEBAPP_DOMAIN_ALT:-https://webapp.example.com}",
        "http://localhost:3000",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
        "http://host.docker.internal:3000"
FRAME_EOF
        )
    else
        # Production mode: only production domains
        log_info "Production mode: Using production-only CSP frame-ancestors"
        frame_ancestors_json=$(
cat << 'FRAME_EOF'
        "${WEBAPP_DOMAIN:-https://app.example.com}",
        "${WEBAPP_DOMAIN_ALT:-https://webapp.example.com}"
FRAME_EOF
        )
    fi
    
    # Create CSP configuration
    cat > /opt/n8n/user-configs/csp-config.json << EOF
{
  "contentSecurityPolicy": {
    "enabled": true,
    "directives": {
      "default-src": ["'self'"],
      "script-src": ["'self'", "'unsafe-inline'", "'unsafe-eval'"],
      "style-src": ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
      "font-src": ["'self'", "https://fonts.gstatic.com"],
      "img-src": ["'self'", "data:", "https:"],
      "connect-src": ["'self'", "wss:", "https:"],
      "frame-ancestors": [
$frame_ancestors_json
      ],
      "frame-src": ["'self'"],
      "object-src": ["'none'"],
      "base-uri": ["'self'"]
    }
  }
}
EOF
    
    log_pass "CSP headers configured"
}

# Configure X-Frame-Options
configure_frame_options() {
    log_info "Configuring X-Frame-Options for selective iframe embedding..."
    
    # Create frame options configuration
    cat > /opt/n8n/user-configs/frame-options.json << EOF
{
  "frameOptions": {
    "policy": "SAMEORIGIN",
    "allowedDomains": [
      "${WEBAPP_DOMAIN:-https://app.example.com}",
      "${WEBAPP_DOMAIN_ALT:-https://webapp.example.com}"
    ]
  }
}
EOF
    
    log_pass "X-Frame-Options configured"
}

# Configure authentication token passing
configure_token_passing() {
    log_info "Configuring authentication token passing..."
    
    # Create token passing configuration
    cat > /opt/n8n/user-configs/token-config.json << EOF
{
  "tokenPassing": {
    "enabled": true,
    "methods": {
      "header": {
        "enabled": true,
        "headerName": "X-Auth-Token"
      },
      "postMessage": {
        "enabled": true,
        "origin": "${WEBAPP_DOMAIN:-https://app.example.com}"
      },
      "urlParam": {
        "enabled": true,
        "paramName": "auth_token"
      }
    },
    "validation": {
      "issuer": "${WEBAPP_DOMAIN:-https://app.example.com}",
      "audience": "${N8N_DOMAIN:-https://n8n.example.com}",
      "algorithm": "HS256"
    }
  }
}
EOF
    
    log_pass "Authentication token passing configured"
}

# Configure session synchronization
configure_session_sync() {
    log_info "Configuring session synchronization..."
    
    # Create session sync script
    cat > /opt/n8n/scripts/session-sync.js << 'EOF'
// Session Synchronization Script
// Handles session sync between web app and embedded n8n

class SessionSync {
    constructor(config) {
        this.config = config;
        this.parentOrigin = config.parentOrigin;
        this.setupMessageListener();
    }

    setupMessageListener() {
        window.addEventListener('message', (event) => {
            if (event.origin !== this.parentOrigin) {
                console.warn('Ignoring message from unauthorized origin:', event.origin);
                return;
            }

            const { type, data } = event.data;

            switch (type) {
                case 'AUTH_TOKEN':
                    this.handleAuthToken(data);
                    break;
                case 'USER_INFO':
                    this.handleUserInfo(data);
                    break;
                case 'SESSION_REFRESH':
                    this.handleSessionRefresh(data);
                    break;
                case 'LOGOUT':
                    this.handleLogout();
                    break;
                default:
                    console.warn('Unknown message type:', type);
            }
        });
    }

    handleAuthToken(tokenData) {
        if (tokenData.token && tokenData.userId) {
            // Store token and user info
            sessionStorage.setItem('n8n_auth_token', tokenData.token);
            sessionStorage.setItem('n8n_user_id', tokenData.userId);
            
            // Update n8n authentication
            this.updateN8nAuth(tokenData);
            
            // Notify parent of successful authentication
            this.sendMessage('AUTH_SUCCESS', { userId: tokenData.userId });
        }
    }

    handleUserInfo(userInfo) {
        sessionStorage.setItem('n8n_user_info', JSON.stringify(userInfo));
        
        // Update UI with user information
        this.updateUserInterface(userInfo);
    }

    handleSessionRefresh(refreshData) {
        if (refreshData.token) {
            sessionStorage.setItem('n8n_auth_token', refreshData.token);
            this.updateN8nAuth(refreshData);
        }
    }

    handleLogout() {
        // Clear session data
        sessionStorage.removeItem('n8n_auth_token');
        sessionStorage.removeItem('n8n_user_id');
        sessionStorage.removeItem('n8n_user_info');
        
        // Redirect to login or show logged out state
        window.location.reload();
    }

    updateN8nAuth(authData) {
        // Update n8n internal authentication
        if (window.n8nAuth) {
            window.n8nAuth.setToken(authData.token);
            window.n8nAuth.setUserId(authData.userId);
        }
    }

    updateUserInterface(userInfo) {
        // Update UI elements with user information
        const userElements = document.querySelectorAll('[data-user-info]');
        userElements.forEach(element => {
            const field = element.getAttribute('data-user-info');
            if (userInfo[field]) {
                element.textContent = userInfo[field];
            }
        });
    }

    sendMessage(type, data) {
        if (window.parent && window.parent !== window) {
            window.parent.postMessage({ type, data }, this.parentOrigin);
        }
    }

    // Initialize session with existing data
    initialize() {
        const token = sessionStorage.getItem('n8n_auth_token');
        const userId = sessionStorage.getItem('n8n_user_id');
        
        if (token && userId) {
            this.updateN8nAuth({ token, userId });
            this.sendMessage('SESSION_READY', { userId });
        } else {
            this.sendMessage('AUTH_REQUIRED', {});
        }
    }
}

// Initialize session sync when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    const config = {
        parentOrigin: window.location.ancestorOrigins ? 
            window.location.ancestorOrigins[0] : 
            document.referrer ? new URL(document.referrer).origin : '*'
    };
    
    const sessionSync = new SessionSync(config);
    sessionSync.initialize();
    
    // Make available globally
    window.sessionSync = sessionSync;
});
EOF

    # Create session sync configuration
    cat > /opt/n8n/user-configs/session-sync.json << EOF
{
  "sessionSync": {
    "enabled": true,
    "syncInterval": 300,
    "heartbeatInterval": 60,
    "timeoutSeconds": 1800,
    "events": {
      "onSessionStart": "session-start",
      "onSessionEnd": "session-end",
      "onSessionRefresh": "session-refresh",
      "onAuthRequired": "auth-required"
    }
  }
}
EOF
    
    log_pass "Session synchronization configured"
}

# Configure URL routing for users
configure_user_routing() {
    log_info "Configuring URL routing for user-specific access..."
    
    # Create routing configuration
    cat > /opt/n8n/user-configs/routing-config.json << EOF
{
  "routing": {
    "userPath": "/user/{userId}",
    "patterns": {
      "workflow": "/user/{userId}/workflow/{workflowId}",
      "execution": "/user/{userId}/execution/{executionId}",
      "settings": "/user/{userId}/settings"
    },
    "redirects": {
      "unauthorized": "/auth/login",
      "forbidden": "/error/403",
      "notFound": "/error/404"
    },
    "middleware": [
      "auth-check",
      "user-validation",
      "quota-check"
    ]
  }
}
EOF
    
    log_pass "User routing configured"
}

# Setup postMessage API
setup_postmessage_api() {
    log_info "Setting up postMessage API for parent-child communication..."
    
    # Create postMessage API script
    cat > /opt/n8n/scripts/postmessage-api.js << 'EOF'
// PostMessage API for n8n iframe communication

class PostMessageAPI {
    constructor() {
        this.handlers = new Map();
        this.setupMessageListener();
        this.parentOrigin = this.getParentOrigin();
    }

    getParentOrigin() {
        if (window.location.ancestorOrigins && window.location.ancestorOrigins.length > 0) {
            return window.location.ancestorOrigins[0];
        }
        if (document.referrer) {
            return new URL(document.referrer).origin;
        }
        return '*';
    }

    setupMessageListener() {
        window.addEventListener('message', (event) => {
            if (this.parentOrigin !== '*' && event.origin !== this.parentOrigin) {
                console.warn('Ignoring message from unauthorized origin:', event.origin);
                return;
            }

            const { type, data, id } = event.data;
            
            if (this.handlers.has(type)) {
                const handler = this.handlers.get(type);
                try {
                    const result = handler(data);
                    if (result instanceof Promise) {
                        result.then(response => {
                            this.sendResponse(id, response);
                        }).catch(error => {
                            this.sendError(id, error.message);
                        });
                    } else {
                        this.sendResponse(id, result);
                    }
                } catch (error) {
                    this.sendError(id, error.message);
                }
            }
        });
    }

    // Register message handlers
    on(type, handler) {
        this.handlers.set(type, handler);
    }

    // Send message to parent
    send(type, data) {
        if (window.parent && window.parent !== window) {
            const message = {
                type,
                data,
                timestamp: Date.now(),
                source: 'n8n-iframe'
            };
            window.parent.postMessage(message, this.parentOrigin);
        }
    }

    // Send response to specific message
    sendResponse(id, data) {
        if (id) {
            this.send('RESPONSE', { id, data, success: true });
        }
    }

    // Send error response
    sendError(id, error) {
        if (id) {
            this.send('RESPONSE', { id, error, success: false });
        }
    }

    // Workflow-related handlers
    setupWorkflowHandlers() {
        this.on('GET_WORKFLOWS', async () => {
            // Return user's workflows
            return await this.getUserWorkflows();
        });

        this.on('GET_WORKFLOW', async (data) => {
            // Return specific workflow
            return await this.getWorkflow(data.workflowId);
        });

        this.on('EXECUTE_WORKFLOW', async (data) => {
            // Execute workflow
            return await this.executeWorkflow(data.workflowId, data.input);
        });

        this.on('GET_EXECUTIONS', async (data) => {
            // Return workflow executions
            return await this.getWorkflowExecutions(data.workflowId);
        });
    }

    // User-related handlers
    setupUserHandlers() {
        this.on('GET_USER_INFO', () => {
            return this.getCurrentUserInfo();
        });

        this.on('GET_USER_METRICS', () => {
            return this.getUserMetrics();
        });

        this.on('UPDATE_USER_SETTINGS', async (data) => {
            return await this.updateUserSettings(data);
        });
    }

    // Navigation handlers
    setupNavigationHandlers() {
        this.on('NAVIGATE_TO', (data) => {
            this.navigateTo(data.path);
        });

        this.on('GET_CURRENT_PATH', () => {
            return window.location.pathname;
        });
    }

    // Helper methods
    async getUserWorkflows() {
        // Implementation would depend on n8n's internal API
        return [];
    }

    async getWorkflow(workflowId) {
        // Implementation would depend on n8n's internal API
        return null;
    }

    async executeWorkflow(workflowId, input) {
        // Implementation would depend on n8n's internal API
        return null;
    }

    async getWorkflowExecutions(workflowId) {
        // Implementation would depend on n8n's internal API
        return [];
    }

    getCurrentUserInfo() {
        const userInfo = sessionStorage.getItem('n8n_user_info');
        return userInfo ? JSON.parse(userInfo) : null;
    }

    getUserMetrics() {
        // Return cached user metrics
        const metrics = sessionStorage.getItem('n8n_user_metrics');
        return metrics ? JSON.parse(metrics) : null;
    }

    async updateUserSettings(settings) {
        // Update user settings
        return { success: true };
    }

    navigateTo(path) {
        window.location.href = path;
    }
}

// Initialize API when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    const api = new PostMessageAPI();
    api.setupWorkflowHandlers();
    api.setupUserHandlers();
    api.setupNavigationHandlers();
    
    // Make available globally
    window.postMessageAPI = api;
    
    // Notify parent that iframe is ready
    api.send('IFRAME_READY', {
        origin: window.location.origin,
        pathname: window.location.pathname
    });
});
EOF
    
    log_pass "PostMessage API configured"
}

# Create security middleware
create_security_middleware() {
    log_info "Creating security middleware for iframe embedding..."
    
    # Create security middleware script
    cat > /opt/n8n/scripts/iframe-security.js << 'EOF'
// Iframe Security Middleware

class IframeSecurity {
    constructor(config) {
        this.config = config;
        this.allowedOrigins = config.allowedOrigins || [];
        this.init();
    }

    init() {
        this.setupCSPViolationListener();
        this.setupClickjackingProtection();
        this.validateParentOrigin();
    }

    setupCSPViolationListener() {
        document.addEventListener('securitypolicyviolation', (event) => {
            console.warn('CSP Violation:', {
                blockedURI: event.blockedURI,
                violatedDirective: event.violatedDirective,
                originalPolicy: event.originalPolicy
            });
            
            // Report violation to parent if needed
            if (window.postMessageAPI) {
                window.postMessageAPI.send('CSP_VIOLATION', {
                    blockedURI: event.blockedURI,
                    directive: event.violatedDirective
                });
            }
        });
    }

    setupClickjackingProtection() {
        // Verify we're in an iframe from allowed origin
        if (window.self !== window.top) {
            const parentOrigin = this.getParentOrigin();
            if (!this.isOriginAllowed(parentOrigin)) {
                console.error('Iframe loaded from unauthorized origin:', parentOrigin);
                document.body.innerHTML = '<div style="padding: 20px; text-align: center;"><h1>Unauthorized Access</h1><p>This application cannot be embedded from this domain.</p></div>';
                return;
            }
        }
    }

    validateParentOrigin() {
        const parentOrigin = this.getParentOrigin();
        if (parentOrigin && !this.isOriginAllowed(parentOrigin)) {
            this.blockContent();
        }
    }

    getParentOrigin() {
        if (window.location.ancestorOrigins && window.location.ancestorOrigins.length > 0) {
            return window.location.ancestorOrigins[0];
        }
        if (document.referrer) {
            return new URL(document.referrer).origin;
        }
        return null;
    }

    isOriginAllowed(origin) {
        if (!origin) return false;
        return this.allowedOrigins.includes(origin) || this.allowedOrigins.includes('*');
    }

    blockContent() {
        document.body.innerHTML = '<div style="padding: 20px; text-align: center; color: #d32f2f;"><h1>Access Denied</h1><p>This application cannot be embedded from unauthorized domains.</p></div>';
        
        // Prevent any scripts from running
        const scripts = document.querySelectorAll('script');
        scripts.forEach(script => script.remove());
    }

    // Content Security helpers
    sanitizeUserInput(input) {
        const div = document.createElement('div');
        div.textContent = input;
        return div.innerHTML;
    }

    validateURL(url) {
        try {
            const urlObj = new URL(url);
            return ['http:', 'https:'].includes(urlObj.protocol);
        } catch {
            return false;
        }
    }
}

// Initialize security when DOM loads
document.addEventListener('DOMContentLoaded', () => {
    const config = {
        allowedOrigins: [
            '${WEBAPP_DOMAIN}',
            '${WEBAPP_DOMAIN_ALT}'
        ]
    };
    
    window.iframeSecurity = new IframeSecurity(config);
});
EOF
    
    # Replace template variables in the JavaScript files
    sed -i "s/\${WEBAPP_DOMAIN}/${WEBAPP_DOMAIN//\//\\/}/g" /opt/n8n/scripts/iframe-security.js
    sed -i "s/\${WEBAPP_DOMAIN_ALT}/${WEBAPP_DOMAIN_ALT//\//\\/}/g" /opt/n8n/scripts/iframe-security.js
    sed -i "s/\${N8N_DOMAIN}/${N8N_DOMAIN//\//\\/}/g" /opt/n8n/scripts/iframe-security.js
    
    log_pass "Security middleware created"
}

# Main execution function
main() {
    log_info "Starting iframe embedding configuration..."
    
    load_environment
    configure_cors_policies
    configure_csp_headers
    configure_frame_options
    configure_token_passing
    configure_session_sync
    configure_user_routing
    setup_postmessage_api
    create_security_middleware
    
    log_pass "Iframe embedding configuration completed successfully"
    log_info "Configuration files created in: /opt/n8n/user-configs/"
    log_info "JavaScript files created in: /opt/n8n/scripts/"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
