# n8n Server Security Hardening

This document describes the security hardening features implemented for the n8n server, including fail2ban protection, rate limiting, security monitoring, and optional geographic IP blocking.

## Overview

The security system provides multiple layers of protection:

- **fail2ban** - Automated IP banning based on attack patterns
- **Nginx Security Hardening** - Security headers, rate limiting, and request filtering
- **Security Monitoring** - Continuous monitoring with alerting
- **Geographic IP Blocking** - Optional country-based traffic filtering
- **IP Whitelist Management** - Trusted IP management

## Quick Start

Security features are enabled by default. Key settings in `conf/user.env`:

```bash
# Enable/disable security features
SECURITY_ENABLED="true"
FAIL2BAN_ENABLED="true"

# Whitelist your webapp server and trusted IPs
SECURITY_WHITELIST_IPS="YOUR_WEBAPP_SERVER_IP"

# Email notifications for security events
FAIL2BAN_EMAIL_NOTIFY="true"
```

## fail2ban Protection

### Protected Services

| Jail | Service | Description |
|------|---------|-------------|
| sshd | SSH | Brute-force login protection |
| sshd-aggressive | SSH | Progressive banning for repeat offenders |
| nginx-http-auth-n8n | Nginx | Authentication failure protection |
| nginx-badbots-n8n | Nginx | Bad bot and scanner blocking |
| nginx-webhook-abuse | Nginx | Webhook scanning/enumeration protection |
| n8n-api-auth | API | User Management API brute-force protection |

### Configuration

Default settings in `conf/default.env`:

```bash
FAIL2BAN_BANTIME="3600"      # Ban duration in seconds (1 hour)
FAIL2BAN_MAXRETRY="5"        # Failures before ban
FAIL2BAN_FINDTIME="600"      # Time window for failures (10 minutes)
FAIL2BAN_EMAIL_NOTIFY="true" # Email notifications
```

### Managing Bans

```bash
# Check fail2ban status
sudo fail2ban-client status

# Check specific jail status
sudo fail2ban-client status sshd
sudo fail2ban-client status nginx-http-auth-n8n

# Unban an IP
sudo fail2ban-client set sshd unbanip 1.2.3.4

# Ban an IP manually
sudo fail2ban-client set sshd banip 1.2.3.4

# Check if IP is banned
sudo fail2ban-client get sshd banned
```

### Custom Filters

Custom fail2ban filters are installed in `/etc/fail2ban/filter.d/`:

- `nginx-http-auth-n8n.conf` - n8n authentication failures
- `nginx-badbots-n8n.conf` - Known bad bots and scanners
- `nginx-webhook-abuse.conf` - Webhook scanning detection
- `n8n-api-auth.conf` - API authentication failures

## IP Whitelist Management

### Adding Trusted IPs

Whitelist IPs are never banned by fail2ban.

```bash
# Via script
/opt/n8n/scripts/manage_whitelist.sh add 192.168.1.100

# Remove from whitelist
/opt/n8n/scripts/manage_whitelist.sh remove 192.168.1.100

# List whitelisted IPs
/opt/n8n/scripts/manage_whitelist.sh list
```

### Via Configuration

Add to `conf/user.env`:

```bash
SECURITY_WHITELIST_IPS="192.168.1.100,10.0.0.1,YOUR_WEBAPP_IP"
```

## Nginx Security Hardening

### Security Headers

The following headers are automatically configured:

| Header | Value | Purpose |
|--------|-------|---------|
| X-Content-Type-Options | nosniff | Prevent MIME sniffing |
| X-XSS-Protection | 1; mode=block | XSS protection |
| Referrer-Policy | strict-origin-when-cross-origin | Referrer control |
| Permissions-Policy | (restrictive) | Feature permissions |

### Rate Limiting

Different rate limits are applied per endpoint type:

| Zone | Default Rate | Purpose |
|------|--------------|---------|
| webhook_limit | 10r/s | Webhook endpoints |
| api_limit | 30r/s | API endpoints |
| ui_limit | 100r/s | UI/page loads |
| login_limit | 5r/m | Login attempts |

Configure in `conf/user.env`:

```bash
RATE_LIMIT_WEBHOOK="10r/s"
RATE_LIMIT_API="30r/s"
RATE_LIMIT_UI="100r/s"
```

### Bad Bot Blocking

Automatic blocking of:

- Vulnerability scanners (nikto, sqlmap, nessus, etc.)
- Known malicious user agents
- WordPress/phpMyAdmin probing
- Path traversal attempts
- SQL injection patterns

## Security Monitoring

### Monitor Script

The security monitor runs every 15 minutes and checks:

- fail2ban service status
- Banned IP counts
- Authentication failures
- Suspicious request patterns

```bash
# Check security status
/opt/n8n/scripts/security_monitor.sh --status

# Run a security check
/opt/n8n/scripts/security_monitor.sh --check

# Generate summary
/opt/n8n/scripts/security_monitor.sh --summary
```

### Security Reports

Daily reports are sent via email (configure `SECURITY_REPORT_SCHEDULE`):

```bash
# Generate report manually
/opt/n8n/scripts/security_report.sh

# Send report via email
/opt/n8n/scripts/security_report.sh --send
```

### Alert Thresholds

Alerts are triggered when incidents exceed threshold:

```bash
SECURITY_ALERT_THRESHOLD="10"  # Incidents per check
```

## Geographic IP Blocking (Optional)

Geographic blocking is disabled by default. Enable only if needed.

### Enabling Geo-Blocking

```bash
# In conf/user.env
GEO_BLOCKING_ENABLED="true"
GEO_BLOCK_COUNTRIES="cn,ru,kp"  # Country codes to block
```

### Managing Countries

```bash
# Check status
/opt/n8n/scripts/manage_geo_blocking.sh status

# Add country to blocklist
/opt/n8n/scripts/manage_geo_blocking.sh add cn

# Remove country
/opt/n8n/scripts/manage_geo_blocking.sh remove cn

# Check if IP is blocked
/opt/n8n/scripts/manage_geo_blocking.sh check 8.8.8.8

# Whitelist specific IP
/opt/n8n/scripts/manage_geo_blocking.sh whitelist 1.2.3.4

# Enable/disable
/opt/n8n/scripts/manage_geo_blocking.sh enable
/opt/n8n/scripts/manage_geo_blocking.sh disable
```

### Country Codes

Common country codes:

| Code | Country |
|------|---------|
| cn | China |
| ru | Russia |
| kp | North Korea |
| ir | Iran |
| sy | Syria |
| cu | Cuba |

## Log Files

| Log | Path | Contents |
|-----|------|----------|
| Security Log | `/var/log/n8n_security.log` | Security events and monitoring |
| fail2ban Log | `/var/log/fail2ban.log` | Ban/unban events |
| Nginx Access | `/var/log/nginx/n8n_access.log` | HTTP access logs |
| Webhook Access | `/var/log/nginx/webhook_access.log` | Webhook-specific access |
| Auth Log | `/var/log/auth.log` | SSH authentication |

## Troubleshooting

### False Positives

If legitimate users are being banned:

1. **Check banned IPs**:
   ```bash
   sudo fail2ban-client status nginx-http-auth-n8n
   ```

2. **Unban the IP**:
   ```bash
   sudo fail2ban-client set nginx-http-auth-n8n unbanip 1.2.3.4
   ```

3. **Add to whitelist**:
   ```bash
   /opt/n8n/scripts/manage_whitelist.sh add 1.2.3.4
   ```

4. **Adjust thresholds** in `/etc/fail2ban/jail.local`:
   ```bash
   maxretry = 10  # Increase if too aggressive
   ```

### fail2ban Not Starting

```bash
# Check service status
sudo systemctl status fail2ban

# Check for config errors
sudo fail2ban-client -t

# View logs
sudo journalctl -u fail2ban -n 50
```

### Rate Limiting Too Aggressive

If legitimate users are being rate limited:

1. Check current limits in `/etc/nginx/conf.d/rate_limits.conf`
2. Increase limits in `conf/user.env`:
   ```bash
   RATE_LIMIT_UI="200r/s"
   RATE_LIMIT_API="60r/s"
   ```
3. Reload nginx: `sudo systemctl reload nginx`

### Geo-Blocking Issues

If geo-blocking is blocking legitimate traffic:

```bash
# Check if IP is blocked
/opt/n8n/scripts/manage_geo_blocking.sh check <IP>

# Whitelist the IP
/opt/n8n/scripts/manage_geo_blocking.sh whitelist <IP>

# Temporarily disable
/opt/n8n/scripts/manage_geo_blocking.sh disable
```

## Best Practices

1. **Always whitelist your webapp server IP** to prevent lockouts
2. **Monitor the security log** regularly for patterns
3. **Review daily security reports** for emerging threats
4. **Keep fail2ban updated** for latest filter improvements
5. **Test rate limits** before deploying to production
6. **Use geo-blocking sparingly** - it can block legitimate users

## Testing

Run the security test suite:

```bash
./test/test_security.sh
```

Tests validate:
- fail2ban installation and configuration
- Jail configurations and filters
- Nginx security configurations
- Rate limiting zones
- Security monitoring scripts
- IP whitelist functionality

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| SECURITY_ENABLED | true | Master security toggle |
| FAIL2BAN_ENABLED | true | Enable fail2ban protection |
| FAIL2BAN_BANTIME | 3600 | Ban duration (seconds) |
| FAIL2BAN_MAXRETRY | 5 | Failures before ban |
| FAIL2BAN_FINDTIME | 600 | Time window (seconds) |
| FAIL2BAN_EMAIL_NOTIFY | true | Email on ban events |
| SECURITY_WHITELIST_IPS | "" | Comma-separated trusted IPs |
| RATE_LIMIT_WEBHOOK | 10r/s | Webhook rate limit |
| RATE_LIMIT_API | 30r/s | API rate limit |
| RATE_LIMIT_UI | 100r/s | UI rate limit |
| GEO_BLOCKING_ENABLED | false | Enable geo-blocking |
| GEO_BLOCK_COUNTRIES | "" | Countries to block |
| SECURITY_ALERT_THRESHOLD | 10 | Incidents before alert |
| SECURITY_REPORT_SCHEDULE | 0 6 * * * | Daily report time |

---

**Last Updated**: January 2026  
**Version**: 1.0.0
