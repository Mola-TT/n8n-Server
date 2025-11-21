// n8n User Management API Configuration
// Update these values to match your n8n server setup

(() => {
    const defaults = {
        // Base URL for the n8n user management API
        // Update this to your n8n server's domain or IP address
        baseUrl: 'https://your-n8n-domain.com/api/v1',
        
        // API Key for authentication
        // This should match the API key configured in your n8n server
        // IMPORTANT: In production, never expose API keys in client-side code
        // Consider implementing a backend proxy for API calls
        apiKey: 'your-api-key-here',
        
        // Refresh interval for auto-updating data (in milliseconds)
        refreshInterval: 30000, // 30 seconds
        
        // Enable debug logging
        debug: false
    };

    window.API_CONFIG_DEFAULTS = defaults;
    if (!window.API_CONFIG) {
        window.API_CONFIG = defaults;
    }
})();

// For local development, you can use:
// API_CONFIG.baseUrl = 'http://localhost:5678/api/v1';

// For production with Nginx reverse proxy:
// API_CONFIG.baseUrl = 'https://n8n.yourdomain.com/api/v1';

// Security Note:
// ================================================================================
// This configuration file exposes the API key in the client-side code.
// For production deployments, you should:
// 1. Implement a backend proxy that handles API authentication
// 2. Use session-based authentication instead of API keys
// 3. Store sensitive credentials on the server side
// 4. Implement proper CORS policies
// 5. Use HTTPS for all communications
// ================================================================================

