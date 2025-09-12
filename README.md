# n8n Server Initialization Scripts

Ubuntu scripts for initializing an n8n server. The scripts are developed on Windows but deployed on Ubuntu systems.

## Quick Start

1. **Configure your environment** (optional):
   ```bash
   cp conf/user.env.template conf/user.env
   # Edit conf/user.env with your specific settings
   ```

2. **Run the initialization**:
   ```bash
   sudo ./init.sh
   ```

## Project Structure

```
├── init.sh                           # Main initialization script
├── conf/
│   ├── default.env                   # Default configuration values
│   ├── user.env                      # User-specific configuration
│   └── user.env.template             # Template for user customization
├── lib/
│   ├── logger.sh                     # Color-coded logging system
│   └── utilities.sh                  # Helper functions
├── setup/
│   ├── general_config.sh             # System configuration functions
│   ├── docker_config.sh              # Docker infrastructure setup
│   ├── nginx_config.sh               # Nginx reverse proxy configuration
│   ├── netdata_config.sh             # System monitoring setup
│   ├── ssl_renewal.sh                # SSL certificate management
│   ├── dynamic_optimization.sh       # Hardware-based optimization
│   ├── hardware_change_detector.sh   # Hardware change monitoring
│   ├── multi_user_config.sh          # Multi-user architecture setup
│   ├── iframe_embedding_config.sh    # Iframe embedding configuration
│   ├── user_monitoring.sh            # User monitoring and analytics
│   ├── user_management_api.sh        # User management API server
│   └── cross_server_setup.sh         # Cross-server communication
├── test/
│   ├── run_tests.sh                  # Test runner for validation
│   ├── test_docker.sh                # Docker infrastructure tests
│   ├── test_nginx.sh                 # Nginx configuration tests
│   ├── test_netdata.sh               # Monitoring system tests
│   ├── test_ssl_renewal.sh           # SSL certificate tests
│   ├── test_dynamic_optimization.sh  # Optimization system tests
│   ├── test_multi_user.sh            # Multi-user system tests
│   ├── test_iframe_embedding.sh      # Iframe integration tests
│   ├── test_user_monitoring.sh       # User monitoring tests
│   ├── test_user_api.sh              # User management API tests
│   └── test_cross_server.sh          # Cross-server communication tests
├── README.md                         # Main project documentation
├── README-User-Management.md         # User management and API documentation
└── README-WebApp-Server.md           # Web app server integration guide
```

## Configuration

- **Default settings**: `conf/default.env` - Contains default values for all configuration
- **User overrides**: `conf/user.env` - Optional file for user-specific settings (copy from template)
- **Environment loading**: The script automatically loads default settings first, then overrides with user settings if available

## Current Features (Milestone 7)

### Core Infrastructure (Milestones 1-6)
- ✅ Silent Ubuntu server updates and system configuration
- ✅ Docker infrastructure with n8n containerization
- ✅ Nginx reverse proxy with SSL termination
- ✅ Netdata system monitoring with health alerts
- ✅ SSL certificate management (Let's Encrypt + self-signed)
- ✅ Dynamic hardware-based optimization
- ✅ Hardware change detection and auto-reconfiguration

### Multi-User Architecture (Milestone 7)
- ✅ Multi-user n8n architecture with isolated user directories
- ✅ JWT-based authentication and session management
- ✅ User provisioning and deprovisioning automation
- ✅ Per-user workflow and credential storage isolation
- ✅ User-specific file storage and access control
- ✅ Iframe embedding configuration for web applications
- ✅ Cross-server communication and API integration
- ✅ Comprehensive user monitoring and analytics
- ✅ User management REST API with full CRUD operations
- ✅ Real-time execution time tracking and performance metrics
- ✅ Storage usage monitoring with quota enforcement
- ✅ Automated cleanup and maintenance for inactive users

## Usage

The `init.sh` script:
1. Makes all scripts in lib/, setup/, and test/ directories executable
2. Updates system packages silently
3. Sets timezone from configuration
4. Loads environment variables (defaults + user overrides)
5. Runs tests to validate the setup

## Documentation

- **[README-User-Management.md](README-User-Management.md)** - Comprehensive guide for JWT authentication, user management, folder structure, monitoring, and API endpoints
- **[README-WebApp-Server.md](README-WebApp-Server.md)** - Integration guide for web application servers and iframe embedding

## Development Notes

- **Minimal Code** – No unnecessary complexity
- **Direct Implementation** – Shortest and clearest approach
- **Single Source of Truth** – All configuration in main scripts
- **No Hotfixes** – All fixes implemented directly in main scripts 