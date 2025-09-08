#!/bin/bash

# Cross-Server Setup Configuration Script
# Configures secure communication between web app server and n8n server

source "$(dirname "$0")/../lib/logger.sh"
source "$(dirname "$0")/../lib/utilities.sh"

# Load environment variables
load_environment() {
    if [[ -f "$(dirname "$0")/../conf/user.env" ]]; then
        source "$(dirname "$0")/../conf/user.env"
    fi
    if [[ -f "$(dirname "$0")/../conf/default.env" ]]; then
        source "$(dirname "$0")/../conf/default.env"
    fi
}

# Configure API authentication
configure_api_authentication() {
    log_info "Configuring API authentication for cross-server communication..."
    
    # Create API authentication configuration
    cat > /opt/n8n/user-configs/api-auth.json << EOF
{
  "apiAuthentication": {
    "enabled": true,
    "methods": {
      "jwt": {
        "enabled": true,
        "secret": "$(openssl rand -base64 32)",
        "algorithm": "HS256",
        "expiresIn": "1h",
        "issuer": "${N8N_DOMAIN:-https://n8n.example.com}",
        "audience": "${WEBAPP_DOMAIN:-https://app.example.com}"
      },
      "apiKey": {
        "enabled": true,
        "header": "X-API-Key",
        "keys": {
          "webapp": "$(openssl rand -hex 32)",
          "admin": "$(openssl rand -hex 32)"
        }
      },
      "oauth2": {
        "enabled": false,
        "clientId": "${OAUTH_CLIENT_ID:-}",
        "clientSecret": "${OAUTH_CLIENT_SECRET:-}",
        "tokenUrl": "${OAUTH_TOKEN_URL:-}",
        "scope": "n8n:read n8n:write"
      }
    },
    "rateLimiting": {
      "enabled": true,
      "windowMs": 900000,
      "maxRequests": 1000,
      "skipSuccessfulRequests": false
    }
  }
}
EOF
    
    log_pass "API authentication configured"
}

# Setup webhook forwarding
setup_webhook_forwarding() {
    log_info "Setting up webhook forwarding and callback mechanisms..."
    
    # Create webhook forwarding configuration
    cat > /opt/n8n/user-configs/webhook-config.json << EOF
{
  "webhookForwarding": {
    "enabled": true,
    "forwardTo": "${WEBAPP_WEBHOOK_URL:-https://app.example.com/webhooks/n8n}",
    "authentication": {
      "type": "bearer",
      "token": "$(openssl rand -base64 32)"
    },
    "retry": {
      "enabled": true,
      "maxRetries": 3,
      "retryDelay": 5000,
      "exponentialBackoff": true
    },
    "filters": {
      "allowedEvents": [
        "workflow.completed",
        "workflow.failed",
        "execution.started",
        "execution.finished",
        "user.created",
        "user.updated"
      ],
      "excludeEvents": [
        "workflow.saved",
        "node.updated"
      ]
    }
  }
}
EOF

    # Create webhook forwarding script
    cat > /opt/n8n/scripts/webhook-forwarder.js << 'EOF'
// Webhook Forwarder for Cross-Server Communication

const https = require('https');
const crypto = require('crypto');
const fs = require('fs');

class WebhookForwarder {
    constructor(configPath = '/opt/n8n/user-configs/webhook-config.json') {
        this.config = this.loadConfig(configPath);
        this.queue = [];
        this.processing = false;
        this.init();
    }

    loadConfig(configPath) {
        try {
            const configData = fs.readFileSync(configPath, 'utf8');
            return JSON.parse(configData).webhookForwarding;
        } catch (error) {
            console.error('Failed to load webhook config:', error);
            return this.getDefaultConfig();
        }
    }

    getDefaultConfig() {
        return {
            enabled: true,
            forwardTo: 'https://app.example.com/webhooks/n8n',
            authentication: {
                type: 'bearer',
                token: 'default-token'
            },
            retry: {
                enabled: true,
                maxRetries: 3,
                retryDelay: 5000,
                exponentialBackoff: true
            },
            filters: {
                allowedEvents: ['workflow.completed', 'workflow.failed'],
                excludeEvents: []
            }
        };
    }

    init() {
        if (!this.config.enabled) {
            console.log('Webhook forwarding is disabled');
            return;
        }

        console.log('Initializing webhook forwarder');
        this.startQueueProcessor();
    }

    // Forward webhook to web app server
    async forwardWebhook(event, data) {
        if (!this.shouldForwardEvent(event)) {
            console.log(`Event ${event} filtered out`);
            return;
        }

        const webhookData = {
            event,
            data,
            timestamp: new Date().toISOString(),
            source: 'n8n-server',
            signature: this.generateSignature(data)
        };

        this.queue.push({
            id: crypto.randomUUID(),
            webhookData,
            retryCount: 0,
            createdAt: Date.now()
        });

        this.processQueue();
    }

    shouldForwardEvent(event) {
        const { allowedEvents, excludeEvents } = this.config.filters;
        
        if (excludeEvents.includes(event)) {
            return false;
        }
        
        if (allowedEvents.length > 0 && !allowedEvents.includes(event)) {
            return false;
        }
        
        return true;
    }

    generateSignature(data) {
        const payload = JSON.stringify(data);
        return crypto.createHmac('sha256', this.config.authentication.token)
            .update(payload)
            .digest('hex');
    }

    async processQueue() {
        if (this.processing || this.queue.length === 0) {
            return;
        }

        this.processing = true;

        while (this.queue.length > 0) {
            const item = this.queue.shift();
            await this.sendWebhook(item);
        }

        this.processing = false;
    }

    async sendWebhook(item) {
        const { webhookData, retryCount } = item;
        
        try {
            await this.makeRequest(webhookData);
            console.log(`Webhook sent successfully: ${item.id}`);
        } catch (error) {
            console.error(`Failed to send webhook ${item.id}:`, error.message);
            
            if (this.config.retry.enabled && retryCount < this.config.retry.maxRetries) {
                const delay = this.calculateRetryDelay(retryCount);
                setTimeout(() => {
                    item.retryCount++;
                    this.queue.push(item);
                    this.processQueue();
                }, delay);
            } else {
                console.error(`Webhook ${item.id} failed permanently after ${retryCount} retries`);
                this.logFailedWebhook(item, error);
            }
        }
    }

    makeRequest(webhookData) {
        return new Promise((resolve, reject) => {
            const url = new URL(this.config.forwardTo);
            const payload = JSON.stringify(webhookData);
            
            const options = {
                hostname: url.hostname,
                port: url.port || (url.protocol === 'https:' ? 443 : 80),
                path: url.pathname + url.search,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(payload),
                    'User-Agent': 'n8n-webhook-forwarder/1.0'
                }
            };

            // Add authentication headers
            if (this.config.authentication.type === 'bearer') {
                options.headers['Authorization'] = `Bearer ${this.config.authentication.token}`;
            } else if (this.config.authentication.type === 'apikey') {
                options.headers['X-API-Key'] = this.config.authentication.token;
            }

            const req = https.request(options, (res) => {
                let responseData = '';
                
                res.on('data', (chunk) => {
                    responseData += chunk;
                });
                
                res.on('end', () => {
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        resolve(responseData);
                    } else {
                        reject(new Error(`HTTP ${res.statusCode}: ${responseData}`));
                    }
                });
            });

            req.on('error', (error) => {
                reject(error);
            });

            req.write(payload);
            req.end();
        });
    }

    calculateRetryDelay(retryCount) {
        const baseDelay = this.config.retry.retryDelay;
        if (this.config.retry.exponentialBackoff) {
            return baseDelay * Math.pow(2, retryCount);
        }
        return baseDelay;
    }

    logFailedWebhook(item, error) {
        const logEntry = {
            timestamp: new Date().toISOString(),
            webhookId: item.id,
            event: item.webhookData.event,
            retryCount: item.retryCount,
            error: error.message,
            data: item.webhookData.data
        };

        fs.appendFileSync('/opt/n8n/monitoring/logs/failed-webhooks.log', 
            JSON.stringify(logEntry) + '\n');
    }

    startQueueProcessor() {
        // Process queue every 5 seconds
        setInterval(() => {
            this.processQueue();
        }, 5000);
    }
}

// Initialize webhook forwarder
const forwarder = new WebhookForwarder();

// Export for use in n8n
if (typeof module !== 'undefined') {
    module.exports = WebhookForwarder;
}

// Make available globally if in browser context
if (typeof window !== 'undefined') {
    window.webhookForwarder = forwarder;
}
EOF

    log_pass "Webhook forwarding configured"
}

# Configure network security
configure_network_security() {
    log_info "Configuring network security between servers..."
    
    # Create network security configuration
    cat > /opt/n8n/user-configs/network-security.json << EOF
{
  "networkSecurity": {
    "allowedIPs": [
      "${WEBAPP_SERVER_IP:-192.168.1.100}",
      "${WEBAPP_SERVER_IP_ALT:-10.0.0.100}"
    ],
    "firewallRules": {
      "inbound": [
        {
          "port": 443,
          "protocol": "tcp",
          "source": "${WEBAPP_SERVER_IP:-192.168.1.100}",
          "action": "allow"
        },
        {
          "port": 80,
          "protocol": "tcp",
          "source": "${WEBAPP_SERVER_IP:-192.168.1.100}",
          "action": "allow"
        }
      ],
      "outbound": [
        {
          "port": 443,
          "protocol": "tcp",
          "destination": "${WEBAPP_SERVER_IP:-192.168.1.100}",
          "action": "allow"
        }
      ]
    },
    "vpn": {
      "enabled": false,
      "type": "wireguard",
      "configPath": "/etc/wireguard/n8n-webapp.conf"
    },
    "ssl": {
      "enabled": true,
      "verifyPeer": true,
      "allowSelfSigned": false,
      "ciphers": "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS"
    }
  }
}
EOF

    # Create firewall setup script
    cat > /opt/n8n/scripts/setup-firewall.sh << 'EOF'
#!/bin/bash

# Firewall Setup for Cross-Server Communication
# Sets up UFW rules for secure communication with web app server

WEBAPP_SERVER_IP="${WEBAPP_SERVER_IP:-192.168.1.100}"
WEBAPP_SERVER_IP_ALT="${WEBAPP_SERVER_IP_ALT:-}"

echo "Setting up firewall rules for cross-server communication"

# Allow SSH (keep existing connection)
sudo ufw allow ssh

# Allow HTTP and HTTPS from web app server
sudo ufw allow from "$WEBAPP_SERVER_IP" to any port 80
sudo ufw allow from "$WEBAPP_SERVER_IP" to any port 443

if [[ -n "$WEBAPP_SERVER_IP_ALT" ]]; then
    sudo ufw allow from "$WEBAPP_SERVER_IP_ALT" to any port 80
    sudo ufw allow from "$WEBAPP_SERVER_IP_ALT" to any port 443
fi

# Allow outbound HTTPS to web app server (for webhooks)
sudo ufw allow out to "$WEBAPP_SERVER_IP" port 443

if [[ -n "$WEBAPP_SERVER_IP_ALT" ]]; then
    sudo ufw allow out to "$WEBAPP_SERVER_IP_ALT" port 443
fi

# Block direct access to n8n port from other IPs
sudo ufw deny 5678

# Enable firewall if not already enabled
sudo ufw --force enable

echo "Firewall rules configured for web app server communication"
sudo ufw status numbered
EOF

    chmod +x /opt/n8n/scripts/setup-firewall.sh
    
    log_pass "Network security configured"
}

# Setup load balancing
setup_load_balancing() {
    log_info "Setting up load balancing for multiple n8n instances..."
    
    # Create load balancing configuration
    cat > /opt/n8n/user-configs/load-balancer.json << EOF
{
  "loadBalancing": {
    "enabled": false,
    "type": "nginx",
    "instances": [
      {
        "id": "n8n-primary",
        "host": "localhost",
        "port": 5678,
        "weight": 100,
        "backup": false
      }
    ],
    "healthCheck": {
      "enabled": true,
      "interval": 30,
      "timeout": 5,
      "path": "/healthz",
      "expectedStatus": 200
    },
    "sessionAffinity": {
      "enabled": true,
      "type": "ip_hash",
      "cookieName": "n8n-session"
    }
  }
}
EOF

    # Create load balancer configuration script
    cat > /opt/n8n/scripts/configure-load-balancer.sh << 'EOF'
#!/bin/bash

# Load Balancer Configuration Script
# Configures Nginx for load balancing multiple n8n instances

CONFIG_FILE="/opt/n8n/user-configs/load-balancer.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Load balancer configuration not found"
    exit 1
fi

ENABLED=$(jq -r '.loadBalancing.enabled' "$CONFIG_FILE")

if [[ "$ENABLED" != "true" ]]; then
    echo "Load balancing is disabled"
    exit 0
fi

echo "Configuring Nginx load balancer for n8n instances"

# Create upstream configuration
UPSTREAM_CONFIG="/etc/nginx/conf.d/n8n-upstream.conf"

cat > "$UPSTREAM_CONFIG" << 'EOL'
upstream n8n_backend {
    ip_hash;  # Session affinity
EOL

# Add instances from configuration
jq -r '.loadBalancing.instances[] | "\(.host):\(.port) weight=\(.weight)" + (if .backup then " backup" else "" end)' "$CONFIG_FILE" | while read -r instance; do
    echo "    server $instance;" >> "$UPSTREAM_CONFIG"
done

cat >> "$UPSTREAM_CONFIG" << 'EOL'
    
    # Health check configuration
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
}
EOL

echo "Load balancer upstream configuration created: $UPSTREAM_CONFIG"

# Update main Nginx configuration to use upstream
NGINX_CONF="/etc/nginx/sites-available/n8n"

if [[ -f "$NGINX_CONF" ]]; then
    # Backup original configuration
    cp "$NGINX_CONF" "$NGINX_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update proxy_pass to use upstream
    sed -i 's|proxy_pass http://localhost:5678|proxy_pass http://n8n_backend|g' "$NGINX_CONF"
    
    echo "Updated Nginx configuration to use load balancer"
    
    # Test and reload Nginx
    if nginx -t; then
        systemctl reload nginx
        echo "Nginx reloaded successfully"
    else
        echo "Nginx configuration test failed"
        exit 1
    fi
else
    echo "Warning: Nginx configuration file not found: $NGINX_CONF"
fi
EOF

    chmod +x /opt/n8n/scripts/configure-load-balancer.sh
    
    log_pass "Load balancing configuration created"
}

# Configure health checks
configure_health_checks() {
    log_info "Configuring health checks and failover mechanisms..."
    
    # Create health check script
    cat > /opt/n8n/scripts/health-check.sh << 'EOF'
#!/bin/bash

# Health Check Script for n8n Server
# Monitors server health and triggers failover if needed

N8N_URL="${N8N_INTERNAL_URL:-http://localhost:5678}"
HEALTH_ENDPOINT="/healthz"
TIMEOUT=10
MAX_FAILURES=3
FAILURE_COUNT_FILE="/opt/n8n/monitoring/health_failures"

# Function to check n8n health
check_n8n_health() {
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$N8N_URL$HEALTH_ENDPOINT")
    
    if [[ "$response_code" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check database connectivity
check_database_health() {
    # This would need to be customized based on your database setup
    # For PostgreSQL:
    if command -v psql >/dev/null 2>&1; then
        pg_isready -h "${DB_POSTGRESDB_HOST:-localhost}" -p "${DB_POSTGRESDB_PORT:-5432}" >/dev/null 2>&1
        return $?
    fi
    return 0  # Skip if no database tools available
}

# Function to check Redis connectivity
check_redis_health() {
    if command -v redis-cli >/dev/null 2>&1; then
        redis-cli -h "${REDIS_HOST:-localhost}" -p "${REDIS_PORT:-6379}" ping >/dev/null 2>&1
        return $?
    fi
    return 0  # Skip if Redis CLI not available
}

# Function to log health status
log_health_status() {
    local status="$1"
    local details="$2"
    local timestamp=$(date -Iseconds)
    
    echo "$timestamp [$status] $details" >> /opt/n8n/monitoring/logs/health-check.log
}

# Function to send alert
send_health_alert() {
    local severity="$1"
    local message="$2"
    
    # Create alert file
    local alert_file="/opt/n8n/monitoring/alerts/health_${severity}_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$alert_file" << EOL
{
  "alertId": "$(uuidgen 2>/dev/null || echo "alert_$(date +%s)")",
  "type": "health_check",
  "severity": "$severity",
  "timestamp": "$(date -Iseconds)",
  "message": "$message",
  "server": "$(hostname)",
  "checks": {
    "n8n": $(check_n8n_health && echo "true" || echo "false"),
    "database": $(check_database_health && echo "true" || echo "false"),
    "redis": $(check_redis_health && echo "true" || echo "false")
  }
}
EOL
    
    log_health_status "ALERT" "$severity: $message"
}

# Main health check function
main() {
    local all_healthy=true
    local failure_reasons=()
    
    # Check n8n health
    if ! check_n8n_health; then
        all_healthy=false
        failure_reasons+=("n8n service unhealthy")
    fi
    
    # Check database health
    if ! check_database_health; then
        all_healthy=false
        failure_reasons+=("database connectivity issues")
    fi
    
    # Check Redis health
    if ! check_redis_health; then
        all_healthy=false
        failure_reasons+=("redis connectivity issues")
    fi
    
    if [[ "$all_healthy" == "true" ]]; then
        # Reset failure count on success
        echo "0" > "$FAILURE_COUNT_FILE"
        log_health_status "HEALTHY" "All services are healthy"
        exit 0
    else
        # Increment failure count
        local current_failures=0
        if [[ -f "$FAILURE_COUNT_FILE" ]]; then
            current_failures=$(<"$FAILURE_COUNT_FILE")
        fi
        current_failures=$((current_failures + 1))
        echo "$current_failures" > "$FAILURE_COUNT_FILE"
        
        local failure_message=$(IFS=', '; echo "${failure_reasons[*]}")
        log_health_status "UNHEALTHY" "Failure #$current_failures: $failure_message"
        
        # Send alerts based on failure count
        if [[ $current_failures -ge $MAX_FAILURES ]]; then
            send_health_alert "critical" "n8n server has failed health checks $current_failures times: $failure_message"
        elif [[ $current_failures -ge 2 ]]; then
            send_health_alert "warning" "n8n server health check failed $current_failures times: $failure_message"
        fi
        
        exit 1
    fi
}

# Run health check
main "$@"
EOF

    chmod +x /opt/n8n/scripts/health-check.sh
    
    # Add health check to crontab (every 2 minutes)
    (crontab -l 2>/dev/null; echo "*/2 * * * * /opt/n8n/scripts/health-check.sh >> /opt/n8n/monitoring/logs/health-check.log 2>&1") | crontab -
    
    log_pass "Health checks configured"
}

# Configure shared session storage
configure_shared_sessions() {
    log_info "Configuring shared session storage across servers..."
    
    # Create session storage configuration
    cat > /opt/n8n/user-configs/session-storage.json << EOF
{
  "sessionStorage": {
    "type": "redis",
    "redis": {
      "host": "${REDIS_HOST:-localhost}",
      "port": ${REDIS_PORT:-6379},
      "password": "${REDIS_PASSWORD:-}",
      "database": 1,
      "keyPrefix": "n8n:session:",
      "ttl": 3600
    },
    "fallback": {
      "type": "file",
      "path": "/opt/n8n/user-sessions",
      "cleanup": true
    },
    "encryption": {
      "enabled": true,
      "algorithm": "aes-256-gcm",
      "key": "$(openssl rand -hex 32)"
    }
  }
}
EOF

    # Create session manager script
    cat > /opt/n8n/scripts/session-manager.js << 'EOF'
// Shared Session Manager for Cross-Server Communication

const redis = require('redis');
const crypto = require('crypto');
const fs = require('fs');

class SessionManager {
    constructor(configPath = '/opt/n8n/user-configs/session-storage.json') {
        this.config = this.loadConfig(configPath);
        this.redisClient = null;
        this.init();
    }

    loadConfig(configPath) {
        try {
            const configData = fs.readFileSync(configPath, 'utf8');
            return JSON.parse(configData).sessionStorage;
        } catch (error) {
            console.error('Failed to load session config:', error);
            return this.getDefaultConfig();
        }
    }

    getDefaultConfig() {
        return {
            type: 'file',
            fallback: {
                type: 'file',
                path: '/opt/n8n/user-sessions',
                cleanup: true
            },
            encryption: {
                enabled: false
            }
        };
    }

    async init() {
        if (this.config.type === 'redis') {
            try {
                this.redisClient = redis.createClient({
                    host: this.config.redis.host,
                    port: this.config.redis.port,
                    password: this.config.redis.password,
                    db: this.config.redis.database
                });
                
                await this.redisClient.connect();
                console.log('Connected to Redis for session storage');
            } catch (error) {
                console.error('Failed to connect to Redis:', error);
                console.log('Falling back to file-based session storage');
                this.redisClient = null;
            }
        }
    }

    async storeSession(sessionId, sessionData, ttl = null) {
        const data = this.encryptData(sessionData);
        const expiry = ttl || this.config.redis?.ttl || 3600;
        
        if (this.redisClient) {
            try {
                const key = `${this.config.redis.keyPrefix}${sessionId}`;
                await this.redisClient.setEx(key, expiry, data);
                return true;
            } catch (error) {
                console.error('Failed to store session in Redis:', error);
                return this.storeSessionFile(sessionId, data, expiry);
            }
        } else {
            return this.storeSessionFile(sessionId, data, expiry);
        }
    }

    async getSession(sessionId) {
        if (this.redisClient) {
            try {
                const key = `${this.config.redis.keyPrefix}${sessionId}`;
                const data = await this.redisClient.get(key);
                if (data) {
                    return this.decryptData(data);
                }
            } catch (error) {
                console.error('Failed to get session from Redis:', error);
            }
        }
        
        // Fallback to file storage
        return this.getSessionFile(sessionId);
    }

    async deleteSession(sessionId) {
        if (this.redisClient) {
            try {
                const key = `${this.config.redis.keyPrefix}${sessionId}`;
                await this.redisClient.del(key);
            } catch (error) {
                console.error('Failed to delete session from Redis:', error);
            }
        }
        
        // Also delete from file storage
        this.deleteSessionFile(sessionId);
    }

    storeSessionFile(sessionId, data, expiry) {
        try {
            const sessionFile = `${this.config.fallback.path}/${sessionId}.json`;
            const sessionInfo = {
                data,
                expires: Date.now() + (expiry * 1000),
                created: Date.now()
            };
            
            fs.writeFileSync(sessionFile, JSON.stringify(sessionInfo));
            return true;
        } catch (error) {
            console.error('Failed to store session file:', error);
            return false;
        }
    }

    getSessionFile(sessionId) {
        try {
            const sessionFile = `${this.config.fallback.path}/${sessionId}.json`;
            
            if (!fs.existsSync(sessionFile)) {
                return null;
            }
            
            const sessionInfo = JSON.parse(fs.readFileSync(sessionFile, 'utf8'));
            
            // Check if session has expired
            if (Date.now() > sessionInfo.expires) {
                this.deleteSessionFile(sessionId);
                return null;
            }
            
            return this.decryptData(sessionInfo.data);
        } catch (error) {
            console.error('Failed to get session file:', error);
            return null;
        }
    }

    deleteSessionFile(sessionId) {
        try {
            const sessionFile = `${this.config.fallback.path}/${sessionId}.json`;
            if (fs.existsSync(sessionFile)) {
                fs.unlinkSync(sessionFile);
            }
        } catch (error) {
            console.error('Failed to delete session file:', error);
        }
    }

    encryptData(data) {
        if (!this.config.encryption.enabled) {
            return JSON.stringify(data);
        }
        
        const algorithm = this.config.encryption.algorithm;
        const key = Buffer.from(this.config.encryption.key, 'hex');
        const iv = crypto.randomBytes(16);
        
        const cipher = crypto.createCipher(algorithm, key);
        cipher.setIV(iv);
        
        let encrypted = cipher.update(JSON.stringify(data), 'utf8', 'hex');
        encrypted += cipher.final('hex');
        
        const authTag = cipher.getAuthTag();
        
        return JSON.stringify({
            encrypted,
            iv: iv.toString('hex'),
            authTag: authTag.toString('hex')
        });
    }

    decryptData(encryptedData) {
        if (!this.config.encryption.enabled) {
            return JSON.parse(encryptedData);
        }
        
        try {
            const { encrypted, iv, authTag } = JSON.parse(encryptedData);
            const algorithm = this.config.encryption.algorithm;
            const key = Buffer.from(this.config.encryption.key, 'hex');
            
            const decipher = crypto.createDecipher(algorithm, key);
            decipher.setIV(Buffer.from(iv, 'hex'));
            decipher.setAuthTag(Buffer.from(authTag, 'hex'));
            
            let decrypted = decipher.update(encrypted, 'hex', 'utf8');
            decrypted += decipher.final('utf8');
            
            return JSON.parse(decrypted);
        } catch (error) {
            console.error('Failed to decrypt session data:', error);
            return null;
        }
    }

    async cleanupExpiredSessions() {
        if (this.config.fallback.cleanup) {
            const sessionDir = this.config.fallback.path;
            
            try {
                const files = fs.readdirSync(sessionDir);
                const now = Date.now();
                
                for (const file of files) {
                    if (file.endsWith('.json')) {
                        const filePath = `${sessionDir}/${file}`;
                        const sessionInfo = JSON.parse(fs.readFileSync(filePath, 'utf8'));
                        
                        if (now > sessionInfo.expires) {
                            fs.unlinkSync(filePath);
                        }
                    }
                }
            } catch (error) {
                console.error('Failed to cleanup expired sessions:', error);
            }
        }
    }
}

// Initialize session manager
const sessionManager = new SessionManager();

// Cleanup expired sessions every 15 minutes
setInterval(() => {
    sessionManager.cleanupExpiredSessions();
}, 15 * 60 * 1000);

// Export for use
if (typeof module !== 'undefined') {
    module.exports = SessionManager;
}

if (typeof window !== 'undefined') {
    window.sessionManager = sessionManager;
}
EOF

    log_pass "Shared session storage configured"
}

# Setup secure file transfer
setup_secure_file_transfer() {
    log_info "Setting up secure file transfer mechanisms..."
    
    # Create file transfer configuration
    cat > /opt/n8n/user-configs/file-transfer.json << EOF
{
  "fileTransfer": {
    "enabled": true,
    "methods": {
      "sftp": {
        "enabled": true,
        "host": "${WEBAPP_SERVER_IP:-192.168.1.100}",
        "port": 22,
        "username": "${SFTP_USERNAME:-n8n-transfer}",
        "keyPath": "/opt/n8n/ssl/transfer-key",
        "remotePath": "/uploads/n8n"
      },
      "https": {
        "enabled": true,
        "uploadUrl": "${WEBAPP_UPLOAD_URL:-https://app.example.com/api/upload}",
        "downloadUrl": "${WEBAPP_DOWNLOAD_URL:-https://app.example.com/api/download}",
        "authentication": {
          "type": "bearer",
          "token": "$(openssl rand -base64 32)"
        }
      }
    },
    "encryption": {
      "enabled": true,
      "algorithm": "aes-256-cbc",
      "keyPath": "/opt/n8n/ssl/file-encryption.key"
    },
    "limits": {
      "maxFileSize": "100MB",
      "allowedTypes": [".pdf", ".json", ".csv", ".txt", ".xlsx"],
      "maxDailyTransfers": 1000
    }
  }
}
EOF

    # Generate file transfer encryption key
    openssl rand -out /opt/n8n/ssl/file-encryption.key 32
    chmod 600 /opt/n8n/ssl/file-encryption.key
    
    # Create file transfer script
    cat > /opt/n8n/scripts/file-transfer.sh << 'EOF'
#!/bin/bash

# Secure File Transfer Script
# Handles secure file transfer between n8n and web app servers

CONFIG_FILE="/opt/n8n/user-configs/file-transfer.json"

# Function to load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: File transfer configuration not found"
        exit 1
    fi
}

# Function to encrypt file
encrypt_file() {
    local source_file="$1"
    local output_file="$2"
    local key_file="/opt/n8n/ssl/file-encryption.key"
    
    if [[ ! -f "$key_file" ]]; then
        echo "Error: Encryption key not found"
        return 1
    fi
    
    openssl enc -aes-256-cbc -salt -in "$source_file" -out "$output_file" -pass file:"$key_file"
}

# Function to decrypt file
decrypt_file() {
    local source_file="$1"
    local output_file="$2"
    local key_file="/opt/n8n/ssl/file-encryption.key"
    
    if [[ ! -f "$key_file" ]]; then
        echo "Error: Decryption key not found"
        return 1
    fi
    
    openssl enc -d -aes-256-cbc -in "$source_file" -out "$output_file" -pass file:"$key_file"
}

# Function to transfer file via SFTP
transfer_sftp() {
    local file_path="$1"
    local remote_name="$2"
    
    local sftp_host=$(jq -r '.fileTransfer.methods.sftp.host' "$CONFIG_FILE")
    local sftp_port=$(jq -r '.fileTransfer.methods.sftp.port' "$CONFIG_FILE")
    local sftp_user=$(jq -r '.fileTransfer.methods.sftp.username' "$CONFIG_FILE")
    local sftp_key=$(jq -r '.fileTransfer.methods.sftp.keyPath' "$CONFIG_FILE")
    local remote_path=$(jq -r '.fileTransfer.methods.sftp.remotePath' "$CONFIG_FILE")
    
    # Encrypt file before transfer
    local encrypted_file=$(mktemp)
    if ! encrypt_file "$file_path" "$encrypted_file"; then
        echo "Failed to encrypt file"
        rm -f "$encrypted_file"
        return 1
    fi
    
    # Transfer encrypted file
    sftp -i "$sftp_key" -P "$sftp_port" "$sftp_user@$sftp_host" << EOL
put $encrypted_file $remote_path/$remote_name.enc
bye
EOL
    
    local result=$?
    rm -f "$encrypted_file"
    
    if [[ $result -eq 0 ]]; then
        echo "File transferred successfully via SFTP"
    else
        echo "SFTP transfer failed"
    fi
    
    return $result
}

# Function to transfer file via HTTPS
transfer_https() {
    local file_path="$1"
    local remote_name="$2"
    
    local upload_url=$(jq -r '.fileTransfer.methods.https.uploadUrl' "$CONFIG_FILE")
    local auth_token=$(jq -r '.fileTransfer.methods.https.authentication.token' "$CONFIG_FILE")
    
    # Encrypt file before transfer
    local encrypted_file=$(mktemp)
    if ! encrypt_file "$file_path" "$encrypted_file"; then
        echo "Failed to encrypt file"
        rm -f "$encrypted_file"
        return 1
    fi
    
    # Upload via HTTPS
    curl -X POST \
        -H "Authorization: Bearer $auth_token" \
        -H "Content-Type: application/octet-stream" \
        -H "X-Filename: $remote_name.enc" \
        --data-binary @"$encrypted_file" \
        "$upload_url"
    
    local result=$?
    rm -f "$encrypted_file"
    
    return $result
}

# Main transfer function
transfer_file() {
    local method="$1"
    local file_path="$2"
    local remote_name="$3"
    
    if [[ ! -f "$file_path" ]]; then
        echo "Error: Source file not found: $file_path"
        return 1
    fi
    
    load_config
    
    case "$method" in
        "sftp")
            transfer_sftp "$file_path" "$remote_name"
            ;;
        "https")
            transfer_https "$file_path" "$remote_name"
            ;;
        *)
            echo "Error: Unknown transfer method: $method"
            echo "Available methods: sftp, https"
            return 1
            ;;
    esac
}

# Usage information
usage() {
    echo "Usage: $0 <method> <file_path> <remote_name>"
    echo "Methods: sftp, https"
    echo "Example: $0 https /tmp/workflow.json workflow_backup"
}

# Main execution
if [[ $# -ne 3 ]]; then
    usage
    exit 1
fi

transfer_file "$1" "$2" "$3"
EOF

    chmod +x /opt/n8n/scripts/file-transfer.sh
    
    log_pass "Secure file transfer configured"
}

# Main execution function
main() {
    log_info "Starting cross-server setup configuration..."
    
    load_environment
    configure_api_authentication
    setup_webhook_forwarding
    configure_network_security
    setup_load_balancing
    configure_health_checks
    configure_shared_sessions
    setup_secure_file_transfer
    
    log_pass "Cross-server setup configuration completed successfully"
    log_info "Configuration files created in: /opt/n8n/user-configs/"
    log_info "Scripts available in: /opt/n8n/scripts/"
    log_info "Health checks run every 2 minutes"
    log_info "To setup firewall rules, run: /opt/n8n/scripts/setup-firewall.sh"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
