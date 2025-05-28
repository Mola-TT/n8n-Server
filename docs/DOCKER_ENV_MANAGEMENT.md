# Docker Environment Management

This document explains how the n8n Docker environment configuration is dynamically generated from your configuration files.

## Overview

The Docker environment file (`/opt/n8n/docker/.env`) is automatically generated from:
1. `conf/default.env` - Default configuration values
2. `conf/user.env` - User-specific overrides (optional)

This ensures a **single source of truth** for all configuration values.

## How It Works

### Initial Setup
During the initial setup (`sudo ./init.sh`), the Docker environment file is automatically created by:
1. Loading values from `conf/default.env`
2. Overriding with values from `conf/user.env` (if it exists)
3. Generating `/opt/n8n/docker/.env` with these values

### Dynamic Values
Some values are generated dynamically:
- `N8N_ENCRYPTION_KEY` - Auto-generated 64-character hex key
- `TIMEZONE` - Uses `SERVER_TIMEZONE` from configuration

## Configuration Workflow

### 1. Initial Configuration
```bash
# Copy template to create your custom configuration
cp conf/user.env.template conf/user.env

# Edit your configuration
nano conf/user.env

# Run setup (this will create Docker .env automatically)
sudo ./init.sh
```

### 2. Updating Configuration
When you modify `conf/user.env` or `conf/default.env`:

```bash
# Option 1: Use the update script (Recommended)
sudo ./scripts/update-docker-env.sh

# Option 2: Regenerate manually
sudo ./setup/docker_config.sh
```

### 3. Apply Changes
After updating the Docker environment:

```bash
# Restart n8n services
sudo /opt/n8n/scripts/service.sh restart

# Check status
sudo /opt/n8n/scripts/service.sh status
```

## Configuration Mapping

| Configuration File Variable | Docker .env Variable | Description |
|------------------------------|---------------------|-------------|
| `N8N_HOST` | `N8N_HOST` | n8n bind address |
| `N8N_PORT` | `N8N_PORT` | n8n port |
| `N8N_PROTOCOL` | `N8N_PROTOCOL` | http/https |
| `N8N_WEBHOOK_URL` | `WEBHOOK_URL` | Webhook endpoint |
| `N8N_EDITOR_BASE_URL` | `N8N_EDITOR_BASE_URL` | Editor URL |
| `N8N_BASIC_AUTH_ACTIVE` | `N8N_BASIC_AUTH_ACTIVE` | Enable auth |
| `N8N_BASIC_AUTH_USER` | `N8N_BASIC_AUTH_USER` | Auth username |
| `N8N_BASIC_AUTH_PASSWORD` | `N8N_BASIC_AUTH_PASSWORD` | Auth password |
| `N8N_SSL_KEY` | `N8N_SSL_KEY` | SSL private key |
| `N8N_SSL_CERT` | `N8N_SSL_CERT` | SSL certificate |
| `SERVER_TIMEZONE` | `TIMEZONE` | Container timezone |
| `DB_HOST` | `DB_HOST` | PostgreSQL host |
| `DB_PORT` | `DB_PORT` | PostgreSQL port |
| `DB_NAME` | `DB_NAME` | Database name |
| `DB_USER` | `DB_USER` | Database user |
| `DB_PASSWORD` | `DB_PASSWORD` | Database password |
| `DB_SSL_ENABLED` | `DB_SSL_ENABLED` | Database SSL |
| `REDIS_DB` | `REDIS_DB` | Redis database |

## Benefits

### ✅ Advantages
- **Single Source of Truth** - All config in one place
- **No Duplication** - Values defined once, used everywhere
- **Automatic Updates** - Changes propagate to Docker automatically
- **Consistency** - Same values across all components
- **Version Control** - Configuration changes tracked in git

### 🔄 Migration from Manual .env
If you previously manually edited `/opt/n8n/docker/.env`:

1. **Backup your current settings:**
   ```bash
   cp /opt/n8n/docker/.env /opt/n8n/docker/.env.backup
   ```

2. **Update your conf/user.env with your values:**
   ```bash
   # Copy template
   cp conf/user.env.template conf/user.env
   
   # Edit with your values from .env.backup
   nano conf/user.env
   ```

3. **Regenerate .env file:**
   ```bash
   sudo ./scripts/update-docker-env.sh
   ```

## Troubleshooting

### Issue: Docker .env not updating
```bash
# Check if configuration files exist
ls -la conf/

# Manually regenerate
sudo ./scripts/update-docker-env.sh

# Check generated file
cat /opt/n8n/docker/.env
```

### Issue: Configuration not loading
```bash
# Verify file permissions
ls -la conf/user.env

# Check for syntax errors
bash -n conf/user.env

# Review logs during regeneration
sudo ./scripts/update-docker-env.sh
```

### Issue: Services not reflecting changes
```bash
# Restart Docker services
sudo /opt/n8n/scripts/service.sh restart

# Check container environment
docker exec n8n env | grep N8N_
```

## Security Notes

- Keep `conf/user.env` secure (contains passwords)
- Don't commit `conf/user.env` to version control
- The `N8N_ENCRYPTION_KEY` is auto-generated and should not be changed
- Backup your configuration before major changes

## Quick Reference

```bash
# Create configuration
cp conf/user.env.template conf/user.env

# Edit configuration
nano conf/user.env

# Update Docker environment
sudo ./scripts/update-docker-env.sh

# Restart services
sudo /opt/n8n/scripts/service.sh restart
``` 