// Environment Configuration Loader
// This script loads configuration from environment variables injected by Docker

// Helper function to get environment variable with fallback
function getEnvVar(name, defaultValue) {
    // In Docker, environment variables are injected via a script tag
    // that sets window.ENV object
    if (typeof window.ENV !== 'undefined' && window.ENV[name]) {
        return window.ENV[name];
    }
    return defaultValue;
}

// Parse boolean values
function parseBool(value) {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') {
        return value.toLowerCase() === 'true';
    }
    return false;
}

// API Configuration loaded from environment
(function () {
    const defaults = window.API_CONFIG_DEFAULTS || window.API_CONFIG || {};

    const config = {
        // Base URL for the n8n user management API
        baseUrl: getEnvVar('N8N_API_BASE_URL', defaults.baseUrl || 'http://localhost:5678/api/v1'),
        
        // API Key for authentication
        apiKey: getEnvVar('N8N_API_KEY', defaults.apiKey || 'your-api-key-here'),
        
        // Refresh interval for auto-updating data (in milliseconds)
        refreshInterval: parseInt(getEnvVar('REFRESH_INTERVAL', String(defaults.refreshInterval ?? 30000)), 10),
        
        // Enable debug logging
        debug: parseBool(getEnvVar('DEBUG_MODE', String(defaults.debug ?? false)))
    };

    window.API_CONFIG = config;
})();

// Log configuration in debug mode (without exposing API key)
if ((window.API_CONFIG && window.API_CONFIG.debug)) {
    console.log('API Configuration loaded:', {
        baseUrl: window.API_CONFIG.baseUrl,
        apiKey: window.API_CONFIG.apiKey ? '***' + window.API_CONFIG.apiKey.slice(-4) : 'not set',
        refreshInterval: window.API_CONFIG.refreshInterval,
        debug: window.API_CONFIG.debug
    });
}

