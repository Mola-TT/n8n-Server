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
const API_CONFIG = {
    // Base URL for the n8n user management API
    baseUrl: getEnvVar('N8N_API_BASE_URL', 'http://localhost:5678/api/v1'),
    
    // API Key for authentication
    apiKey: getEnvVar('N8N_API_KEY', 'your-api-key-here'),
    
    // Refresh interval for auto-updating data (in milliseconds)
    refreshInterval: parseInt(getEnvVar('REFRESH_INTERVAL', '30000')),
    
    // Enable debug logging
    debug: parseBool(getEnvVar('DEBUG_MODE', 'false'))
};

// Log configuration in debug mode (without exposing API key)
if (API_CONFIG.debug) {
    console.log('API Configuration loaded:', {
        baseUrl: API_CONFIG.baseUrl,
        apiKey: API_CONFIG.apiKey ? '***' + API_CONFIG.apiKey.slice(-4) : 'not set',
        refreshInterval: API_CONFIG.refreshInterval,
        debug: API_CONFIG.debug
    });
}

