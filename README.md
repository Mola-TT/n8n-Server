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
│   ├── cross_server_setup.sh         # Cross-server communication
│   ├── backup_config.sh              # Automated backup system
│   ├── security_config.sh            # Security hardening (fail2ban, etc.)
│   └── geo_blocking.sh               # Geographic IP blocking (optional)
├── test/
│   ├── run_tests.sh                  # Test runner for validation
│   ├── test_docker.sh                # Docker infrastructure tests
│   ├── test_n8n.sh                   # n8n application tests
│   ├── test_netdata.sh               # Monitoring system tests
│   ├── test_ssl_renewal.sh           # SSL certificate tests
│   ├── test_dynamic_optimization.sh  # Optimization system tests
│   ├── test_dynamic_optimization_integration.sh  # Integration tests
│   ├── test_email_notification.sh    # Email notification tests
│   ├── test_hardware_change_detector.sh  # Hardware detection tests
│   ├── test_multi_user.sh            # Multi-user system tests
│   ├── test_iframe_embedding.sh      # Iframe integration tests
│   ├── test_user_monitoring.sh       # User monitoring tests
│   ├── test_user_api.sh              # User management API tests
│   ├── test_user_scaling.sh          # User scaling tests
│   ├── test_performance_metrics.sh   # Performance metrics tests
│   ├── test_cross_server.sh          # Cross-server communication tests
│   ├── test_backup.sh                # Backup system tests
│   └── test_security.sh              # Security hardening tests
├── README.md                         # Main project documentation
├── README-Backup.md                  # Backup system documentation
├── README-Security.md                # Security hardening documentation
├── README-User-Management.md         # User management and API documentation
├── README-Docker-Development.md      # Local Docker development guide
└── README-WebApp-Server.md           # Web app server integration guide
```

## Configuration

### Quick Setup - Only 3 Addresses Required

```bash
# conf/user.env - The only settings you MUST configure:

# --- n8n Server (this server) ---
N8N_SERVER_IP="YOUR_N8N_SERVER_IP"
N8N_SERVER_DOMAIN="your-domain.com"

# --- PostgreSQL Database Server ---
DB_HOST="your-postgres-host.example.com"
DB_PORT="5432"

# --- Web Application Server ---
WEBAPP_SERVER_IP="YOUR_WEBAPP_SERVER_IP"
WEBAPP_SERVER_PORT="3001"
```

All other URLs (like `N8N_WEBHOOK_URL`, `WEBAPP_DOMAIN`, etc.) are **automatically derived** from these base addresses.

### Configuration Files

- **Default settings**: `conf/default.env` - Contains default values for all configuration
- **User overrides**: `conf/user.env` - Optional file for user-specific settings (copy from template)
- **Environment loading**: The script automatically loads default settings first, then overrides with user settings if available

## Current Features (Milestone 9)

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

### Backup System (Milestone 8)
- ✅ Automated daily, weekly, and monthly backups via systemd timers
- ✅ Comprehensive backup of n8n data, workflows, credentials, and encryption keys
- ✅ User files and per-user data directory backups
- ✅ Docker configuration and Redis data backups
- ✅ Rotational retention policies (configurable daily/weekly/monthly)
- ✅ Backup compression (tar.gz) to minimize storage
- ✅ Optional GPG encryption for sensitive data
- ✅ Optional remote backup to S3 or SFTP
- ✅ Email notifications for backup success/failure
- ✅ Backup verification and integrity checking
- ✅ Automatic cleanup based on retention policies
- ✅ Storage threshold monitoring and emergency cleanup
- ✅ Manual backup and restore scripts

### Security Hardening (Milestone 9)
- ✅ fail2ban protection for SSH, Nginx, and API endpoints
- ✅ Custom fail2ban filters for n8n-specific attack patterns
- ✅ Nginx security headers and request filtering
- ✅ Rate limiting per endpoint type (webhooks, API, UI)
- ✅ Bad bot and vulnerability scanner blocking
- ✅ IP whitelist management for trusted sources
- ✅ Security monitoring with automated alerting
- ✅ Daily security reports via email
- ✅ Optional geographic IP blocking by country
- ✅ Webhook abuse and scanning protection
- ✅ Login brute-force protection
- ✅ Security audit logging

## Production Readiness Checklist

Before deploying to production, ensure you have completed these steps:

### Required Configuration
- [ ] Set `PRODUCTION=true` in `conf/user.env`
- [ ] Configure real domain: `N8N_SERVER_DOMAIN="your-domain.com"`
- [ ] Set up DNS records pointing to your server IP
- [ ] Generate secure secrets: `openssl rand -base64 32`
  - `JWT_SECRET`
  - `N8N_IFRAME_JWT_SECRET`
- [ ] Change all default passwords:
  - `N8N_BASIC_AUTH_PASSWORD`
  - `DB_PASSWORD`
  - `NETDATA_NGINX_AUTH_PASSWORD`
  - `SMTP_PASSWORD`
- [ ] Configure real SMTP settings for email notifications
- [ ] Set `SECURITY_WHITELIST_IPS` to your webapp server IP

### Recommended Configuration
- [ ] Configure remote backups: `BACKUP_REMOTE_ENABLED=true` (S3 or SFTP)
- [ ] Enable backup encryption: `BACKUP_ENCRYPTION_ENABLED=true`
- [ ] Review rate limits for expected traffic volume
- [ ] Set up external PostgreSQL backup strategy (database is external)
- [ ] Consider enabling geo-blocking: `GEO_BLOCKING_ENABLED=true`

### Post-Deployment Verification
- [ ] Verify SSL certificate is valid: `curl -I https://your-domain.com`
- [ ] Test n8n login and workflow execution
- [ ] Verify backup creation: `/opt/n8n/scripts/backup_now.sh --type manual`
- [ ] Test email notifications work
- [ ] Review security logs: `tail -f /var/log/n8n_security.log`
- [ ] Check fail2ban status: `fail2ban-client status`

## Maintenance & Updates

### Updating n8n

```bash
# Create backup before updating
/opt/n8n/scripts/backup_now.sh --type manual

# Update n8n to latest version
/opt/n8n/scripts/update.sh

# Or manually:
cd /opt/n8n/docker
docker-compose pull
docker-compose down
docker-compose up -d
docker image prune -f
```

**Scheduled n8n updates** (optional - add to cron):
```bash
# Weekly update every Sunday at 4 AM (after backups)
echo "0 4 * * 0 root /opt/n8n/scripts/update.sh >> /opt/n8n/logs/update.log 2>&1" | sudo tee /etc/cron.d/n8n-update
```

### Updating Ubuntu

**Security updates (recommended - automatic):**
```bash
# Enable unattended security upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

**Full system updates (manual during maintenance window):**
```bash
sudo apt update && sudo apt upgrade -y

# If kernel was updated, schedule a reboot
sudo reboot
```

### Update Best Practices

| Component | Frequency | Approach |
|-----------|-----------|----------|
| n8n | Weekly or on-demand | Via update script after backup |
| Ubuntu Security | Daily | Unattended upgrades (automatic) |
| Ubuntu Full | Monthly | Manual during maintenance window |
| Kernel/Reboot | As needed | After backup, during low-traffic |

**Before any major update:**
1. Create backup: `/opt/n8n/scripts/backup_now.sh --type manual`
2. Check [n8n release notes](https://github.com/n8n-io/n8n/releases) for breaking changes
3. Test in staging environment if possible

## Usage

The `init.sh` script:
1. Makes all scripts in lib/, setup/, and test/ directories executable
2. Updates system packages silently
3. Sets timezone from configuration
4. Loads environment variables (defaults + user overrides)
5. Runs tests to validate the setup

## Documentation

- **[README-Backup.md](README-Backup.md)** - Backup strategy, retention policies, restore procedures, and disaster recovery
- **[README-Security.md](README-Security.md)** - Security hardening, fail2ban configuration, rate limiting, and geo-blocking
- **[README-User-Management.md](README-User-Management.md)** - Comprehensive guide for JWT authentication, user management, folder structure, monitoring, and API endpoints
- **[README-WebApp-Server.md](README-WebApp-Server.md)** - Integration guide for web application servers and iframe embedding
- **[README-Docker-Development.md](README-Docker-Development.md)** - Local Docker development setup for Next.js + FastAPI integration

## Development Notes

- **Minimal Code** – No unnecessary complexity
- **Direct Implementation** – Shortest and clearest approach
- **Single Source of Truth** – All configuration in main scripts
- **No Hotfixes** – All fixes implemented directly in main scripts 