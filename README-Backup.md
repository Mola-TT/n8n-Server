# n8n Server Backup System

This document describes the backup and restore system for the n8n server, including automated backups, retention policies, and disaster recovery procedures.

## Overview

The backup system provides:

- **Automated daily, weekly, and monthly backups** via systemd timers
- **Rotational retention** to manage backup storage
- **Compression** to minimize disk usage
- **Optional encryption** for sensitive data
- **Optional remote backup** to S3 or SFTP
- **Email notifications** for backup events
- **Backup verification** to ensure data integrity
- **Automatic cleanup** based on retention policies

## What Gets Backed Up

| Component | Path | Description |
|-----------|------|-------------|
| n8n Home | `/opt/n8n/.n8n/` | Workflows, credentials, encryption keys |
| User Files | `/opt/n8n/files/` | Uploaded files and attachments |
| User Data | `/opt/n8n/users/` | Per-user isolated data |
| Docker Config | `/opt/n8n/docker/` | docker-compose.yml, .env |
| SSL Certificates | `/opt/n8n/ssl/` | SSL/TLS certificates |
| Nginx Config | `/etc/nginx/` | Nginx configuration |
| Redis Data | Container | Queue data (RDB snapshot) |

> **Note:** The PostgreSQL database is external and should be backed up separately on the database server.

## Backup Location

Backups are stored in `/opt/n8n/backups/` with the following structure:

```
/opt/n8n/backups/
├── daily/          # Daily backups (default: keep 7)
├── weekly/         # Weekly backups (default: keep 4)
├── monthly/        # Monthly backups (default: keep 3)
├── manual/         # Manual/on-demand backups
└── temp/           # Temporary staging area
```

## Backup Scripts

All backup management scripts are located in `/opt/n8n/scripts/`:

### backup_now.sh

Create a backup immediately.

```bash
# Create a manual backup
/opt/n8n/scripts/backup_now.sh manual

# Create a daily-type backup
/opt/n8n/scripts/backup_now.sh daily

# Create a backup with custom name
/opt/n8n/scripts/backup_now.sh manual my_backup_name
```

### list_backups.sh

List all available backups.

```bash
# List all backups
/opt/n8n/scripts/list_backups.sh

# List only daily backups
/opt/n8n/scripts/list_backups.sh daily

# List only weekly backups
/opt/n8n/scripts/list_backups.sh weekly
```

### restore_backup.sh

Restore n8n from a backup.

```bash
# Restore from a specific backup file
/opt/n8n/scripts/restore_backup.sh /opt/n8n/backups/daily/n8n_backup_daily_20240101_020000.tar.gz

# Preview restore without making changes
/opt/n8n/scripts/restore_backup.sh backup_name --dry-run

# Restore without stopping services (not recommended)
/opt/n8n/scripts/restore_backup.sh backup_name --skip-services
```

### verify_backup.sh

Verify backup integrity.

```bash
# Verify all backups
/opt/n8n/scripts/verify_backup.sh all

# Verify a specific backup
/opt/n8n/scripts/verify_backup.sh backup_name

# Verbose output
/opt/n8n/scripts/verify_backup.sh all --verbose
```

### cleanup_backups.sh

Manage backup retention and cleanup.

```bash
# Run cleanup with retention policies
/opt/n8n/scripts/cleanup_backups.sh

# Preview cleanup without deleting
/opt/n8n/scripts/cleanup_backups.sh --dry-run

# Force cleanup (ignore minimum retention)
/opt/n8n/scripts/cleanup_backups.sh --force

# Cleanup specific type only
/opt/n8n/scripts/cleanup_backups.sh --type daily
```

## Automated Backup Schedule

The system uses systemd timers for automated backups:

| Timer | Schedule | Description |
|-------|----------|-------------|
| n8n-backup.timer | Daily at 02:00 | Daily backup |
| n8n-backup-weekly.timer | Sunday at 03:00 | Weekly backup |
| n8n-backup-monthly.timer | 1st of month at 04:00 | Monthly backup |
| n8n-backup-cleanup.timer | Daily at 03:00 | Cleanup old backups |

### Managing Timers

```bash
# Check timer status
systemctl list-timers | grep n8n-backup

# Manually trigger a backup
systemctl start n8n-backup.service

# Disable automated backups
systemctl disable n8n-backup.timer

# Re-enable automated backups
systemctl enable n8n-backup.timer
systemctl start n8n-backup.timer
```

## Configuration

Configure backup settings in `/opt/n8n/docker/.env` or environment variables:

### Basic Settings

```bash
# Backup location
BACKUP_LOCATION="/opt/n8n/backups"
BACKUP_ENABLED="true"

# Retention policies (number of backups to keep)
BACKUP_RETENTION_DAILY="7"
BACKUP_RETENTION_WEEKLY="4"
BACKUP_RETENTION_MONTHLY="3"

# Minimum backups to always keep (safety net)
BACKUP_MIN_KEEP="3"

# Storage threshold - trigger emergency cleanup when exceeded
BACKUP_STORAGE_THRESHOLD="85"
```

### Encryption (Optional)

```bash
# Enable encryption (uses GPG symmetric encryption)
BACKUP_ENCRYPTION_ENABLED="true"
BACKUP_ENCRYPTION_KEY="your-secure-passphrase"
```

> **Warning:** Store the encryption key securely. Without it, encrypted backups cannot be restored.

### Remote Backup (Optional)

#### Amazon S3

```bash
BACKUP_REMOTE_ENABLED="true"
BACKUP_REMOTE_TYPE="s3"
BACKUP_S3_BUCKET="your-bucket-name"
BACKUP_S3_REGION="us-east-1"
```

Requires AWS CLI configured with appropriate credentials.

#### SFTP

```bash
BACKUP_REMOTE_ENABLED="true"
BACKUP_REMOTE_TYPE="sftp"
BACKUP_SFTP_HOST="backup.example.com"
BACKUP_SFTP_USER="backup_user"
BACKUP_SFTP_PATH="/backups/n8n"
```

Requires SSH key authentication configured for the backup user.

### Email Notifications

```bash
BACKUP_EMAIL_NOTIFY="true"
EMAIL_RECIPIENT="admin@example.com"
EMAIL_SENDER="n8n@example.com"
```

## Retention Policies

The cleanup system applies the following rules:

1. **Daily backups**: Keep the most recent N daily backups (default: 7)
2. **Weekly backups**: Keep the most recent N weekly backups (default: 4)
3. **Monthly backups**: Keep the most recent N monthly backups (default: 3)
4. **Minimum retention**: Never delete below BACKUP_MIN_KEEP backups per type
5. **Storage threshold**: Emergency cleanup when disk usage exceeds threshold

## Disaster Recovery

### Complete System Recovery

1. **Install fresh n8n server** following the main README

2. **Restore from backup**:
   ```bash
   # List available backups (if backup directory survived)
   /opt/n8n/scripts/list_backups.sh
   
   # Or copy backup from remote storage first
   aws s3 cp s3://bucket/monthly/n8n_backup_monthly_20240101_040000.tar.gz /tmp/
   
   # Restore
   /opt/n8n/scripts/restore_backup.sh /tmp/n8n_backup_monthly_20240101_040000.tar.gz
   ```

3. **Restore database** from your PostgreSQL backup (separate process)

4. **Verify services**:
   ```bash
   docker compose ps
   systemctl status nginx
   ```

### Partial Recovery

#### Restore Only Workflows

```bash
# Extract backup
mkdir /tmp/restore
tar -xzf /opt/n8n/backups/daily/backup.tar.gz -C /tmp/restore

# Copy only workflows
cp -r /tmp/restore/n8n_home/database.sqlite /opt/n8n/.n8n/
# Or for specific workflow files if using file storage
```

#### Restore Only Files

```bash
# Extract and restore only user files
tar -xzf backup.tar.gz -C /tmp/restore
cp -r /tmp/restore/files/* /opt/n8n/files/
chown -R 1000:1000 /opt/n8n/files/
```

## Monitoring

### Backup Status

Check the last backup status:

```bash
cat /var/lib/n8n/backup_state
```

### Backup Logs

```bash
# View backup log
tail -100 /var/log/n8n_backup.log

# Follow backup log
tail -f /var/log/n8n_backup.log
```

### Netdata Dashboard

If Netdata is enabled, backup metrics are available at:
- `https://your-domain.com/netdata/` → n8n section

Monitored metrics:
- Last backup age (hours since last backup)
- Total backup count
- Backup storage size by type (daily/weekly/monthly)

### Health Alerts

The system sends alerts when:
- Last backup is older than 26 hours (warning)
- Last backup is older than 50 hours (critical)
- Backup storage exceeds 80% (warning)
- Backup storage exceeds 90% (critical)

## Troubleshooting

### Backup Fails to Create

1. **Check disk space**:
   ```bash
   df -h /opt/n8n/backups
   ```

2. **Check permissions**:
   ```bash
   ls -la /opt/n8n/backups
   ```

3. **Check log for errors**:
   ```bash
   tail -50 /var/log/n8n_backup.log
   ```

4. **Run backup manually with verbose output**:
   ```bash
   bash -x /opt/n8n/scripts/backup_now.sh manual test
   ```

### Encrypted Backup Won't Restore

1. **Verify encryption key** is set correctly:
   ```bash
   echo $BACKUP_ENCRYPTION_KEY
   ```

2. **Test decryption manually**:
   ```bash
   gpg --batch --passphrase "$BACKUP_ENCRYPTION_KEY" -d backup.tar.gz.gpg > test.tar.gz
   tar -tzf test.tar.gz
   ```

### Timers Not Running

1. **Check timer status**:
   ```bash
   systemctl status n8n-backup.timer
   journalctl -u n8n-backup.timer
   ```

2. **Reload systemd and restart timers**:
   ```bash
   systemctl daemon-reload
   systemctl restart n8n-backup.timer
   ```

### Remote Upload Fails

1. **For S3**: Verify AWS credentials:
   ```bash
   aws sts get-caller-identity
   aws s3 ls s3://your-bucket/
   ```

2. **For SFTP**: Test connection:
   ```bash
   sftp user@host
   ```

## Best Practices

1. **Test restores regularly** - Don't wait for a disaster to find out your backups don't work

2. **Use encryption** for backups containing sensitive data

3. **Enable remote backups** - Local backups won't help if the server fails completely

4. **Monitor backup age** - Set up alerts for failed backups

5. **Keep encryption keys safe** - Store them separately from the backups

6. **Document your recovery process** - Know exactly what steps to follow in an emergency

7. **Backup the database separately** - The external PostgreSQL database needs its own backup strategy

## Testing

Run the backup test suite:

```bash
./test/test_backup.sh
```

This validates:
- Backup directory structure
- Script existence and permissions
- Systemd timer configuration
- Backup creation and verification
- Cleanup and retention policies
