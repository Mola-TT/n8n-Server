#!/bin/bash

# ==============================================================================
# Geographic IP Blocking Script for n8n Server - Milestone 9
# ==============================================================================
# This script implements optional country-based IP blocking using GeoIP
# databases and ipset for efficient firewall rules
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

# Geographic blocking settings
GEO_BLOCKING_ENABLED="${GEO_BLOCKING_ENABLED:-false}"
GEO_BLOCK_COUNTRIES="${GEO_BLOCK_COUNTRIES:-}"
GEO_ALLOW_COUNTRIES="${GEO_ALLOW_COUNTRIES:-}"
GEO_MODE="${GEO_MODE:-blocklist}"  # blocklist or allowlist

# GeoIP database settings
GEOIP_DB_DIR="/usr/share/GeoIP"
GEOIP_DB_URL="https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz"
GEOIP_UPDATE_SCHEDULE="${GEOIP_UPDATE_SCHEDULE:-0 4 * * 0}"  # Weekly on Sunday

# ipset settings
IPSET_NAME="geo_blocked"
IPSET_ALLOW_NAME="geo_allowed"

# Zone files directory
ZONE_FILES_DIR="/etc/n8n/geo_zones"

# Log file
GEO_LOG_FILE="/var/log/n8n_geo_blocking.log"

# ==============================================================================
# Logging Functions
# ==============================================================================

log_geo() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO") log_info "$message" ;;
        "WARN") log_warn "$message" ;;
        "ERROR") log_error "$message" ;;
        "DEBUG") log_debug "$message" ;;
    esac
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$GEO_LOG_FILE"
}

# ==============================================================================
# Installation Functions
# ==============================================================================

install_dependencies() {
    log_info "Installing geographic blocking dependencies..."
    
    # Install required packages
    local packages="ipset iptables-persistent geoip-bin geoip-database wget"
    
    if ! execute_silently "apt-get update"; then
        log_error "Failed to update package index"
        return 1
    fi
    
    for pkg in $packages; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log_info "Installing $pkg..."
            if ! execute_silently "apt-get install -y $pkg"; then
                log_warn "Failed to install $pkg"
            fi
        fi
    done
    
    log_info "Dependencies installed"
    return 0
}

# ==============================================================================
# GeoIP Database Functions
# ==============================================================================

download_geoip_database() {
    log_info "Downloading GeoIP database..."
    
    mkdir -p "$GEOIP_DB_DIR"
    
    local temp_file="/tmp/geoip.dat.gz"
    
    if wget -q -O "$temp_file" "$GEOIP_DB_URL"; then
        gunzip -f "$temp_file"
        mv /tmp/geoip.dat "$GEOIP_DB_DIR/GeoIP.dat"
        log_info "GeoIP database downloaded successfully"
        return 0
    else
        log_warn "Failed to download GeoIP database from primary source"
        log_info "Using system GeoIP database if available"
        return 1
    fi
}

setup_geoip_update_cron() {
    log_info "Setting up GeoIP database auto-update..."
    
    local update_script="/opt/n8n/scripts/update_geoip.sh"
    
    cat > "$update_script" << 'EOF'
#!/bin/bash
# GeoIP Database Update Script

GEOIP_DB_DIR="/usr/share/GeoIP"
GEOIP_DB_URL="https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz"
LOG_FILE="/var/log/n8n_geo_blocking.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log "Starting GeoIP database update..."

if wget -q -O /tmp/geoip.dat.gz "$GEOIP_DB_URL"; then
    gunzip -f /tmp/geoip.dat.gz
    mv /tmp/geoip.dat "$GEOIP_DB_DIR/GeoIP.dat"
    log "GeoIP database updated successfully"
    
    # Reload geo-blocking rules
    if [[ -x /opt/n8n/scripts/reload_geo_rules.sh ]]; then
        /opt/n8n/scripts/reload_geo_rules.sh
    fi
else
    log "Failed to update GeoIP database"
fi
EOF

    chmod +x "$update_script"
    
    # Create cron job
    echo "${GEOIP_UPDATE_SCHEDULE} root $update_script" > /etc/cron.d/n8n-geoip-update
    
    log_info "GeoIP auto-update cron job created"
    return 0
}

# ==============================================================================
# Country Zone File Functions
# ==============================================================================

download_country_zones() {
    log_info "Downloading country IP zone files..."
    
    mkdir -p "$ZONE_FILES_DIR"
    
    # Download zone files from ipdeny.com (free, regularly updated)
    local base_url="https://www.ipdeny.com/ipblocks/data/countries"
    
    # Get list of countries to download
    local countries=""
    if [[ "$GEO_MODE" == "blocklist" && -n "$GEO_BLOCK_COUNTRIES" ]]; then
        countries="$GEO_BLOCK_COUNTRIES"
    elif [[ "$GEO_MODE" == "allowlist" && -n "$GEO_ALLOW_COUNTRIES" ]]; then
        # For allowlist, we need all countries except allowed ones
        # This is handled differently - we'll download common high-risk countries
        countries="cn,ru,kp,ir,sy,cu"
    fi
    
    if [[ -z "$countries" ]]; then
        log_info "No countries specified for geo-blocking"
        return 0
    fi
    
    # Download each country zone file
    IFS=',' read -ra COUNTRY_ARRAY <<< "$countries"
    for country in "${COUNTRY_ARRAY[@]}"; do
        country=$(echo "$country" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
        local zone_file="$ZONE_FILES_DIR/${country}.zone"
        
        log_info "Downloading zone file for: $country"
        if wget -q -O "$zone_file" "${base_url}/${country}.zone"; then
            log_info "Downloaded: $zone_file"
        else
            log_warn "Failed to download zone file for: $country"
        fi
    done
    
    log_info "Country zone files downloaded"
    return 0
}

# ==============================================================================
# ipset Functions
# ==============================================================================

create_ipset() {
    log_info "Creating ipset for geo-blocking..."
    
    # Remove existing ipset if present
    ipset destroy "$IPSET_NAME" 2>/dev/null || true
    
    # Create new ipset (hash:net for IP ranges)
    if ipset create "$IPSET_NAME" hash:net family inet hashsize 65536 maxelem 1000000; then
        log_info "Created ipset: $IPSET_NAME"
    else
        log_error "Failed to create ipset"
        return 1
    fi
    
    return 0
}

populate_ipset() {
    log_info "Populating ipset with blocked IP ranges..."
    
    local count=0
    
    # Get list of zone files to process
    for zone_file in "$ZONE_FILES_DIR"/*.zone; do
        if [[ -f "$zone_file" ]]; then
            local country=$(basename "$zone_file" .zone)
            log_info "Adding IPs from: $country"
            
            while IFS= read -r ip_range; do
                # Skip empty lines and comments
                [[ -z "$ip_range" || "$ip_range" =~ ^# ]] && continue
                
                if ipset add "$IPSET_NAME" "$ip_range" 2>/dev/null; then
                    count=$((count + 1))
                fi
            done < "$zone_file"
        fi
    done
    
    log_info "Added $count IP ranges to ipset"
    return 0
}

# ==============================================================================
# iptables Functions
# ==============================================================================

setup_iptables_rules() {
    log_info "Setting up iptables rules for geo-blocking..."
    
    # Check if ipset exists
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        log_error "ipset $IPSET_NAME does not exist"
        return 1
    fi
    
    # Remove existing geo-blocking rules (if any)
    iptables -D INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null || true
    
    # Add geo-blocking rule
    # This rule drops packets from IPs in the geo_blocked ipset
    if iptables -I INPUT -m set --match-set "$IPSET_NAME" src -j DROP; then
        log_info "iptables geo-blocking rule added"
    else
        log_error "Failed to add iptables rule"
        return 1
    fi
    
    # Optionally allow specific ports even from blocked countries (e.g., webhooks)
    if [[ "${GEO_ALLOW_WEBHOOKS:-false}" == "true" ]]; then
        log_info "Allowing webhook traffic from blocked countries..."
        iptables -I INPUT -p tcp --dport 443 -m string --string "/webhook" --algo bm -j ACCEPT 2>/dev/null || true
    fi
    
    # Save iptables rules
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save
        log_info "iptables rules saved"
    elif command -v iptables-save &>/dev/null; then
        iptables-save > /etc/iptables/rules.v4
        log_info "iptables rules saved to /etc/iptables/rules.v4"
    fi
    
    return 0
}

# ==============================================================================
# Systemd Service Functions
# ==============================================================================

create_geo_blocking_service() {
    log_info "Creating geo-blocking systemd service..."
    
    # Create reload script
    local reload_script="/opt/n8n/scripts/reload_geo_rules.sh"
    
    cat > "$reload_script" << 'EOF'
#!/bin/bash
# Reload geo-blocking rules

IPSET_NAME="geo_blocked"
ZONE_FILES_DIR="/etc/n8n/geo_zones"
LOG_FILE="/var/log/n8n_geo_blocking.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log "Reloading geo-blocking rules..."

# Flush and recreate ipset
ipset flush "$IPSET_NAME" 2>/dev/null || ipset create "$IPSET_NAME" hash:net family inet hashsize 65536 maxelem 1000000

# Repopulate from zone files
count=0
for zone_file in "$ZONE_FILES_DIR"/*.zone; do
    if [[ -f "$zone_file" ]]; then
        while IFS= read -r ip_range; do
            [[ -z "$ip_range" || "$ip_range" =~ ^# ]] && continue
            ipset add "$IPSET_NAME" "$ip_range" 2>/dev/null && count=$((count + 1))
        done < "$zone_file"
    fi
done

log "Reloaded $count IP ranges"
EOF

    chmod +x "$reload_script"
    
    # Create systemd service
    cat > /etc/systemd/system/n8n-geo-blocking.service << EOF
[Unit]
Description=n8n Geographic IP Blocking
After=network.target
Before=nginx.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/n8n/scripts/reload_geo_rules.sh
ExecReload=/opt/n8n/scripts/reload_geo_rules.sh

[Install]
WantedBy=multi-user.target
EOF

    # Enable service
    execute_silently "systemctl daemon-reload"
    execute_silently "systemctl enable n8n-geo-blocking.service"
    
    log_info "Geo-blocking service created and enabled"
    return 0
}

# ==============================================================================
# Management Functions
# ==============================================================================

create_management_script() {
    log_info "Creating geo-blocking management script..."
    
    local manage_script="/opt/n8n/scripts/manage_geo_blocking.sh"
    
    cat > "$manage_script" << 'MANAGE_SCRIPT'
#!/bin/bash

# ==============================================================================
# Geo-Blocking Management Script for n8n Server - Milestone 9
# ==============================================================================

IPSET_NAME="geo_blocked"
ZONE_FILES_DIR="/etc/n8n/geo_zones"
LOG_FILE="/var/log/n8n_geo_blocking.log"

show_status() {
    echo "=== Geo-Blocking Status ==="
    
    if ipset list "$IPSET_NAME" &>/dev/null; then
        local count=$(ipset list "$IPSET_NAME" | grep -c "^[0-9]" || echo "0")
        echo "Status: ACTIVE"
        echo "Blocked IP ranges: $count"
        echo ""
        echo "Blocked countries:"
        for zone in "$ZONE_FILES_DIR"/*.zone; do
            if [[ -f "$zone" ]]; then
                local country=$(basename "$zone" .zone | tr '[:lower:]' '[:upper:]')
                local ranges=$(wc -l < "$zone")
                echo "  - $country: $ranges ranges"
            fi
        done
    else
        echo "Status: INACTIVE"
    fi
}

add_country() {
    local country="$1"
    country=$(echo "$country" | tr '[:upper:]' '[:lower:]')
    
    echo "Adding country: $country"
    
    # Download zone file
    wget -q -O "$ZONE_FILES_DIR/${country}.zone" "https://www.ipdeny.com/ipblocks/data/countries/${country}.zone"
    
    if [[ -f "$ZONE_FILES_DIR/${country}.zone" ]]; then
        # Add to ipset
        while IFS= read -r ip_range; do
            [[ -z "$ip_range" || "$ip_range" =~ ^# ]] && continue
            ipset add "$IPSET_NAME" "$ip_range" 2>/dev/null
        done < "$ZONE_FILES_DIR/${country}.zone"
        
        echo "Added country: $country"
    else
        echo "Failed to download zone file for: $country"
    fi
}

remove_country() {
    local country="$1"
    country=$(echo "$country" | tr '[:upper:]' '[:lower:]')
    
    echo "Removing country: $country"
    
    if [[ -f "$ZONE_FILES_DIR/${country}.zone" ]]; then
        # Remove from ipset
        while IFS= read -r ip_range; do
            [[ -z "$ip_range" || "$ip_range" =~ ^# ]] && continue
            ipset del "$IPSET_NAME" "$ip_range" 2>/dev/null
        done < "$ZONE_FILES_DIR/${country}.zone"
        
        rm -f "$ZONE_FILES_DIR/${country}.zone"
        echo "Removed country: $country"
    else
        echo "Country not in blocklist: $country"
    fi
}

check_ip() {
    local ip="$1"
    
    if ipset test "$IPSET_NAME" "$ip" 2>/dev/null; then
        echo "IP $ip is BLOCKED"
        
        # Try to determine country
        if command -v geoiplookup &>/dev/null; then
            geoiplookup "$ip"
        fi
    else
        echo "IP $ip is NOT blocked"
    fi
}

whitelist_ip() {
    local ip="$1"
    
    # Remove from blocked set
    ipset del "$IPSET_NAME" "$ip" 2>/dev/null
    
    # Add to whitelist file
    echo "$ip" >> /etc/n8n/geo_whitelist.txt
    sort -u -o /etc/n8n/geo_whitelist.txt /etc/n8n/geo_whitelist.txt
    
    echo "Whitelisted IP: $ip"
}

show_help() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status              Show geo-blocking status"
    echo "  add <country>       Add country to blocklist (2-letter code)"
    echo "  remove <country>    Remove country from blocklist"
    echo "  check <ip>          Check if IP is blocked"
    echo "  whitelist <ip>      Whitelist specific IP"
    echo "  reload              Reload all rules"
    echo "  enable              Enable geo-blocking"
    echo "  disable             Disable geo-blocking"
    echo ""
    echo "Examples:"
    echo "  $0 add cn           Block China"
    echo "  $0 add ru           Block Russia"
    echo "  $0 check 8.8.8.8    Check if Google DNS is blocked"
}

case "${1:-}" in
    status)
        show_status
        ;;
    add)
        add_country "$2"
        ;;
    remove)
        remove_country "$2"
        ;;
    check)
        check_ip "$2"
        ;;
    whitelist)
        whitelist_ip "$2"
        ;;
    reload)
        /opt/n8n/scripts/reload_geo_rules.sh
        ;;
    enable)
        systemctl start n8n-geo-blocking.service
        iptables -I INPUT -m set --match-set "$IPSET_NAME" src -j DROP
        echo "Geo-blocking enabled"
        ;;
    disable)
        iptables -D INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
        echo "Geo-blocking disabled (rules remain loaded)"
        ;;
    *)
        show_help
        ;;
esac
MANAGE_SCRIPT

    chmod +x "$manage_script"
    log_info "Management script created: $manage_script"
    return 0
}

# ==============================================================================
# Main Setup Function
# ==============================================================================

setup_geo_blocking() {
    log_info "Starting geographic IP blocking setup..."
    
    # Check if geo-blocking is enabled
    if [[ "${GEO_BLOCKING_ENABLED,,}" != "true" ]]; then
        log_info "Geographic blocking is disabled (GEO_BLOCKING_ENABLED=false)"
        return 0
    fi
    
    # Create log file
    mkdir -p "$(dirname "$GEO_LOG_FILE")"
    touch "$GEO_LOG_FILE"
    
    # Install dependencies
    install_dependencies || log_warn "Some dependencies may be missing"
    
    # Download GeoIP database
    download_geoip_database || log_warn "GeoIP database download had issues"
    
    # Setup auto-update
    setup_geoip_update_cron
    
    # Download country zone files
    download_country_zones
    
    # Create and populate ipset
    create_ipset || return 1
    populate_ipset
    
    # Setup iptables rules
    setup_iptables_rules || return 1
    
    # Create systemd service
    create_geo_blocking_service
    
    # Create management script
    create_management_script
    
    log_info "Geographic IP blocking setup completed!"
    log_info "Use /opt/n8n/scripts/manage_geo_blocking.sh to manage blocked countries"
    
    return 0
}

# Export functions
export -f setup_geo_blocking

# Run setup if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_geo_blocking "$@"
fi
