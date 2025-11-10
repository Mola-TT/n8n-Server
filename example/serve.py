#!/usr/bin/env python3
"""
Simple HTTP server for n8n User Management Web Application
Serves static files and injects environment variables from webapp.env
"""

import http.server
import socketserver
import os
import sys
from pathlib import Path

# Load environment variables from webapp.env
def load_env_file():
    env_file = Path(__file__).parent / 'webapp.env'
    env_vars = {}
    
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        env_vars[key.strip()] = value.strip()
    else:
        print(f"Warning: {env_file} not found. Using default values.")
        env_vars = {
            'N8N_API_BASE_URL': 'http://localhost:5678/api/v1',
            'N8N_API_KEY': 'your-api-key-here',
            'REFRESH_INTERVAL': '30000',
            'DEBUG_MODE': 'false'
        }
    
    return env_vars

# Custom request handler that injects config
class ConfigInjectHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(Path(__file__).parent), **kwargs)
    
    def end_headers(self):
        # Add CORS headers for local development
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()
    
    def do_GET(self):
        # Serve config.js with environment variables
        if self.path == '/config.js':
            env_vars = load_env_file()
            
            config_content = f"""// Auto-generated configuration from webapp.env
// This file is generated at server startup

window.ENV = {{
    N8N_API_BASE_URL: '{env_vars.get('N8N_API_BASE_URL', 'http://localhost:5678/api/v1')}',
    N8N_API_KEY: '{env_vars.get('N8N_API_KEY', 'your-api-key-here')}',
    REFRESH_INTERVAL: '{env_vars.get('REFRESH_INTERVAL', '30000')}',
    DEBUG_MODE: '{env_vars.get('DEBUG_MODE', 'false')}'
}};
"""
            
            self.send_response(200)
            self.send_header('Content-type', 'application/javascript')
            self.send_header('Content-Length', len(config_content.encode()))
            self.end_headers()
            self.wfile.write(config_content.encode())
        else:
            # Serve other files normally
            super().do_GET()

def main():
    PORT = int(os.environ.get('PORT', 8080))
    
    print("=" * 80)
    print("n8n User Management Web Application")
    print("=" * 80)
    
    # Load and display configuration
    env_vars = load_env_file()
    print(f"\nConfiguration loaded:")
    print(f"  N8N_API_BASE_URL: {env_vars.get('N8N_API_BASE_URL')}")
    print(f"  N8N_API_KEY: {'*' * 8}{env_vars.get('N8N_API_KEY', '')[-4:]}")
    print(f"  REFRESH_INTERVAL: {env_vars.get('REFRESH_INTERVAL')}ms")
    print(f"  DEBUG_MODE: {env_vars.get('DEBUG_MODE')}")
    
    print(f"\nStarting server on http://localhost:{PORT}")
    print(f"Press Ctrl+C to stop the server\n")
    print("=" * 80)
    
    with socketserver.TCPServer(("", PORT), ConfigInjectHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n\nServer stopped.")
            sys.exit(0)

if __name__ == "__main__":
    main()

