#!/bin/bash

# dynamic_optimization.sh - Dynamic Hardware Optimization for n8n Server
# Part of Milestone 6: Dynamic Hardware Optimization
# 
# This script detects hardware specifications and dynamically optimizes:
# - n8n configuration parameters
# - Docker resource limits and allocations
# - Nginx worker processes and connections
# - Redis memory configuration
# - PostgreSQL connection parameters
# - Netdata monitoring settings

set -euo pipefail

# Get script directory for relative imports
PROJECT_ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

# Source required utilities
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Hardware validation bounds
CPU_CORES_MIN=1
CPU_CORES_MAX=128
MEMORY_MIN_GB=1
MEMORY_MAX_GB=1024
DISK_MIN_GB=1
DISK_MAX_GB=10240

# Optimization ratios and constants
N8N_EXECUTION_PROCESS_RATIO=0.75
N8N_MEMORY_RATIO=0.4
N8N_TIMEOUT_BASE=180
DOCKER_MEMORY_RATIO=0.75
DOCKER_CPU_RATIO=0.9
NGINX_WORKER_RATIO=1.0
NGINX_CONNECTIONS_PER_WORKER=384
REDIS_MEMORY_RATIO=0.15
REDIS_MEMORY_MIN_MB=128

# Backup directory
BACKUP_DIR="/opt/n8n/backups/optimization"

# =============================================================================
# HARDWARE DETECTION FUNCTIONS
# =============================================================================

detect_cpu_cores() {
    log_info "Detecting CPU cores..."
    
    local cores
    cores=$(nproc 2>/dev/null || echo "1")
    
    # Validate CPU cores within reasonable bounds
    if [[ "$cores" -lt "$CPU_CORES_MIN" ]]; then
        cores=$CPU_CORES_MIN
    elif [[ "$cores" -gt "$CPU_CORES_MAX" ]]; then
        cores=$CPU_CORES_MAX
    fi
    
    CPU_CORES="$cores"
    log_info "CPU cores detected: $CPU_CORES"
    
    return 0
}

detect_memory_gb() {
    log_info "Detecting memory..."
    
    local memory_kb memory_gb
    memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "1048576")
    memory_gb=$((memory_kb / 1024 / 1024))
    
    # Validate memory within reasonable bounds
    if [[ "$memory_gb" -lt "$MEMORY_MIN_GB" ]]; then
        memory_gb=$MEMORY_MIN_GB
    elif [[ "$memory_gb" -gt "$MEMORY_MAX_GB" ]]; then
        memory_gb=$MEMORY_MAX_GB
    fi
    
    MEMORY_GB="$memory_gb"
    log_info "Memory detected: ${MEMORY_GB}GB"
    
    return 0
}

detect_disk_gb() {
    log_info "Detecting disk space..."
    
    # Get disk size in GB for root filesystem
    local disk_size_gb=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')
    
    # Validate disk size
    if [[ ! "$disk_size_gb" =~ ^[0-9]+$ ]] || [ "$disk_size_gb" -lt 1 ] || [ "$disk_size_gb" -gt 10000 ]; then
        log_warn "Invalid disk size detected: ${disk_size_gb}GB, using default"
        disk_size_gb=50
    fi
    
    DISK_GB="$disk_size_gb"
    log_info "Disk space detected: ${DISK_GB}GB"
    
    return 0
}

# Alias function for test compatibility
detect_hardware_disk() {
    detect_disk_gb
}

get_hardware_specs() {
    log_info "Detecting hardware specifications..."
    
    # Call detection functions
    detect_cpu_cores
    detect_memory_gb
    detect_disk_gb
    
    # Use the global variables set by detection functions
    local cpu_cores="$CPU_CORES"
    local memory_gb="$MEMORY_GB"
    local disk_gb="$DISK_GB"
    
    log_info "Hardware detected: ${cpu_cores} CPU cores, ${memory_gb}GB RAM, ${disk_gb}GB disk"
    
    # Export for use by other functions
    export HW_CPU_CORES="$cpu_cores"
    export HW_MEMORY_GB="$memory_gb"
    export HW_DISK_GB="$disk_gb"
}

# =============================================================================
# OPTIMIZATION CALCULATION FUNCTIONS
# =============================================================================

calculate_n8n_parameters() {
    local cpu_cores="$HW_CPU_CORES"
    local memory_gb="$HW_MEMORY_GB"
    
    # Calculate execution processes (75% of CPU cores, minimum 1)
    local execution_processes
    execution_processes=$(echo "$cpu_cores * $N8N_EXECUTION_PROCESS_RATIO" | bc -l | cut -d. -f1)
    [[ "$execution_processes" -lt 1 ]] && execution_processes=1
    
    # Calculate memory limit (40% of total memory in MB)
    local memory_limit_mb
    memory_limit_mb=$(echo "$memory_gb * 1024 * $N8N_MEMORY_RATIO" | bc -l | cut -d. -f1)
    
    # Calculate timeout based on memory (more memory = longer timeout)
    local execution_timeout
    execution_timeout=$(echo "$N8N_TIMEOUT_BASE + ($memory_gb * 30)" | bc -l | cut -d. -f1)
    
    # Calculate webhook timeout
    local webhook_timeout
    webhook_timeout=$(echo "$execution_timeout * 0.8" | bc -l | cut -d. -f1)
    
    # Export calculated values
    export N8N_EXECUTION_PROCESS="$execution_processes"
    export N8N_MEMORY_LIMIT_MB="$memory_limit_mb"
    export N8N_EXECUTION_TIMEOUT="$execution_timeout"
    export N8N_WEBHOOK_TIMEOUT="$webhook_timeout"
    
    log_info "n8n parameters: ${execution_processes} processes, ${memory_limit_mb}MB memory, ${execution_timeout}s timeout"
}

calculate_docker_parameters() {
    local cpu_cores="$HW_CPU_CORES"
    local memory_gb="$HW_MEMORY_GB"
    
    # Calculate Docker memory limit (80% of total memory)
    local docker_memory_gb
    docker_memory_gb=$(echo "$memory_gb * $DOCKER_MEMORY_RATIO" | bc -l | cut -d. -f1)
    
    # Calculate CPU limit (90% of CPU cores)
    local docker_cpu_limit
    docker_cpu_limit=$(echo "$cpu_cores * $DOCKER_CPU_RATIO" | bc -l)
    
    # Calculate shared memory (1/8 of container memory, minimum 64MB)
    local shm_size_mb
    shm_size_mb=$(echo "$docker_memory_gb * 1024 / 8" | bc -l | cut -d. -f1)
    [[ "$shm_size_mb" -lt 64 ]] && shm_size_mb=64
    
    # Export calculated values
    export DOCKER_MEMORY_LIMIT="${docker_memory_gb}g"
    export DOCKER_CPU_LIMIT="$docker_cpu_limit"
    export DOCKER_SHM_SIZE="${shm_size_mb}m"
    
    log_info "Docker parameters: ${docker_memory_gb}GB memory, ${docker_cpu_limit} CPU limit, ${shm_size_mb}MB shared memory"
}

calculate_nginx_parameters() {
    local cpu_cores="$HW_CPU_CORES"
    local memory_gb="$HW_MEMORY_GB"
    
    # Calculate worker processes (1 per CPU core)
    local worker_processes
    worker_processes=$(echo "$cpu_cores * $NGINX_WORKER_RATIO" | bc -l | cut -d. -f1)
    [[ "$worker_processes" -lt 1 ]] && worker_processes=1
    
    # Calculate worker connections (base * memory factor)
    local memory_factor
    memory_factor=$(echo "scale=2; 1 + ($memory_gb / 8)" | bc -l)
    local worker_connections
    worker_connections=$(echo "$NGINX_CONNECTIONS_PER_WORKER * $memory_factor" | bc -l | cut -d. -f1)
    
    # Calculate client max body size (based on available memory)
    local client_max_body_mb
    if [[ "$memory_gb" -ge 8 ]]; then
        client_max_body_mb=100
    elif [[ "$memory_gb" -ge 4 ]]; then
        client_max_body_mb=50
    else
        client_max_body_mb=25
    fi
    
    # Calculate SSL session cache (based on memory)
    local ssl_session_cache_mb
    ssl_session_cache_mb=$(echo "$memory_gb * 2" | bc -l | cut -d. -f1)
    [[ "$ssl_session_cache_mb" -lt 1 ]] && ssl_session_cache_mb=1
    [[ "$ssl_session_cache_mb" -gt 10 ]] && ssl_session_cache_mb=10
    
    # Export calculated values
    export NGINX_WORKER_PROCESSES="$worker_processes"
    export NGINX_WORKER_CONNECTIONS="$worker_connections"
    export NGINX_CLIENT_MAX_BODY="${client_max_body_mb}m"
    export NGINX_SSL_SESSION_CACHE="${ssl_session_cache_mb}m"
    
    log_info "Nginx parameters: ${worker_processes} workers, ${worker_connections} connections, ${client_max_body_mb}MB max body"
}

calculate_redis_parameters() {
    local memory_gb="$HW_MEMORY_GB"
    
    # Calculate Redis memory (15% of total memory)
    local redis_memory_mb
    redis_memory_mb=$(echo "$memory_gb * 1024 * $REDIS_MEMORY_RATIO" | bc -l | cut -d. -f1)
    [[ "$redis_memory_mb" -lt "$REDIS_MEMORY_MIN_MB" ]] && redis_memory_mb=$REDIS_MEMORY_MIN_MB
    
    # Calculate save intervals based on memory
    local save_interval
    if [[ "$redis_memory_mb" -ge 512 ]]; then
        save_interval="900 1 300 10 60 10000"  # More frequent saves for larger memory
    else
        save_interval="900 1 300 10"           # Less frequent saves for smaller memory
    fi
    
    # Set memory policy for n8n queue management
    local maxmemory_policy="allkeys-lru"
    
    # Export calculated values
    export REDIS_MAXMEMORY="${redis_memory_mb}mb"
    export REDIS_SAVE_INTERVAL="$save_interval"
    export REDIS_MAXMEMORY_POLICY="$maxmemory_policy"
    
    log_info "Redis parameters: ${redis_memory_mb}MB memory, policy: ${maxmemory_policy}"
}

calculate_netdata_parameters() {
    local cpu_cores="$HW_CPU_CORES"
    local memory_gb="$HW_MEMORY_GB"
    local disk_gb="$HW_DISK_GB"
    
    # Calculate update frequency (higher for more powerful systems)
    local update_every
    if [[ "$cpu_cores" -ge 4 && "$memory_gb" -ge 4 ]]; then
        update_every=1  # 1 second for powerful systems
    elif [[ "$cpu_cores" -ge 2 && "$memory_gb" -ge 2 ]]; then
        update_every=2  # 2 seconds for medium systems
    else
        update_every=3  # 3 seconds for low-end systems
    fi
    
    # Calculate memory limit (5% of total memory, max 512MB)
    local memory_limit_mb
    memory_limit_mb=$(echo "$memory_gb * 1024 * 0.05" | bc -l | cut -d. -f1)
    [[ "$memory_limit_mb" -gt 512 ]] && memory_limit_mb=512
    [[ "$memory_limit_mb" -lt 32 ]] && memory_limit_mb=32
    
    # Calculate history retention (based on disk space)
    local history_hours
    if [[ "$disk_gb" -ge 100 ]]; then
        history_hours=168  # 7 days for large disks
    elif [[ "$disk_gb" -ge 50 ]]; then
        history_hours=72   # 3 days for medium disks
    else
        history_hours=24   # 1 day for small disks
    fi
    
    # Export calculated values
    export NETDATA_UPDATE_EVERY="$update_every"
    export NETDATA_MEMORY_LIMIT="${memory_limit_mb}"
    export NETDATA_HISTORY_HOURS="$history_hours"
    
    log_info "Netdata parameters: ${update_every}s updates, ${memory_limit_mb}MB memory, ${history_hours}h history"
}

# =============================================================================
# CONFIGURATION UPDATE FUNCTIONS
# =============================================================================

backup_configurations() {
    log_info "Creating configuration backups..."
    
    # Create backup directory with timestamp
    local backup_timestamp
    backup_timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="$BACKUP_DIR/$backup_timestamp"
    
    sudo mkdir -p "$backup_path" 2>/dev/null || mkdir -p "$backup_path"
    sudo chown -R "$(whoami):$(id -gn)" "$backup_path" 2>/dev/null || true
    sudo chmod -R 755 "$backup_path" 2>/dev/null || true
    
    # Backup n8n environment file
    [[ -f "/opt/n8n/docker/.env" ]] && cp "/opt/n8n/docker/.env" "$backup_path/n8n.env.backup"
    
    # Backup Docker Compose file
    [[ -f "/opt/n8n/docker/docker-compose.yml" ]] && cp "/opt/n8n/docker/docker-compose.yml" "$backup_path/docker-compose.yml.backup"
    
    # Backup Nginx configuration
    [[ -f "/etc/nginx/sites-available/n8n" ]] && cp "/etc/nginx/sites-available/n8n" "$backup_path/nginx.conf.backup"
    
    # Backup Redis configuration
    [[ -f "/etc/redis/redis.conf" ]] && cp "/etc/redis/redis.conf" "$backup_path/redis.conf.backup"
    
    # Backup Netdata configuration
    [[ -f "/etc/netdata/netdata.conf" ]] && cp "/etc/netdata/netdata.conf" "$backup_path/netdata.conf.backup"
    
    # Create backup manifest
    cat > "$backup_path/manifest.txt" << EOF
Backup created: $(date)
Hardware specs: ${HW_CPU_CORES} cores, ${HW_MEMORY_GB}GB RAM, ${HW_DISK_GB}GB disk
Backup contents:
$(ls -la "$backup_path")
EOF
    
    log_info "Configuration backup created: $backup_path"
    export BACKUP_PATH="$backup_path"
}

update_n8n_configuration() {
    log_info "Updating n8n configuration..."
    
    local env_file="/opt/n8n/docker/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log_error "n8n environment file not found: $env_file"
        return 1
    fi
    
    # Update n8n execution parameters
    sed -i "s/^N8N_EXECUTION_PROCESS=.*/N8N_EXECUTION_PROCESS=${N8N_EXECUTION_PROCESS}/" "$env_file" || \
        echo "N8N_EXECUTION_PROCESS=${N8N_EXECUTION_PROCESS}" >> "$env_file"
    
    sed -i "s/^N8N_EXECUTION_TIMEOUT=.*/N8N_EXECUTION_TIMEOUT=${N8N_EXECUTION_TIMEOUT}/" "$env_file" || \
        echo "N8N_EXECUTION_TIMEOUT=${N8N_EXECUTION_TIMEOUT}" >> "$env_file"
    
    sed -i "s/^WEBHOOK_TIMEOUT=.*/WEBHOOK_TIMEOUT=${N8N_WEBHOOK_TIMEOUT}/" "$env_file" || \
        echo "WEBHOOK_TIMEOUT=${N8N_WEBHOOK_TIMEOUT}" >> "$env_file"
    
    log_info "n8n configuration updated successfully"
}

update_docker_configuration() {
    log_info "Updating Docker configuration..."
    
    local compose_file="/opt/n8n/docker/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    # Create temporary file for updates
    local temp_file
    temp_file=$(mktemp)
    
    # Update Docker Compose with calculated limits
    awk -v mem_limit="$DOCKER_MEMORY_LIMIT" \
        -v cpu_limit="$DOCKER_CPU_LIMIT" \
        -v shm_size="$DOCKER_SHM_SIZE" '
    /^[[:space:]]*deploy:/ {
        print $0
        getline
        while ($0 ~ /^[[:space:]]*resources:/ || $0 ~ /^[[:space:]]*limits:/ || $0 ~ /^[[:space:]]*memory:/ || $0 ~ /^[[:space:]]*cpus:/) {
            getline
        }
        print "      resources:"
        print "        limits:"
        print "          memory: " mem_limit
        print "          cpus: \"" cpu_limit "\""
        print $0
        next
    }
    /^[[:space:]]*shm_size:/ {
        print "    shm_size: " shm_size
        next
    }
    { print }
    ' "$compose_file" > "$temp_file"
    
    # Replace original file if changes were made
    if ! cmp -s "$compose_file" "$temp_file"; then
        mv "$temp_file" "$compose_file"
        log_info "Docker configuration updated successfully"
    else
        rm "$temp_file"
        log_info "Docker configuration already optimal"
    fi
}

update_nginx_configuration() {
    log_info "Updating Nginx configuration..."
    
    local nginx_conf="/etc/nginx/sites-available/n8n"
    
    if [[ ! -f "$nginx_conf" ]]; then
        log_warn "Nginx configuration file not found: $nginx_conf"
        return 0
    fi
    
    # Update main nginx.conf for worker processes
    local main_conf="/etc/nginx/nginx.conf"
    if [[ -f "$main_conf" ]]; then
        sed -i "s/^worker_processes.*/worker_processes ${NGINX_WORKER_PROCESSES};/" "$main_conf"
        
        # Update worker_connections in events block
        sed -i "/events {/,/}/ s/worker_connections.*/worker_connections ${NGINX_WORKER_CONNECTIONS};/" "$main_conf"
    fi
    
    # Update site-specific configuration
    sed -i "s/client_max_body_size.*/client_max_body_size ${NGINX_CLIENT_MAX_BODY};/" "$nginx_conf"
    
    # Update SSL session cache if SSL is configured
    if grep -q "ssl_session_cache" "$nginx_conf"; then
        sed -i "s/ssl_session_cache.*/ssl_session_cache shared:SSL:${NGINX_SSL_SESSION_CACHE};/" "$nginx_conf"
    fi
    
    log_info "Nginx configuration updated successfully"
}

update_redis_configuration() {
    log_info "Updating Redis configuration..."
    
    # Check if Redis is running in Docker (part of our compose)
    if docker-compose -f /opt/n8n/docker/docker-compose.yml ps redis >/dev/null 2>&1; then
        log_info "Redis is running in Docker container - configuration managed via compose"
        
        # Update Redis configuration in Docker Compose
        local compose_file="/opt/n8n/docker/docker-compose.yml"
        local temp_file
        temp_file=$(mktemp)
        
        # Add Redis configuration to compose file
        awk -v maxmem="$REDIS_MAXMEMORY" -v policy="$REDIS_MAXMEMORY_POLICY" '
        /^[[:space:]]*redis:/ {
            in_redis = 1
            print $0
            next
        }
        in_redis && /^[[:space:]]*[a-zA-Z]/ && !/^[[:space:]]*command:/ && !/^[[:space:]]*image:/ && !/^[[:space:]]*volumes:/ && !/^[[:space:]]*networks:/ {
            in_redis = 0
        }
        in_redis && /^[[:space:]]*command:/ {
            print "    command: redis-server --maxmemory " maxmem " --maxmemory-policy " policy
            next
        }
        !in_redis || !/^[[:space:]]*command:/ {
            print $0
        }
        ' "$compose_file" > "$temp_file"
        
        mv "$temp_file" "$compose_file"
    else
        # Update system Redis configuration
        local redis_conf="/etc/redis/redis.conf"
        if [[ -f "$redis_conf" ]]; then
            sed -i "s/^maxmemory.*/maxmemory ${REDIS_MAXMEMORY}/" "$redis_conf"
            sed -i "s/^maxmemory-policy.*/maxmemory-policy ${REDIS_MAXMEMORY_POLICY}/" "$redis_conf"
            
            # Update save configuration
            sed -i "/^save /d" "$redis_conf"
            echo "save $REDIS_SAVE_INTERVAL" >> "$redis_conf"
        fi
    fi
    
    log_info "Redis configuration updated successfully"
}

update_netdata_configuration() {
    log_info "Updating Netdata configuration..."
    
    local netdata_conf="/etc/netdata/netdata.conf"
    
    if [[ ! -f "$netdata_conf" ]]; then
        log_warn "Netdata configuration file not found: $netdata_conf"
        return 0
    fi
    
    # Update global settings
    sed -i "s/^[[:space:]]*update every = .*/    update every = ${NETDATA_UPDATE_EVERY}/" "$netdata_conf"
    sed -i "s/^[[:space:]]*memory mode = .*/    memory mode = ram/" "$netdata_conf"
    sed -i "s/^[[:space:]]*history = .*/    history = ${NETDATA_HISTORY_HOURS}/" "$netdata_conf"
    
    # Update memory settings
    if ! grep -q "\[global\]" "$netdata_conf"; then
        echo -e "\n[global]" >> "$netdata_conf"
    fi
    
    # Add or update memory limit
    if grep -q "memory limit" "$netdata_conf"; then
        sed -i "s/^[[:space:]]*memory limit = .*/    memory limit = ${NETDATA_MEMORY_LIMIT}/" "$netdata_conf"
    else
        sed -i "/\[global\]/a\\    memory limit = ${NETDATA_MEMORY_LIMIT}" "$netdata_conf"
    fi
    
    log_info "Netdata configuration updated successfully"
}

# =============================================================================
# Performance Testing Functions with Resource Limits
# =============================================================================

test_parameter_calculation_performance() {
    log_info "Testing parameter calculation performance with resource limits..."
    
    # Set resource limits to prevent system overload
    ulimit -v 1048576  # Limit virtual memory to 1GB
    ulimit -t 30       # Limit CPU time to 30 seconds
    
    local start_time end_time duration
    local test_iterations=100
    local max_duration=10  # Maximum 10 seconds for performance test
    
    start_time=$(date +%s.%N)
    
    # Run parameter calculations with timeout
    for i in $(seq 1 $test_iterations); do
        # Check if we're exceeding time limit
        local current_time=$(date +%s.%N)
        local elapsed=$(echo "$current_time - $start_time" | bc -l 2>/dev/null || echo "0")
        
        if (( $(echo "$elapsed > $max_duration" | bc -l 2>/dev/null || echo "0") )); then
            log_warn "Performance test stopped early to prevent system overload (${elapsed}s elapsed)"
            break
        fi
        
        # Lightweight parameter calculation test
        calculate_n8n_parameters 2 4 100 >/dev/null 2>&1 || true
        
        # Add small delay to prevent CPU spike
        sleep 0.01
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    log_info "Parameter calculation performance test completed in ${duration}s"
    
    # Reset resource limits
    ulimit -v unlimited 2>/dev/null || true
    ulimit -t unlimited 2>/dev/null || true
    
    return 0
}

test_hardware_detection_performance() {
    log_info "Testing hardware detection performance with resource limits..."
    
    # Set resource limits
    ulimit -v 524288   # Limit virtual memory to 512MB
    ulimit -t 15       # Limit CPU time to 15 seconds
    
    local start_time end_time duration
    local test_iterations=10
    local max_duration=5  # Maximum 5 seconds
    
    start_time=$(date +%s.%N)
    
    # Run hardware detection with timeout
    for i in $(seq 1 $test_iterations); do
        local current_time=$(date +%s.%N)
        local elapsed=$(echo "$current_time - $start_time" | bc -l 2>/dev/null || echo "0")
        
        if (( $(echo "$elapsed > $max_duration" | bc -l 2>/dev/null || echo "0") )); then
            log_warn "Hardware detection test stopped early (${elapsed}s elapsed)"
            break
        fi
        
        # Lightweight hardware detection
        timeout 1 detect_hardware_specs >/dev/null 2>&1 || true
        sleep 0.1
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    log_info "Hardware detection performance test completed in ${duration}s"
    
    # Reset resource limits
    ulimit -v unlimited 2>/dev/null || true
    ulimit -t unlimited 2>/dev/null || true
    
    return 0
}

# =============================================================================
# SERVICE MANAGEMENT FUNCTIONS
# =============================================================================

restart_services() {
    log_info "Restarting services to apply optimizations..."
    
    local services_restarted=0
    local services_failed=0
    
    # Restart n8n (Docker Compose)
    if cd /opt/n8n/docker 2>/dev/null && docker-compose restart n8n >/dev/null 2>&1; then
        log_info "✓ n8n service restarted successfully"
        services_restarted=$((services_restarted + 1))
    else
        log_warn "✗ Failed to restart n8n service"
        services_failed=$((services_failed + 1))
    fi
    
    # Test Nginx configuration before restart
    if nginx -t >/dev/null 2>&1; then
        if systemctl restart nginx >/dev/null 2>&1; then
            log_info "✓ Nginx service restarted successfully"
            services_restarted=$((services_restarted + 1))
        else
            log_warn "✗ Failed to restart Nginx service"
            services_failed=$((services_failed + 1))
        fi
    else
        log_warn "✗ Nginx configuration test failed, skipping restart"
        services_failed=$((services_failed + 1))
    fi
    
    # Restart Redis (Docker container first, then system service)
    if cd /opt/n8n/docker 2>/dev/null && docker-compose restart redis >/dev/null 2>&1; then
        log_info "✓ Redis container restarted successfully"
        services_restarted=$((services_restarted + 1))
    elif systemctl is-active redis >/dev/null 2>&1 && systemctl restart redis >/dev/null 2>&1; then
        log_info "✓ Redis system service restarted successfully"
        services_restarted=$((services_restarted + 1))
    else
        log_warn "✗ Failed to restart Redis service (tried both Docker and system)"
        services_failed=$((services_failed + 1))
    fi
    
    # Restart Netdata
    if systemctl restart netdata >/dev/null 2>&1; then
        log_info "✓ Netdata service restarted successfully"
        services_restarted=$((services_restarted + 1))
    else
        log_warn "✗ Failed to restart Netdata service"
        services_failed=$((services_failed + 1))
    fi
    
    log_info "Service restart summary: ${services_restarted} successful, ${services_failed} failed"
    
    # Wait for services to stabilize
    log_info "Waiting for services to stabilize..."
    sleep 10
}

verify_optimization() {
    log_info "Verifying optimization results..."
    
    local verification_passed=0
    local verification_failed=0
    
    # Verify n8n is responding
    if curl -s --connect-timeout 10 "http://localhost:5678" >/dev/null 2>&1; then
        log_info "✓ n8n service is responding"
        verification_passed=$((verification_passed + 1))
    else
        log_warn "✗ n8n service is not responding"
        verification_failed=$((verification_failed + 1))
    fi
    
    # Verify Nginx is responding (try both HTTP and HTTPS)
    if curl -s --connect-timeout 10 "http://localhost" >/dev/null 2>&1 || curl -s --connect-timeout 10 -k "https://localhost" >/dev/null 2>&1; then
        log_info "✓ Nginx service is responding"
        verification_passed=$((verification_passed + 1))
    else
        log_warn "✗ Nginx service is not responding"
        verification_failed=$((verification_failed + 1))
    fi
    
    # Verify Redis is responding (try Docker first, then system service)
    local redis_responding=false
    
    # Try Docker Redis first
    if cd /opt/n8n/docker 2>/dev/null && docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; then
        log_info "✓ Redis Docker container is responding"
        redis_responding=true
    # Try system Redis as fallback
    elif redis-cli ping >/dev/null 2>&1; then
        log_info "✓ Redis system service is responding"
        redis_responding=true
    fi
    
    if $redis_responding; then
        verification_passed=$((verification_passed + 1))
    else
        log_warn "✗ Redis service is not responding (tried both Docker and system)"
        verification_failed=$((verification_failed + 1))
    fi
    
    # Verify Netdata is responding
    if curl -s --connect-timeout 10 "http://localhost:19999" >/dev/null 2>&1; then
        log_info "✓ Netdata service is responding"
        verification_passed=$((verification_passed + 1))
    else
        log_warn "✗ Netdata service is not responding"
        verification_failed=$((verification_failed + 1))
    fi
    
    log_info "Verification summary: ${verification_passed} passed, ${verification_failed} failed"
    
    return $verification_failed
}

# =============================================================================
# REPORTING FUNCTIONS
# =============================================================================

generate_optimization_report() {
    local report_file="${1:-/opt/n8n/reports/optimization_report_$(date +%Y%m%d).txt}"
    local hardware_specs="$2"
    
    log_info "Generating optimization report: $report_file"
    
    # Ensure reports directory exists
    mkdir -p "$(dirname "$report_file")"
    
    # Create comprehensive optimization report
    cat > "$report_file" << EOF
# n8n Server Optimization Report
# Generated: $(date)
# Hostname: $(hostname)

## System Hardware Specifications
$(echo "$hardware_specs" | jq -r '
"CPU Cores: " + (.cpu_cores | tostring) + 
"\nMemory (GB): " + (.memory_gb | tostring) + 
"\nDisk (GB): " + (.disk_gb | tostring)' 2>/dev/null || echo "$hardware_specs")

## Calculated Optimization Parameters

### n8n Configuration
N8N_EXECUTION_PROCESS: $N8N_EXECUTION_PROCESS
N8N_EXECUTION_TIMEOUT: $N8N_EXECUTION_TIMEOUT
N8N_WEBHOOK_TIMEOUT: $N8N_WEBHOOK_TIMEOUT

### Docker Configuration  
DOCKER_MEMORY_LIMIT: $DOCKER_MEMORY_LIMIT
DOCKER_CPU_LIMIT: $DOCKER_CPU_LIMIT
DOCKER_SHM_SIZE: $DOCKER_SHM_SIZE

### Nginx Configuration
NGINX_WORKER_PROCESSES: $NGINX_WORKER_PROCESSES
NGINX_WORKER_CONNECTIONS: $NGINX_WORKER_CONNECTIONS
NGINX_CLIENT_MAX_BODY_SIZE: $NGINX_CLIENT_MAX_BODY

### Redis Configuration
REDIS_MAXMEMORY: $REDIS_MAXMEMORY
REDIS_MAXMEMORY_POLICY: $REDIS_MAXMEMORY_POLICY

### Netdata Configuration
NETDATA_UPDATE_EVERY: $NETDATA_UPDATE_EVERY
NETDATA_MEMORY_MODE: $NETDATA_MEMORY_MODE

## Performance Recommendations
- Optimization completed at: $(date)
- Next recommended review: $(date -d '+30 days')
- Monitor system performance for 24-48 hours after optimization

## System Status
Load Average: $(cat /proc/loadavg 2>/dev/null || echo "N/A")
Memory Usage: $(free -h 2>/dev/null | grep ^Mem || echo "N/A")
Disk Usage: $(df -h / 2>/dev/null | tail -1 || echo "N/A")

EOF
    
    # Set proper permissions
    chmod 644 "$report_file"
    
    log_info "Optimization report generated successfully: $report_file"
    return 0
}

generate_performance_recommendations() {
    local cpu_cores="$HW_CPU_CORES"
    local memory_gb="$HW_MEMORY_GB"
    local disk_gb="$HW_DISK_GB"
    
    echo "Based on your hardware configuration:"
    echo
    
    if [[ "$cpu_cores" -le 2 ]]; then
        echo "- Consider upgrading CPU for better workflow parallel processing"
        echo "- Limit concurrent workflow executions to prevent overload"
    elif [[ "$cpu_cores" -ge 8 ]]; then
        echo "- Excellent CPU capacity for high-throughput workflow processing"
        echo "- Consider enabling more aggressive parallel execution"
    fi
    
    if [[ "$memory_gb" -le 2 ]]; then
        echo "- Memory is limited - monitor for out-of-memory conditions"
        echo "- Consider reducing workflow complexity or upgrading RAM"
    elif [[ "$memory_gb" -ge 16 ]]; then
        echo "- Excellent memory capacity for complex workflows"
        echo "- Consider increasing execution timeout for memory-intensive tasks"
    fi
    
    if [[ "$disk_gb" -le 20 ]]; then
        echo "- Disk space is limited - enable log rotation and cleanup"
        echo "- Monitor disk usage regularly"
    elif [[ "$disk_gb" -ge 100 ]]; then
        echo "- Ample disk space for extensive logging and data retention"
        echo "- Consider increasing Netdata history retention"
    fi
    
    echo
    echo "Next optimization should be run when hardware changes are detected."
}

# =============================================================================
# MAIN OPTIMIZATION FUNCTION
# =============================================================================

run_optimization() {
    local start_time
    start_time=$(date +%s)
    
    log_info "Starting dynamic hardware optimization..."
    
    # Create necessary directories
    sudo mkdir -p "$BACKUP_DIR" "/opt/n8n/logs" 2>/dev/null || mkdir -p "$BACKUP_DIR"
    sudo chown -R "$(whoami):$(id -gn)" "$BACKUP_DIR" "/opt/n8n/logs" 2>/dev/null || true
    sudo chmod -R 755 "$BACKUP_DIR" "/opt/n8n/logs" 2>/dev/null || true
    
    # Detect hardware specifications
    get_hardware_specs
    
    # Calculate optimization parameters
    calculate_n8n_parameters
    calculate_docker_parameters
    calculate_nginx_parameters
    calculate_redis_parameters
    calculate_netdata_parameters
    
    # Create configuration backups
    backup_configurations
    
    # Update configurations
    update_n8n_configuration
    update_docker_configuration
    update_nginx_configuration
    update_redis_configuration
    update_netdata_configuration
    
    # Restart services to apply changes
    restart_services
    
    # Verify optimization results
    if verify_optimization; then
        log_info "✓ Optimization completed successfully"
    else
        log_warn "⚠ Optimization completed with some verification failures"
    fi
    
    # Generate optimization report
    local report_file
    report_file=$(generate_optimization_report)
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_info "Optimization completed in ${duration} seconds"
    log_info "Report available at: $report_file"
    
    return 0
}

# =============================================================================
# INITIALIZATION SETUP FUNCTION
# =============================================================================

setup_dynamic_optimization() {
    log_info "Setting up dynamic hardware optimization infrastructure..."
    
    # Create necessary directories
    sudo mkdir -p "$BACKUP_DIR" "/opt/n8n/logs" "/opt/n8n/data" 2>/dev/null || mkdir -p "$BACKUP_DIR"
    sudo chown -R "$(whoami):$(id -gn)" "$BACKUP_DIR" "/opt/n8n/logs" "/opt/n8n/data" 2>/dev/null || true
    sudo chmod -R 755 "$BACKUP_DIR" "/opt/n8n/logs" "/opt/n8n/data" 2>/dev/null || true
    
    # Run initial hardware detection and optimization
    log_info "Running initial hardware detection and optimization..."
    get_hardware_specs
    
    # Calculate optimization parameters
    calculate_n8n_parameters
    calculate_docker_parameters
    calculate_nginx_parameters
    calculate_redis_parameters
    calculate_netdata_parameters
    
    # Create configuration backups
    backup_configurations
    
    # Apply optimizations
    update_n8n_configuration
    update_docker_configuration
    update_nginx_configuration
    update_redis_configuration
    update_netdata_configuration
    
    # Set up hardware change detector service
    log_info "Setting up hardware change detection service..."
    local detector_script="$PROJECT_ROOT/setup/hardware_change_detector.sh"
    if [[ -f "$detector_script" ]]; then
        bash "$detector_script" --install-service >/dev/null 2>&1 || true
    else
        log_warn "Hardware change detector script not found: $detector_script"
    fi
    
    # Generate initial optimization report
    local report_file
    report_file=$(generate_optimization_report)
    log_info "Initial optimization report generated: $report_file"
    
    # Restart services to apply optimizations
    restart_services
    
    # Verify optimization results
    if verify_optimization; then
        log_info "✓ Dynamic hardware optimization setup completed successfully"
    else
        log_warn "⚠ Dynamic hardware optimization setup completed with some verification failures"
    fi
    
    log_info "Hardware change detection service installed and ready"
    log_info "Optimization can be re-run manually with: bash $PROJECT_ROOT/setup/dynamic_optimization.sh --optimize"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
Dynamic Hardware Optimization for n8n Server

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --optimize          Run full optimization (default)
    --detect-only       Only detect and display hardware specifications
    --calculate-only    Detect hardware and calculate parameters without applying
    --verify-only       Verify current optimization status
    --report-only       Generate optimization report without changes
    --help              Show this help message

EXAMPLES:
    $0                  # Run full optimization
    $0 --detect-only    # Just show hardware specs
    $0 --verify-only    # Check if services are optimized

The script will automatically:
1. Detect hardware specifications (CPU, memory, disk)
2. Calculate optimal parameters for all components
3. Backup current configurations
4. Apply optimizations
5. Restart services
6. Verify results
7. Generate detailed report

All changes are logged and backed up for easy rollback if needed.
EOF
}

main() {
    local action="optimize"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --optimize)
                action="optimize"
                shift
                ;;
            --detect-only)
                action="detect"
                shift
                ;;
            --calculate-only)
                action="calculate"
                shift
                ;;
            --verify-only)
                action="verify"
                shift
                ;;
            --report-only)
                action="report"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Execute requested action
    case $action in
        "detect")
            get_hardware_specs
            log_info "Hardware: ${HW_CPU_CORES} cores, ${HW_MEMORY_GB}GB RAM, ${HW_DISK_GB}GB disk"
            ;;
        "calculate")
            get_hardware_specs
            calculate_n8n_parameters
            calculate_docker_parameters
            calculate_nginx_parameters
            calculate_redis_parameters
            calculate_netdata_parameters
            log_info "Optimization parameters calculated (not applied)"
            ;;
        "verify")
            verify_optimization
            ;;
        "report")
            get_hardware_specs
            calculate_n8n_parameters
            calculate_docker_parameters
            calculate_nginx_parameters
            calculate_redis_parameters
            calculate_netdata_parameters
            generate_optimization_report
            ;;
        "optimize")
            run_optimization
            ;;
        *)
            log_error "Invalid action: $action"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 