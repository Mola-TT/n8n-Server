#!/bin/bash

# ==============================================================================
# Backup Configuration Script for n8n Server - Milestone 8
# ==============================================================================
# This script sets up automated backup infrastructure for n8n server including
# backup creation, rotation, cleanup, and monitoring
# ==============================================================================

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# ==============================================================================
# Default Configuration
# ==============================================================================

# Backup paths
BACKUP_BASE_DIR="${BACKUP_LOCATION:-/opt/n8n/backups}"
BACKUP_SCRIPTS_DIR="/opt/n8n/scripts"
BACKUP_LOG_FILE="/var/log/n8n_backup.log"
BACKUP_STATE_FILE="/var/lib/n8n/backup_state"

# n8n data directories to backup
N8N_DATA_DIR="${N8N_DATA_DIR:-/opt/n8n}"
N8N_HOME_DIR="$N8N_DATA_DIR/.n8n"
N8N_FILES_DIR="$N8N_DATA_DIR/files"
N8N_USERS_DIR="$N8N_DATA_DIR/users"
N8N_DOCKER_DIR="$N8N_DATA_DIR/docker"
N8N_SSL_DIR="$N8N_DATA_DIR/ssl"

# Nginx configuration
NGINX_CONF_DIR="/etc/nginx"

# Default retention settings
BACKUP_RETENTION_DAILY="${BACKUP_RETENTION_DAILY:-7}"
BACKUP_RETENTION_WEEKLY="${BACKUP_RETENTION_WEEKLY:-4}"
BACKUP_RETENTION_MONTHLY="${BACKUP_RETENTION_MONTHLY:-3}"
BACKUP_MIN_KEEP="${BACKUP_MIN_KEEP:-3}"
BACKUP_STORAGE_THRESHOLD="${BACKUP_STORAGE_THRESHOLD:-85}"

# Backup schedule (cron format)
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
BACKUP_CLEANUP_SCHEDULE="${BACKUP_CLEANUP_SCHEDULE:-0 3 * * *}"

# Encryption settings
BACKUP_ENCRYPTION_ENABLED="${BACKUP_ENCRYPTION_ENABLED:-false}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

# Remote backup settings
BACKUP_REMOTE_ENABLED="${BACKUP_REMOTE_ENABLED:-false}"
BACKUP_REMOTE_TYPE="${BACKUP_REMOTE_TYPE:-}"

# Email notification
BACKUP_EMAIL_NOTIFY="${BACKUP_EMAIL_NOTIFY:-true}"

# ==============================================================================
# Utility Functions
# ==============================================================================

log_backup() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO") log_info "$message" ;;
        "WARN") log_warn "$message" ;;
        "ERROR") log_error "$message" ;;
        "DEBUG") log_debug "$message" ;;
    esac
    
    # Also log to backup-specific log file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$BACKUP_LOG_FILE"
}

ensure_directory() {
    local dir="$1"
    local permissions="${2:-755}"
    
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod "$permissions" "$dir"
        log_backup "INFO" "Created directory: $dir"
    fi
}

# ==============================================================================
# Setup Functions
# ==============================================================================

setup_backup_directories() {
    log_info "Setting up backup directories..."
    
    # Create main backup directory structure
    ensure_directory "$BACKUP_BASE_DIR" "750"
    ensure_directory "$BACKUP_BASE_DIR/daily" "750"
    ensure_directory "$BACKUP_BASE_DIR/weekly" "750"
    ensure_directory "$BACKUP_BASE_DIR/monthly" "750"
    ensure_directory "$BACKUP_BASE_DIR/manual" "750"
    ensure_directory "$BACKUP_BASE_DIR/temp" "750"
    
    # Create state directory
    ensure_directory "$(dirname "$BACKUP_STATE_FILE")" "755"
    
    # Create log directory
    ensure_directory "$(dirname "$BACKUP_LOG_FILE")" "755"
    touch "$BACKUP_LOG_FILE"
    chmod 644 "$BACKUP_LOG_FILE"
    
    # Set ownership to allow Docker user access
    chown -R root:docker "$BACKUP_BASE_DIR" 2>/dev/null || true
    
    log_info "Backup directories created successfully"
}

create_backup_now_script() {
    log_info "Creating backup_now.sh script..."
    
    cat > "$BACKUP_SCRIPTS_DIR/backup_now.sh" << 'BACKUP_SCRIPT'
#!/bin/bash

# ==============================================================================
# n8n Backup Script - Creates backup of all n8n data
# ==============================================================================

set -e

# Configuration
BACKUP_BASE_DIR="${BACKUP_LOCATION:-/opt/n8n/backups}"
BACKUP_LOG_FILE="/var/log/n8n_backup.log"
N8N_DATA_DIR="${N8N_DATA_DIR:-/opt/n8n}"

# Backup type (daily, weekly, monthly, manual)
BACKUP_TYPE="${1:-manual}"
BACKUP_NAME="${2:-}"

# Encryption settings
BACKUP_ENCRYPTION_ENABLED="${BACKUP_ENCRYPTION_ENABLED:-false}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

# Remote settings
BACKUP_REMOTE_ENABLED="${BACKUP_REMOTE_ENABLED:-false}"
BACKUP_REMOTE_TYPE="${BACKUP_REMOTE_TYPE:-}"

# Email settings
BACKUP_EMAIL_NOTIFY="${BACKUP_EMAIL_NOTIFY:-true}"
EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-}"
EMAIL_SENDER="${EMAIL_SENDER:-}"

log_backup() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$BACKUP_LOG_FILE"
}

send_notification() {
    local subject="$1"
    local body="$2"
    
    if [ "$BACKUP_EMAIL_NOTIFY" = "true" ] && [ -n "$EMAIL_RECIPIENT" ]; then
        echo "$body" | mail -s "$subject" "$EMAIL_RECIPIENT" 2>/dev/null || \
        echo "$body" | sendmail "$EMAIL_RECIPIENT" 2>/dev/null || \
        log_backup "WARN" "Failed to send email notification"
    fi
}

# Generate backup filename
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
if [ -z "$BACKUP_NAME" ]; then
    BACKUP_NAME="n8n_backup_${BACKUP_TYPE}_${TIMESTAMP}"
fi
BACKUP_DIR="$BACKUP_BASE_DIR/$BACKUP_TYPE"
BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
BACKUP_MANIFEST="$BACKUP_DIR/${BACKUP_NAME}.manifest"

log_backup "INFO" "Starting $BACKUP_TYPE backup: $BACKUP_NAME"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Create temporary directory for staging
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Collect backup data
log_backup "INFO" "Collecting backup data..."

BACKUP_ITEMS=()
BACKUP_SIZE=0

# 1. n8n home directory (workflows, credentials, encryption keys)
if [ -d "$N8N_DATA_DIR/.n8n" ]; then
    cp -rp "$N8N_DATA_DIR/.n8n" "$TEMP_DIR/n8n_home"
    BACKUP_ITEMS+=(".n8n")
    log_backup "INFO" "  Added: .n8n directory"
fi

# 2. User files
if [ -d "$N8N_DATA_DIR/files" ]; then
    cp -rp "$N8N_DATA_DIR/files" "$TEMP_DIR/files"
    BACKUP_ITEMS+=("files")
    log_backup "INFO" "  Added: files directory"
fi

# 3. Per-user data directories
if [ -d "$N8N_DATA_DIR/users" ]; then
    cp -rp "$N8N_DATA_DIR/users" "$TEMP_DIR/users"
    BACKUP_ITEMS+=("users")
    log_backup "INFO" "  Added: users directory"
fi

# 4. Docker configuration
if [ -d "$N8N_DATA_DIR/docker" ]; then
    mkdir -p "$TEMP_DIR/docker"
    cp -p "$N8N_DATA_DIR/docker/docker-compose.yml" "$TEMP_DIR/docker/" 2>/dev/null || true
    cp -p "$N8N_DATA_DIR/docker/.env" "$TEMP_DIR/docker/" 2>/dev/null || true
    BACKUP_ITEMS+=("docker")
    log_backup "INFO" "  Added: docker configuration"
fi

# 5. SSL certificates
if [ -d "$N8N_DATA_DIR/ssl" ]; then
    cp -rp "$N8N_DATA_DIR/ssl" "$TEMP_DIR/ssl"
    BACKUP_ITEMS+=("ssl")
    log_backup "INFO" "  Added: ssl certificates"
fi

# 6. Nginx configuration
if [ -d "/etc/nginx" ]; then
    mkdir -p "$TEMP_DIR/nginx"
    cp -p /etc/nginx/nginx.conf "$TEMP_DIR/nginx/" 2>/dev/null || true
    cp -rp /etc/nginx/sites-available "$TEMP_DIR/nginx/" 2>/dev/null || true
    cp -rp /etc/nginx/sites-enabled "$TEMP_DIR/nginx/" 2>/dev/null || true
    cp -rp /etc/nginx/ssl "$TEMP_DIR/nginx/" 2>/dev/null || true
    BACKUP_ITEMS+=("nginx")
    log_backup "INFO" "  Added: nginx configuration"
fi

# 7. Redis data (export RDB snapshot)
if docker ps --format '{{.Names}}' | grep -q 'redis'; then
    log_backup "INFO" "  Exporting Redis data..."
    docker exec n8n-redis redis-cli BGSAVE 2>/dev/null || true
    sleep 2
    if docker cp n8n-redis:/data/dump.rdb "$TEMP_DIR/redis_dump.rdb" 2>/dev/null; then
        BACKUP_ITEMS+=("redis")
        log_backup "INFO" "  Added: redis data"
    fi
fi

# Create backup manifest
cat > "$TEMP_DIR/MANIFEST" << EOF
Backup Name: $BACKUP_NAME
Backup Type: $BACKUP_TYPE
Created: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
n8n Data Dir: $N8N_DATA_DIR
Items Included:
$(printf '  - %s\n' "${BACKUP_ITEMS[@]}")
EOF

# Create compressed archive
log_backup "INFO" "Creating compressed archive..."
cd "$TEMP_DIR"

if [ "$BACKUP_ENCRYPTION_ENABLED" = "true" ] && [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
    # Create encrypted backup
    tar -czf - . | gpg --symmetric --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" -o "${BACKUP_FILE}.gpg"
    BACKUP_FILE="${BACKUP_FILE}.gpg"
    log_backup "INFO" "Created encrypted backup"
else
    # Create unencrypted backup
    tar -czf "$BACKUP_FILE" .
    log_backup "INFO" "Created uncompressed backup"
fi

# Copy manifest separately for quick reference
cp "$TEMP_DIR/MANIFEST" "$BACKUP_MANIFEST"

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)

# Verify backup integrity
log_backup "INFO" "Verifying backup integrity..."
if [ "$BACKUP_ENCRYPTION_ENABLED" = "true" ] && [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
    if gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" -d "$BACKUP_FILE" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
        log_backup "INFO" "Backup verification: PASSED"
        VERIFICATION_STATUS="PASSED"
    else
        log_backup "ERROR" "Backup verification: FAILED"
        VERIFICATION_STATUS="FAILED"
    fi
else
    if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        log_backup "INFO" "Backup verification: PASSED"
        VERIFICATION_STATUS="PASSED"
    else
        log_backup "ERROR" "Backup verification: FAILED"
        VERIFICATION_STATUS="FAILED"
    fi
fi

# Upload to remote if enabled
if [ "$BACKUP_REMOTE_ENABLED" = "true" ]; then
    log_backup "INFO" "Uploading to remote storage..."
    case "$BACKUP_REMOTE_TYPE" in
        s3)
            if command -v aws &>/dev/null && [ -n "$BACKUP_S3_BUCKET" ]; then
                aws s3 cp "$BACKUP_FILE" "s3://$BACKUP_S3_BUCKET/$BACKUP_TYPE/$(basename $BACKUP_FILE)" && \
                    log_backup "INFO" "Uploaded to S3: $BACKUP_S3_BUCKET" || \
                    log_backup "ERROR" "Failed to upload to S3"
            fi
            ;;
        sftp)
            if [ -n "$BACKUP_SFTP_HOST" ] && [ -n "$BACKUP_SFTP_USER" ] && [ -n "$BACKUP_SFTP_PATH" ]; then
                sftp "$BACKUP_SFTP_USER@$BACKUP_SFTP_HOST" <<< "put $BACKUP_FILE $BACKUP_SFTP_PATH/$BACKUP_TYPE/" && \
                    log_backup "INFO" "Uploaded to SFTP: $BACKUP_SFTP_HOST" || \
                    log_backup "ERROR" "Failed to upload to SFTP"
            fi
            ;;
    esac
fi

# Update state file
mkdir -p "$(dirname /var/lib/n8n/backup_state)"
cat > /var/lib/n8n/backup_state << EOF
last_backup_time=$(date '+%Y-%m-%d %H:%M:%S')
last_backup_type=$BACKUP_TYPE
last_backup_file=$BACKUP_FILE
last_backup_size=$BACKUP_SIZE
last_backup_status=$VERIFICATION_STATUS
EOF

# Send notification
NOTIFICATION_BODY="n8n Backup Completed

Backup Name: $BACKUP_NAME
Type: $BACKUP_TYPE
Size: $BACKUP_SIZE
Location: $BACKUP_FILE
Verification: $VERIFICATION_STATUS
Time: $(date '+%Y-%m-%d %H:%M:%S')
Items: ${BACKUP_ITEMS[*]}"

if [ "$VERIFICATION_STATUS" = "PASSED" ]; then
    send_notification "[n8n] Backup Successful - $BACKUP_TYPE" "$NOTIFICATION_BODY"
    log_backup "INFO" "Backup completed successfully: $BACKUP_FILE ($BACKUP_SIZE)"
    exit 0
else
    send_notification "[n8n] Backup FAILED - $BACKUP_TYPE" "$NOTIFICATION_BODY"
    log_backup "ERROR" "Backup completed with errors: $BACKUP_FILE"
    exit 1
fi
BACKUP_SCRIPT

    chmod +x "$BACKUP_SCRIPTS_DIR/backup_now.sh"
    log_info "Created backup_now.sh"
}

create_list_backups_script() {
    log_info "Creating list_backups.sh script..."
    
    cat > "$BACKUP_SCRIPTS_DIR/list_backups.sh" << 'LIST_SCRIPT'
#!/bin/bash

# ==============================================================================
# n8n List Backups Script - Lists all available backup points
# ==============================================================================

BACKUP_BASE_DIR="${BACKUP_LOCATION:-/opt/n8n/backups}"
BACKUP_TYPE="${1:-all}"

print_header() {
    printf "\n%-50s %-10s %-20s %-15s\n" "BACKUP NAME" "TYPE" "DATE" "SIZE"
    printf "%s\n" "$(printf '=%.0s' {1..100})"
}

list_backups() {
    local type="$1"
    local dir="$BACKUP_BASE_DIR/$type"
    
    if [ -d "$dir" ]; then
        for backup in "$dir"/*.tar.gz "$dir"/*.tar.gz.gpg; do
            [ -f "$backup" ] || continue
            
            local name=$(basename "$backup" | sed 's/\.tar\.gz\(\.gpg\)\?$//')
            local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
            local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
            local encrypted=""
            
            [[ "$backup" == *.gpg ]] && encrypted=" [encrypted]"
            
            printf "%-50s %-10s %-20s %-15s%s\n" "$name" "$type" "$date" "$size" "$encrypted"
        done
    fi
}

count_backups() {
    local type="$1"
    local dir="$BACKUP_BASE_DIR/$type"
    local count=0
    
    if [ -d "$dir" ]; then
        count=$(ls -1 "$dir"/*.tar.gz "$dir"/*.tar.gz.gpg 2>/dev/null | wc -l)
    fi
    echo "$count"
}

echo "============================================================"
echo "n8n Backup Inventory"
echo "============================================================"
echo "Backup Location: $BACKUP_BASE_DIR"
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Summary
echo "Summary:"
echo "  Daily backups:   $(count_backups daily)"
echo "  Weekly backups:  $(count_backups weekly)"
echo "  Monthly backups: $(count_backups monthly)"
echo "  Manual backups:  $(count_backups manual)"

# Calculate total size
TOTAL_SIZE=$(du -sh "$BACKUP_BASE_DIR" 2>/dev/null | cut -f1)
echo "  Total size:      $TOTAL_SIZE"

# List backups based on type filter
print_header

case "$BACKUP_TYPE" in
    all)
        list_backups "daily"
        list_backups "weekly"
        list_backups "monthly"
        list_backups "manual"
        ;;
    daily|weekly|monthly|manual)
        list_backups "$BACKUP_TYPE"
        ;;
    *)
        echo "Unknown backup type: $BACKUP_TYPE"
        echo "Usage: $0 [all|daily|weekly|monthly|manual]"
        exit 1
        ;;
esac

echo ""

# Show last backup state
if [ -f "/var/lib/n8n/backup_state" ]; then
    echo "Last Backup Status:"
    cat /var/lib/n8n/backup_state | sed 's/^/  /'
fi
LIST_SCRIPT

    chmod +x "$BACKUP_SCRIPTS_DIR/list_backups.sh"
    log_info "Created list_backups.sh"
}

create_restore_backup_script() {
    log_info "Creating restore_backup.sh script..."
    
    cat > "$BACKUP_SCRIPTS_DIR/restore_backup.sh" << 'RESTORE_SCRIPT'
#!/bin/bash

# ==============================================================================
# n8n Restore Backup Script - Restores n8n from a backup point
# ==============================================================================

set -e

BACKUP_BASE_DIR="${BACKUP_LOCATION:-/opt/n8n/backups}"
BACKUP_LOG_FILE="/var/log/n8n_backup.log"
N8N_DATA_DIR="${N8N_DATA_DIR:-/opt/n8n}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

log_restore() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$BACKUP_LOG_FILE"
}

usage() {
    echo "Usage: $0 <backup_file> [--dry-run] [--skip-services]"
    echo ""
    echo "Options:"
    echo "  --dry-run        Show what would be restored without making changes"
    echo "  --skip-services  Don't stop/start n8n services"
    echo ""
    echo "Examples:"
    echo "  $0 /opt/n8n/backups/daily/n8n_backup_daily_20240101_020000.tar.gz"
    echo "  $0 n8n_backup_daily_20240101_020000  # Searches in backup directories"
    exit 1
}

find_backup() {
    local name="$1"
    
    # If it's a full path, use it directly
    if [ -f "$name" ]; then
        echo "$name"
        return 0
    fi
    
    # Search in backup directories
    for type in daily weekly monthly manual; do
        for ext in ".tar.gz" ".tar.gz.gpg"; do
            local path="$BACKUP_BASE_DIR/$type/${name}${ext}"
            if [ -f "$path" ]; then
                echo "$path"
                return 0
            fi
        done
    done
    
    return 1
}

# Parse arguments
BACKUP_INPUT=""
DRY_RUN=false
SKIP_SERVICES=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --skip-services) SKIP_SERVICES=true ;;
        -*) echo "Unknown option: $1"; usage ;;
        *) BACKUP_INPUT="$1" ;;
    esac
    shift
done

[ -z "$BACKUP_INPUT" ] && usage

# Find backup file
BACKUP_FILE=$(find_backup "$BACKUP_INPUT") || {
    log_restore "ERROR" "Backup not found: $BACKUP_INPUT"
    exit 1
}

log_restore "INFO" "Found backup: $BACKUP_FILE"

# Check if encrypted
IS_ENCRYPTED=false
[[ "$BACKUP_FILE" == *.gpg ]] && IS_ENCRYPTED=true

if [ "$IS_ENCRYPTED" = true ] && [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
    log_restore "ERROR" "Backup is encrypted but BACKUP_ENCRYPTION_KEY is not set"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract backup
log_restore "INFO" "Extracting backup..."
if [ "$IS_ENCRYPTED" = true ]; then
    gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" -d "$BACKUP_FILE" | tar -xzf - -C "$TEMP_DIR"
else
    tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"
fi

# Show manifest
if [ -f "$TEMP_DIR/MANIFEST" ]; then
    log_restore "INFO" "Backup manifest:"
    cat "$TEMP_DIR/MANIFEST" | sed 's/^/  /'
fi

# Dry run - just show what would be restored
if [ "$DRY_RUN" = true ]; then
    log_restore "INFO" "DRY RUN - Would restore the following:"
    [ -d "$TEMP_DIR/n8n_home" ] && echo "  - .n8n directory -> $N8N_DATA_DIR/.n8n"
    [ -d "$TEMP_DIR/files" ] && echo "  - files directory -> $N8N_DATA_DIR/files"
    [ -d "$TEMP_DIR/users" ] && echo "  - users directory -> $N8N_DATA_DIR/users"
    [ -d "$TEMP_DIR/docker" ] && echo "  - docker config -> $N8N_DATA_DIR/docker"
    [ -d "$TEMP_DIR/ssl" ] && echo "  - ssl certificates -> $N8N_DATA_DIR/ssl"
    [ -d "$TEMP_DIR/nginx" ] && echo "  - nginx config -> /etc/nginx"
    [ -f "$TEMP_DIR/redis_dump.rdb" ] && echo "  - redis data -> n8n-redis container"
    log_restore "INFO" "DRY RUN complete - no changes made"
    exit 0
fi

# Confirm restore
echo ""
echo "WARNING: This will overwrite existing n8n data!"
echo "Backup file: $BACKUP_FILE"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log_restore "INFO" "Restore cancelled by user"
    exit 0
fi

# Stop n8n services
if [ "$SKIP_SERVICES" = false ]; then
    log_restore "INFO" "Stopping n8n services..."
    cd "$N8N_DATA_DIR/docker" 2>/dev/null && docker compose down 2>/dev/null || true
    systemctl stop n8n-docker 2>/dev/null || true
fi

# Create backup of current state
CURRENT_BACKUP="$BACKUP_BASE_DIR/pre_restore_$(date '+%Y%m%d_%H%M%S')"
log_restore "INFO" "Creating backup of current state: $CURRENT_BACKUP"
mkdir -p "$CURRENT_BACKUP"
cp -rp "$N8N_DATA_DIR/.n8n" "$CURRENT_BACKUP/" 2>/dev/null || true
cp -rp "$N8N_DATA_DIR/files" "$CURRENT_BACKUP/" 2>/dev/null || true

# Restore data
log_restore "INFO" "Restoring data..."

if [ -d "$TEMP_DIR/n8n_home" ]; then
    rm -rf "$N8N_DATA_DIR/.n8n"
    cp -rp "$TEMP_DIR/n8n_home" "$N8N_DATA_DIR/.n8n"
    log_restore "INFO" "  Restored: .n8n directory"
fi

if [ -d "$TEMP_DIR/files" ]; then
    rm -rf "$N8N_DATA_DIR/files"
    cp -rp "$TEMP_DIR/files" "$N8N_DATA_DIR/files"
    log_restore "INFO" "  Restored: files directory"
fi

if [ -d "$TEMP_DIR/users" ]; then
    rm -rf "$N8N_DATA_DIR/users"
    cp -rp "$TEMP_DIR/users" "$N8N_DATA_DIR/users"
    log_restore "INFO" "  Restored: users directory"
fi

if [ -d "$TEMP_DIR/docker" ]; then
    cp -p "$TEMP_DIR/docker/"* "$N8N_DATA_DIR/docker/" 2>/dev/null || true
    log_restore "INFO" "  Restored: docker configuration"
fi

if [ -d "$TEMP_DIR/ssl" ]; then
    cp -rp "$TEMP_DIR/ssl/"* "$N8N_DATA_DIR/ssl/" 2>/dev/null || true
    log_restore "INFO" "  Restored: ssl certificates"
fi

if [ -d "$TEMP_DIR/nginx" ]; then
    cp -p "$TEMP_DIR/nginx/nginx.conf" /etc/nginx/ 2>/dev/null || true
    cp -rp "$TEMP_DIR/nginx/sites-available" /etc/nginx/ 2>/dev/null || true
    cp -rp "$TEMP_DIR/nginx/sites-enabled" /etc/nginx/ 2>/dev/null || true
    log_restore "INFO" "  Restored: nginx configuration"
fi

# Fix permissions
chown -R 1000:1000 "$N8N_DATA_DIR/.n8n" 2>/dev/null || true
chown -R 1000:1000 "$N8N_DATA_DIR/files" 2>/dev/null || true
chown -R 1000:1000 "$N8N_DATA_DIR/users" 2>/dev/null || true

# Start n8n services
if [ "$SKIP_SERVICES" = false ]; then
    log_restore "INFO" "Starting n8n services..."
    
    # Reload nginx if it was running
    systemctl reload nginx 2>/dev/null || true
    
    # Start n8n
    cd "$N8N_DATA_DIR/docker" && docker compose up -d 2>/dev/null || \
    systemctl start n8n-docker 2>/dev/null || true
    
    # Restore Redis data if available
    if [ -f "$TEMP_DIR/redis_dump.rdb" ]; then
        sleep 5  # Wait for Redis to start
        docker cp "$TEMP_DIR/redis_dump.rdb" n8n-redis:/data/dump.rdb 2>/dev/null && \
        docker exec n8n-redis redis-cli DEBUG RELOAD 2>/dev/null && \
        log_restore "INFO" "  Restored: redis data" || \
        log_restore "WARN" "  Failed to restore redis data"
    fi
fi

log_restore "INFO" "Restore completed successfully!"
log_restore "INFO" "Pre-restore backup saved to: $CURRENT_BACKUP"
RESTORE_SCRIPT

    chmod +x "$BACKUP_SCRIPTS_DIR/restore_backup.sh"
    log_info "Created restore_backup.sh"
}

create_verify_backup_script() {
    log_info "Creating verify_backup.sh script..."
    
    cat > "$BACKUP_SCRIPTS_DIR/verify_backup.sh" << 'VERIFY_SCRIPT'
#!/bin/bash

# ==============================================================================
# n8n Verify Backup Script - Verifies backup integrity and completeness
# ==============================================================================

BACKUP_BASE_DIR="${BACKUP_LOCATION:-/opt/n8n/backups}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

usage() {
    echo "Usage: $0 <backup_file|all> [--verbose]"
    echo ""
    echo "Options:"
    echo "  all        Verify all backups"
    echo "  --verbose  Show detailed output"
    exit 1
}

BACKUP_INPUT="$1"
VERBOSE=false
[ "$2" = "--verbose" ] && VERBOSE=true

[ -z "$BACKUP_INPUT" ] && usage

verify_single_backup() {
    local backup_file="$1"
    local name=$(basename "$backup_file")
    local status="OK"
    local details=""
    
    # Check if file exists
    if [ ! -f "$backup_file" ]; then
        echo "FAIL: $name - File not found"
        return 1
    fi
    
    # Check if encrypted
    local is_encrypted=false
    [[ "$backup_file" == *.gpg ]] && is_encrypted=true
    
    # Verify archive integrity
    if [ "$is_encrypted" = true ]; then
        if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
            echo "SKIP: $name - Encrypted, no key provided"
            return 2
        fi
        
        if gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" -d "$backup_file" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
            status="OK"
        else
            status="FAIL"
            details="Decryption or archive error"
        fi
    else
        if tar -tzf "$backup_file" >/dev/null 2>&1; then
            status="OK"
        else
            status="FAIL"
            details="Archive corruption detected"
        fi
    fi
    
    # Get file info
    local size=$(du -sh "$backup_file" 2>/dev/null | cut -f1)
    local date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d'.' -f1)
    
    if [ "$status" = "OK" ]; then
        echo "OK:   $name ($size)"
        
        if [ "$VERBOSE" = true ]; then
            echo "      Date: $date"
            echo "      Contents:"
            if [ "$is_encrypted" = true ]; then
                gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" -d "$backup_file" 2>/dev/null | tar -tzf - | head -20 | sed 's/^/        /'
            else
                tar -tzf "$backup_file" | head -20 | sed 's/^/        /'
            fi
        fi
        return 0
    else
        echo "FAIL: $name - $details"
        return 1
    fi
}

if [ "$BACKUP_INPUT" = "all" ]; then
    echo "============================================================"
    echo "n8n Backup Verification Report"
    echo "============================================================"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    TOTAL=0
    PASSED=0
    FAILED=0
    SKIPPED=0
    
    for type in daily weekly monthly manual; do
        dir="$BACKUP_BASE_DIR/$type"
        [ -d "$dir" ] || continue
        
        echo "[$type backups]"
        for backup in "$dir"/*.tar.gz "$dir"/*.tar.gz.gpg; do
            [ -f "$backup" ] || continue
            TOTAL=$((TOTAL + 1))
            
            if verify_single_backup "$backup"; then
                PASSED=$((PASSED + 1))
            else
                result=$?
                if [ $result -eq 2 ]; then
                    SKIPPED=$((SKIPPED + 1))
                else
                    FAILED=$((FAILED + 1))
                fi
            fi
        done
        echo ""
    done
    
    echo "============================================================"
    echo "Summary: $TOTAL total, $PASSED passed, $FAILED failed, $SKIPPED skipped"
    
    [ $FAILED -gt 0 ] && exit 1
    exit 0
else
    # Find and verify single backup
    if [ -f "$BACKUP_INPUT" ]; then
        verify_single_backup "$BACKUP_INPUT"
    else
        # Search in backup directories
        found=false
        for type in daily weekly monthly manual; do
            for ext in ".tar.gz" ".tar.gz.gpg"; do
                path="$BACKUP_BASE_DIR/$type/${BACKUP_INPUT}${ext}"
                if [ -f "$path" ]; then
                    verify_single_backup "$path"
                    found=true
                    break 2
                fi
            done
        done
        
        if [ "$found" = false ]; then
            echo "Backup not found: $BACKUP_INPUT"
            exit 1
        fi
    fi
fi
VERIFY_SCRIPT

    chmod +x "$BACKUP_SCRIPTS_DIR/verify_backup.sh"
    log_info "Created verify_backup.sh"
}

create_cleanup_backups_script() {
    log_info "Creating cleanup_backups.sh script..."
    
    cat > "$BACKUP_SCRIPTS_DIR/cleanup_backups.sh" << 'CLEANUP_SCRIPT'
#!/bin/bash

# ==============================================================================
# n8n Cleanup Backups Script - Manages backup retention and cleanup
# ==============================================================================

BACKUP_BASE_DIR="${BACKUP_LOCATION:-/opt/n8n/backups}"
BACKUP_LOG_FILE="/var/log/n8n_backup.log"

# Retention settings
BACKUP_RETENTION_DAILY="${BACKUP_RETENTION_DAILY:-7}"
BACKUP_RETENTION_WEEKLY="${BACKUP_RETENTION_WEEKLY:-4}"
BACKUP_RETENTION_MONTHLY="${BACKUP_RETENTION_MONTHLY:-3}"
BACKUP_MIN_KEEP="${BACKUP_MIN_KEEP:-3}"
BACKUP_STORAGE_THRESHOLD="${BACKUP_STORAGE_THRESHOLD:-85}"

# Email settings
BACKUP_EMAIL_NOTIFY="${BACKUP_EMAIL_NOTIFY:-true}"
EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-}"

# Options
DRY_RUN=false
FORCE=false

log_cleanup() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$BACKUP_LOG_FILE"
}

usage() {
    echo "Usage: $0 [--dry-run] [--force] [--type TYPE]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without making changes"
    echo "  --force      Skip minimum retention check"
    echo "  --type TYPE  Only cleanup specific type (daily|weekly|monthly)"
    exit 1
}

send_notification() {
    local subject="$1"
    local body="$2"
    
    if [ "$BACKUP_EMAIL_NOTIFY" = "true" ] && [ -n "$EMAIL_RECIPIENT" ]; then
        echo "$body" | mail -s "$subject" "$EMAIL_RECIPIENT" 2>/dev/null || true
    fi
}

get_disk_usage() {
    df "$BACKUP_BASE_DIR" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%'
}

count_backups() {
    local dir="$1"
    ls -1 "$dir"/*.tar.gz "$dir"/*.tar.gz.gpg 2>/dev/null | wc -l
}

cleanup_by_retention() {
    local type="$1"
    local retention="$2"
    local dir="$BACKUP_BASE_DIR/$type"
    
    [ -d "$dir" ] || return 0
    
    local count=$(count_backups "$dir")
    local to_delete=$((count - retention))
    
    if [ $to_delete -le 0 ]; then
        log_cleanup "INFO" "[$type] No cleanup needed ($count backups, retention: $retention)"
        return 0
    fi
    
    # Check minimum retention
    if [ "$FORCE" = false ] && [ $((count - to_delete)) -lt $BACKUP_MIN_KEEP ]; then
        log_cleanup "WARN" "[$type] Would go below minimum ($BACKUP_MIN_KEEP), skipping"
        return 0
    fi
    
    log_cleanup "INFO" "[$type] Cleaning up $to_delete old backups..."
    
    # Get oldest backups to delete (sorted by modification time)
    local deleted=0
    local deleted_size=0
    
    for backup in $(ls -1t "$dir"/*.tar.gz "$dir"/*.tar.gz.gpg 2>/dev/null | tail -$to_delete); do
        local name=$(basename "$backup")
        local size=$(du -sb "$backup" 2>/dev/null | cut -f1)
        
        if [ "$DRY_RUN" = true ]; then
            log_cleanup "INFO" "  [DRY RUN] Would delete: $name ($(du -sh "$backup" | cut -f1))"
        else
            rm -f "$backup"
            rm -f "${backup%.tar.gz*}.manifest"
            deleted=$((deleted + 1))
            deleted_size=$((deleted_size + size))
            log_cleanup "INFO" "  Deleted: $name"
        fi
    done
    
    if [ "$DRY_RUN" = false ] && [ $deleted -gt 0 ]; then
        local freed=$(numfmt --to=iec $deleted_size 2>/dev/null || echo "$deleted_size bytes")
        log_cleanup "INFO" "[$type] Deleted $deleted backups, freed $freed"
        echo "$type:$deleted:$freed"
    fi
}

cleanup_by_storage() {
    local current_usage=$(get_disk_usage)
    
    if [ -z "$current_usage" ]; then
        log_cleanup "WARN" "Could not determine disk usage"
        return 0
    fi
    
    if [ "$current_usage" -lt "$BACKUP_STORAGE_THRESHOLD" ]; then
        log_cleanup "INFO" "Disk usage ($current_usage%) below threshold ($BACKUP_STORAGE_THRESHOLD%)"
        return 0
    fi
    
    log_cleanup "WARN" "Disk usage ($current_usage%) exceeds threshold ($BACKUP_STORAGE_THRESHOLD%)"
    log_cleanup "INFO" "Initiating emergency cleanup..."
    
    # Delete oldest backups until below threshold
    local deleted=0
    
    while [ $(get_disk_usage) -ge $BACKUP_STORAGE_THRESHOLD ]; do
        # Find oldest backup across all types
        local oldest=""
        local oldest_time=9999999999
        
        for type in daily weekly monthly manual; do
            local dir="$BACKUP_BASE_DIR/$type"
            [ -d "$dir" ] || continue
            
            # Skip if at minimum retention
            if [ "$FORCE" = false ] && [ $(count_backups "$dir") -le $BACKUP_MIN_KEEP ]; then
                continue
            fi
            
            for backup in "$dir"/*.tar.gz "$dir"/*.tar.gz.gpg; do
                [ -f "$backup" ] || continue
                local mtime=$(stat -c %Y "$backup" 2>/dev/null)
                if [ -n "$mtime" ] && [ "$mtime" -lt "$oldest_time" ]; then
                    oldest_time=$mtime
                    oldest=$backup
                fi
            done
        done
        
        if [ -z "$oldest" ]; then
            log_cleanup "WARN" "No more backups to delete (minimum retention reached)"
            break
        fi
        
        if [ "$DRY_RUN" = true ]; then
            log_cleanup "INFO" "[DRY RUN] Would delete: $(basename $oldest)"
            break  # Exit loop in dry run mode
        else
            log_cleanup "INFO" "Deleting oldest backup: $(basename $oldest)"
            rm -f "$oldest"
            rm -f "${oldest%.tar.gz*}.manifest"
            deleted=$((deleted + 1))
        fi
    done
    
    if [ $deleted -gt 0 ]; then
        log_cleanup "INFO" "Emergency cleanup: deleted $deleted backups"
        log_cleanup "INFO" "Current disk usage: $(get_disk_usage)%"
    fi
}

# Parse arguments
CLEANUP_TYPE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --force) FORCE=true ;;
        --type) CLEANUP_TYPE="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

log_cleanup "INFO" "Starting backup cleanup..."
[ "$DRY_RUN" = true ] && log_cleanup "INFO" "DRY RUN MODE - No changes will be made"

CLEANUP_RESULTS=""

# Cleanup by retention policy
if [ -n "$CLEANUP_TYPE" ]; then
    case "$CLEANUP_TYPE" in
        daily) result=$(cleanup_by_retention "daily" "$BACKUP_RETENTION_DAILY") ;;
        weekly) result=$(cleanup_by_retention "weekly" "$BACKUP_RETENTION_WEEKLY") ;;
        monthly) result=$(cleanup_by_retention "monthly" "$BACKUP_RETENTION_MONTHLY") ;;
        *) echo "Invalid type: $CLEANUP_TYPE"; usage ;;
    esac
    [ -n "$result" ] && CLEANUP_RESULTS+="$result\n"
else
    result=$(cleanup_by_retention "daily" "$BACKUP_RETENTION_DAILY")
    [ -n "$result" ] && CLEANUP_RESULTS+="$result\n"
    
    result=$(cleanup_by_retention "weekly" "$BACKUP_RETENTION_WEEKLY")
    [ -n "$result" ] && CLEANUP_RESULTS+="$result\n"
    
    result=$(cleanup_by_retention "monthly" "$BACKUP_RETENTION_MONTHLY")
    [ -n "$result" ] && CLEANUP_RESULTS+="$result\n"
fi

# Cleanup by storage threshold
cleanup_by_storage

# Send summary notification
if [ -n "$CLEANUP_RESULTS" ] && [ "$DRY_RUN" = false ]; then
    SUMMARY="n8n Backup Cleanup Summary

Date: $(date '+%Y-%m-%d %H:%M:%S')
Disk Usage: $(get_disk_usage)%

Deleted Backups:
$(echo -e "$CLEANUP_RESULTS" | while IFS=: read type count size; do
    echo "  $type: $count backups ($size freed)"
done)"
    
    send_notification "[n8n] Backup Cleanup Complete" "$SUMMARY"
fi

log_cleanup "INFO" "Backup cleanup completed"
CLEANUP_SCRIPT

    chmod +x "$BACKUP_SCRIPTS_DIR/cleanup_backups.sh"
    log_info "Created cleanup_backups.sh"
}

setup_systemd_timers() {
    log_info "Setting up systemd timers for automated backups..."
    
    # Create backup service
    cat > /etc/systemd/system/n8n-backup.service << EOF
[Unit]
Description=n8n Backup Service
After=docker.service

[Service]
Type=oneshot
ExecStart=$BACKUP_SCRIPTS_DIR/backup_now.sh daily
Environment="BACKUP_LOCATION=$BACKUP_BASE_DIR"
Environment="N8N_DATA_DIR=$N8N_DATA_DIR"
Environment="BACKUP_ENCRYPTION_ENABLED=$BACKUP_ENCRYPTION_ENABLED"
Environment="BACKUP_EMAIL_NOTIFY=$BACKUP_EMAIL_NOTIFY"
Environment="EMAIL_RECIPIENT=${EMAIL_RECIPIENT:-}"
Environment="EMAIL_SENDER=${EMAIL_SENDER:-}"
StandardOutput=append:$BACKUP_LOG_FILE
StandardError=append:$BACKUP_LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Create backup timer
    cat > /etc/systemd/system/n8n-backup.timer << EOF
[Unit]
Description=n8n Daily Backup Timer

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    # Create cleanup service
    cat > /etc/systemd/system/n8n-backup-cleanup.service << EOF
[Unit]
Description=n8n Backup Cleanup Service
After=n8n-backup.service

[Service]
Type=oneshot
ExecStart=$BACKUP_SCRIPTS_DIR/cleanup_backups.sh
Environment="BACKUP_LOCATION=$BACKUP_BASE_DIR"
Environment="BACKUP_RETENTION_DAILY=$BACKUP_RETENTION_DAILY"
Environment="BACKUP_RETENTION_WEEKLY=$BACKUP_RETENTION_WEEKLY"
Environment="BACKUP_RETENTION_MONTHLY=$BACKUP_RETENTION_MONTHLY"
Environment="BACKUP_MIN_KEEP=$BACKUP_MIN_KEEP"
Environment="BACKUP_STORAGE_THRESHOLD=$BACKUP_STORAGE_THRESHOLD"
Environment="BACKUP_EMAIL_NOTIFY=$BACKUP_EMAIL_NOTIFY"
Environment="EMAIL_RECIPIENT=${EMAIL_RECIPIENT:-}"
StandardOutput=append:$BACKUP_LOG_FILE
StandardError=append:$BACKUP_LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Create cleanup timer
    cat > /etc/systemd/system/n8n-backup-cleanup.timer << EOF
[Unit]
Description=n8n Backup Cleanup Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Create weekly backup service
    cat > /etc/systemd/system/n8n-backup-weekly.service << EOF
[Unit]
Description=n8n Weekly Backup Service
After=docker.service

[Service]
Type=oneshot
ExecStart=$BACKUP_SCRIPTS_DIR/backup_now.sh weekly
Environment="BACKUP_LOCATION=$BACKUP_BASE_DIR"
Environment="N8N_DATA_DIR=$N8N_DATA_DIR"
Environment="BACKUP_ENCRYPTION_ENABLED=$BACKUP_ENCRYPTION_ENABLED"
Environment="BACKUP_EMAIL_NOTIFY=$BACKUP_EMAIL_NOTIFY"
Environment="EMAIL_RECIPIENT=${EMAIL_RECIPIENT:-}"
StandardOutput=append:$BACKUP_LOG_FILE
StandardError=append:$BACKUP_LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Create weekly backup timer (runs on Sundays at 3 AM)
    cat > /etc/systemd/system/n8n-backup-weekly.timer << EOF
[Unit]
Description=n8n Weekly Backup Timer

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Create monthly backup service
    cat > /etc/systemd/system/n8n-backup-monthly.service << EOF
[Unit]
Description=n8n Monthly Backup Service
After=docker.service

[Service]
Type=oneshot
ExecStart=$BACKUP_SCRIPTS_DIR/backup_now.sh monthly
Environment="BACKUP_LOCATION=$BACKUP_BASE_DIR"
Environment="N8N_DATA_DIR=$N8N_DATA_DIR"
Environment="BACKUP_ENCRYPTION_ENABLED=$BACKUP_ENCRYPTION_ENABLED"
Environment="BACKUP_EMAIL_NOTIFY=$BACKUP_EMAIL_NOTIFY"
Environment="EMAIL_RECIPIENT=${EMAIL_RECIPIENT:-}"
StandardOutput=append:$BACKUP_LOG_FILE
StandardError=append:$BACKUP_LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Create monthly backup timer (runs on 1st of month at 4 AM)
    cat > /etc/systemd/system/n8n-backup-monthly.timer << EOF
[Unit]
Description=n8n Monthly Backup Timer

[Timer]
OnCalendar=*-*-01 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable timers
    systemctl daemon-reload
    systemctl enable n8n-backup.timer
    systemctl enable n8n-backup-cleanup.timer
    systemctl enable n8n-backup-weekly.timer
    systemctl enable n8n-backup-monthly.timer
    
    systemctl start n8n-backup.timer
    systemctl start n8n-backup-cleanup.timer
    systemctl start n8n-backup-weekly.timer
    systemctl start n8n-backup-monthly.timer
    
    log_info "Systemd timers configured and enabled"
}

setup_netdata_monitoring() {
    log_info "Setting up Netdata backup monitoring..."
    
    # Create Netdata custom chart for backup monitoring
    local netdata_charts_dir="/usr/libexec/netdata/charts.d"
    local netdata_plugin_dir="/etc/netdata/python.d"
    
    # Create backup status script for Netdata
    mkdir -p "$netdata_charts_dir"
    
    cat > "$netdata_charts_dir/n8n_backup.chart.sh" << 'NETDATA_CHART'
#!/bin/bash
# Netdata chart for n8n backup monitoring

BACKUP_STATE_FILE="/var/lib/n8n/backup_state"
BACKUP_BASE_DIR="${BACKUP_LOCATION:-/opt/n8n/backups}"

# Chart definitions
n8n_backup_status() {
    echo "CHART n8n.backup_status '' 'n8n Backup Status' 'status' n8n n8n.backup_status line 100000 10"
    echo "DIMENSION last_backup_age 'Age (hours)' absolute 1 1"
    echo "DIMENSION backup_count 'Total Backups' absolute 1 1"
}

n8n_backup_size() {
    echo "CHART n8n.backup_size '' 'n8n Backup Size' 'MB' n8n n8n.backup_size area 100001 10"
    echo "DIMENSION daily 'Daily' absolute 1 1048576"
    echo "DIMENSION weekly 'Weekly' absolute 1 1048576"
    echo "DIMENSION monthly 'Monthly' absolute 1 1048576"
}

# Data collection
collect_data() {
    local now=$(date +%s)
    local last_backup_time=0
    local backup_count=0
    
    # Get last backup time
    if [ -f "$BACKUP_STATE_FILE" ]; then
        local last_time=$(grep "last_backup_time=" "$BACKUP_STATE_FILE" | cut -d= -f2)
        if [ -n "$last_time" ]; then
            last_backup_time=$(date -d "$last_time" +%s 2>/dev/null || echo 0)
        fi
    fi
    
    local age_hours=0
    if [ $last_backup_time -gt 0 ]; then
        age_hours=$(( (now - last_backup_time) / 3600 ))
    fi
    
    # Count backups
    for type in daily weekly monthly manual; do
        if [ -d "$BACKUP_BASE_DIR/$type" ]; then
            backup_count=$((backup_count + $(ls -1 "$BACKUP_BASE_DIR/$type"/*.tar.gz* 2>/dev/null | wc -l)))
        fi
    done
    
    echo "BEGIN n8n.backup_status"
    echo "SET last_backup_age = $age_hours"
    echo "SET backup_count = $backup_count"
    echo "END"
    
    # Backup sizes
    local daily_size=0
    local weekly_size=0
    local monthly_size=0
    
    [ -d "$BACKUP_BASE_DIR/daily" ] && daily_size=$(du -sb "$BACKUP_BASE_DIR/daily" 2>/dev/null | cut -f1)
    [ -d "$BACKUP_BASE_DIR/weekly" ] && weekly_size=$(du -sb "$BACKUP_BASE_DIR/weekly" 2>/dev/null | cut -f1)
    [ -d "$BACKUP_BASE_DIR/monthly" ] && monthly_size=$(du -sb "$BACKUP_BASE_DIR/monthly" 2>/dev/null | cut -f1)
    
    echo "BEGIN n8n.backup_size"
    echo "SET daily = ${daily_size:-0}"
    echo "SET weekly = ${weekly_size:-0}"
    echo "SET monthly = ${monthly_size:-0}"
    echo "END"
}

# Main
case "$1" in
    charts) n8n_backup_status; n8n_backup_size ;;
    *) collect_data ;;
esac
NETDATA_CHART

    chmod +x "$netdata_charts_dir/n8n_backup.chart.sh" 2>/dev/null || true
    
    # Create Netdata health alert for backup age
    local netdata_health_dir="/etc/netdata/health.d"
    mkdir -p "$netdata_health_dir"
    
    cat > "$netdata_health_dir/n8n_backup.conf" << 'NETDATA_HEALTH'
# n8n Backup Health Alerts

alarm: n8n_backup_age_warning
on: n8n.backup_status
lookup: max -1m of last_backup_age
units: hours
every: 5m
warn: $this > 26
crit: $this > 50
info: Time since last n8n backup
to: sysadmin

alarm: n8n_backup_disk_usage
on: disk_space./opt/n8n/backups
lookup: max -1m of used_percentage
units: %
every: 5m
warn: $this > 80
crit: $this > 90
info: n8n backup storage usage
to: sysadmin
NETDATA_HEALTH

    # Restart Netdata to load new charts
    systemctl restart netdata 2>/dev/null || true
    
    log_info "Netdata backup monitoring configured"
}

# ==============================================================================
# Main Configuration Function
# ==============================================================================

configure_backup() {
    log_section "n8n Backup Configuration"
    
    log_info "Starting backup configuration..."
    log_info "Backup location: $BACKUP_BASE_DIR"
    log_info "Retention: $BACKUP_RETENTION_DAILY daily, $BACKUP_RETENTION_WEEKLY weekly, $BACKUP_RETENTION_MONTHLY monthly"
    
    # Setup directories
    setup_backup_directories
    
    # Ensure scripts directory exists
    ensure_directory "$BACKUP_SCRIPTS_DIR" "755"
    
    # Create management scripts
    create_backup_now_script
    create_list_backups_script
    create_restore_backup_script
    create_verify_backup_script
    create_cleanup_backups_script
    
    # Setup automated backups
    setup_systemd_timers
    
    # Setup monitoring
    if [ "${NETDATA_ENABLED:-true}" = "true" ]; then
        setup_netdata_monitoring
    fi
    
    log_info "Backup configuration completed successfully"
    log_info ""
    log_info "Backup scripts installed to: $BACKUP_SCRIPTS_DIR"
    log_info "  - backup_now.sh     : Create manual backup"
    log_info "  - list_backups.sh   : List available backups"
    log_info "  - restore_backup.sh : Restore from backup"
    log_info "  - verify_backup.sh  : Verify backup integrity"
    log_info "  - cleanup_backups.sh: Manage backup retention"
    log_info ""
    log_info "Automated backup schedule:"
    log_info "  - Daily:   02:00 AM"
    log_info "  - Weekly:  Sunday 03:00 AM"
    log_info "  - Monthly: 1st of month 04:00 AM"
    log_info "  - Cleanup: 03:00 AM daily"
}

# Run configuration if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_backup
fi
