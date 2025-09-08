# n8n Multi-User Web App Server Integration Guide

This guide provides step-by-step instructions for integrating your web application with the n8n multi-user server, enabling secure iframe embedding and user management.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Server Setup](#server-setup)
3. [Network Configuration](#network-configuration)
4. [Authentication Integration](#authentication-integration)
5. [Iframe Embedding](#iframe-embedding)
6. [API Integration](#api-integration)
7. [Security Configuration](#security-configuration)
8. [Code Examples](#code-examples)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)

## Prerequisites

### Web App Server Requirements

- **Operating System**: Ubuntu 20.04 LTS or newer, CentOS 8+, or similar Linux distribution
- **Node.js**: Version 16.x or newer
- **Memory**: Minimum 2GB RAM (4GB+ recommended for production)
- **Storage**: Minimum 10GB free space
- **Network**: Stable internet connection with access to n8n server

### Dependencies to Install

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y nodejs npm nginx certbot python3-certbot-nginx

# CentOS/RHEL
sudo yum update
sudo yum install -y nodejs npm nginx certbot python3-certbot-nginx
```

### Node.js Dependencies

Add these to your `package.json`:

```json
{
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.0.0",
    "jsonwebtoken": "^9.0.1",
    "axios": "^1.4.0",
    "socket.io": "^4.7.2"
  }
}
```

## Server Setup

### 1. Environment Configuration

Create a `.env` file in your web app root:

```bash
# Web App Configuration
WEB_APP_PORT=3000
WEB_APP_DOMAIN=https://app.example.com

# n8n Server Configuration
N8N_SERVER_URL=https://n8n.example.com
N8N_API_URL=https://n8n.example.com/api
N8N_WEBHOOK_URL=https://n8n.example.com/webhook

# Authentication
JWT_SECRET=your-super-secure-jwt-secret-here
JWT_EXPIRES_IN=24h

# API Keys (provided by n8n server admin)
N8N_API_KEY=your-n8n-api-key-here
N8N_WEBHOOK_SECRET=your-webhook-secret-here

# Database (your existing web app database)
DATABASE_URL=postgresql://user:password@localhost:5432/webapp_db

# Security
CORS_ORIGIN=https://n8n.example.com
IFRAME_ALLOWED_ORIGINS=https://n8n.example.com

# SSL Configuration
SSL_CERT_PATH=/etc/ssl/certs/webapp.crt
SSL_KEY_PATH=/etc/ssl/private/webapp.key
```

### 2. Nginx Configuration

Create `/etc/nginx/sites-available/webapp`:

```nginx
# Web App Nginx Configuration
server {
    listen 80;
    server_name app.example.com;
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.example.com;
    
    # SSL Configuration
    ssl_certificate /etc/ssl/certs/webapp.crt;
    ssl_certificate_key /etc/ssl/private/webapp.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # CSP for iframe embedding
    add_header Content-Security-Policy "default-src 'self'; frame-src 'self' https://n8n.example.com; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=webapp:10m rate=10r/m;
    limit_req zone=webapp burst=20 nodelay;
    
    # Main application
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # API endpoints
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # n8n webhook receiver
    location /webhooks/n8n {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Static files
    location /static/ {
        root /var/www/webapp;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

Enable the configuration:

```bash
sudo ln -s /etc/nginx/sites-available/webapp /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Network Configuration

### 1. Firewall Rules

```bash
# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow outbound connections to n8n server
sudo ufw allow out to N8N_SERVER_IP port 443

# Enable firewall
sudo ufw enable
```

### 2. DNS Configuration

Ensure your domain points to your web app server:

```
app.example.com.    IN    A    YOUR_WEBAPP_SERVER_IP
```

### 3. SSL Certificate Setup

#### Option A: Let's Encrypt (Production)

```bash
sudo certbot --nginx -d app.example.com
```

#### Option B: Self-signed (Development)

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/webapp.key \
    -out /etc/ssl/certs/webapp.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=app.example.com"
```

## Authentication Integration

### 1. User Authentication Service

Create `services/auth.js`:

```javascript
const jwt = require('jsonwebtoken');
const axios = require('axios');

class AuthService {
    constructor() {
        this.n8nApiUrl = process.env.N8N_API_URL;
        this.apiKey = process.env.N8N_API_KEY;
        this.jwtSecret = process.env.JWT_SECRET;
    }

    // Create user in both systems
    async createUser(userData) {
        try {
            // Create user in your database first
            const localUser = await this.createLocalUser(userData);
            
            // Create user in n8n
            const n8nUser = await this.createN8nUser({
                userId: localUser.id,
                email: localUser.email,
                password: userData.password,
                role: 'user'
            });
            
            return { localUser, n8nUser };
        } catch (error) {
            console.error('Error creating user:', error);
            throw error;
        }
    }

    // Login user and get n8n token
    async loginUser(email, password) {
        try {
            // Authenticate with your local system
            const localUser = await this.authenticateLocal(email, password);
            
            if (!localUser) {
                throw new Error('Invalid credentials');
            }
            
            // Get n8n token
            const n8nToken = await this.getN8nToken(localUser.id, password);
            
            // Generate local JWT
            const localToken = jwt.sign(
                { 
                    userId: localUser.id,
                    email: localUser.email 
                },
                this.jwtSecret,
                { expiresIn: process.env.JWT_EXPIRES_IN }
            );
            
            return {
                user: localUser,
                localToken,
                n8nToken: n8nToken.token
            };
        } catch (error) {
            console.error('Error during login:', error);
            throw error;
        }
    }

    // Create user in n8n system
    async createN8nUser(userData) {
        try {
            const response = await axios.post(
                `${this.n8nApiUrl}/users`,
                userData,
                {
                    headers: {
                        'X-API-Key': this.apiKey,
                        'Content-Type': 'application/json'
                    }
                }
            );
            
            return response.data;
        } catch (error) {
            console.error('Error creating n8n user:', error);
            throw error;
        }
    }

    // Get n8n authentication token
    async getN8nToken(userId, password) {
        try {
            const response = await axios.post(
                `${this.n8nApiUrl}/auth/login`,
                { userId, password },
                {
                    headers: {
                        'Content-Type': 'application/json'
                    }
                }
            );
            
            return response.data;
        } catch (error) {
            console.error('Error getting n8n token:', error);
            throw error;
        }
    }

    // Validate local JWT token
    validateToken(token) {
        try {
            return jwt.verify(token, this.jwtSecret);
        } catch (error) {
            return null;
        }
    }

    // Implement these methods according to your database/auth system
    async createLocalUser(userData) {
        // Your implementation here
    }

    async authenticateLocal(email, password) {
        // Your implementation here
    }
}

module.exports = new AuthService();
```

### 2. Authentication Middleware

Create `middleware/auth.js`:

```javascript
const authService = require('../services/auth');

const requireAuth = async (req, res, next) => {
    try {
        const token = req.headers.authorization?.replace('Bearer ', '');
        
        if (!token) {
            return res.status(401).json({ error: 'Authentication required' });
        }
        
        const decoded = authService.validateToken(token);
        
        if (!decoded) {
            return res.status(401).json({ error: 'Invalid token' });
        }
        
        req.user = decoded;
        next();
    } catch (error) {
        return res.status(401).json({ error: 'Authentication failed' });
    }
};

module.exports = { requireAuth };
```

## Iframe Embedding

### 1. Frontend Integration

Create `components/N8nEmbed.js` (React example):

```javascript
import React, { useEffect, useRef, useState } from 'react';
import { useAuth } from '../hooks/useAuth';

const N8nEmbed = ({ userId, height = '600px' }) => {
    const iframeRef = useRef(null);
    const { user, n8nToken } = useAuth();
    const [isReady, setIsReady] = useState(false);
    
    useEffect(() => {
        const iframe = iframeRef.current;
        if (!iframe || !n8nToken) return;

        // Set up postMessage communication
        const handleMessage = (event) => {
            if (event.origin !== process.env.REACT_APP_N8N_SERVER_URL) {
                return;
            }

            const { type, data } = event.data;

            switch (type) {
                case 'IFRAME_READY':
                    // Send authentication data to n8n
                    iframe.contentWindow.postMessage({
                        type: 'AUTH_TOKEN',
                        data: {
                            token: n8nToken,
                            userId: user.id
                        }
                    }, process.env.REACT_APP_N8N_SERVER_URL);
                    break;
                    
                case 'AUTH_SUCCESS':
                    setIsReady(true);
                    break;
                    
                case 'WORKFLOW_EXECUTED':
                    console.log('Workflow executed:', data);
                    // Handle workflow execution events
                    break;
                    
                case 'SESSION_REFRESH':
                    // Handle session refresh requests
                    refreshN8nToken();
                    break;
            }
        };

        window.addEventListener('message', handleMessage);
        
        return () => {
            window.removeEventListener('message', handleMessage);
        };
    }, [n8nToken, user]);

    const refreshN8nToken = async () => {
        try {
            // Refresh n8n token and send to iframe
            const newToken = await authService.refreshN8nToken();
            
            iframeRef.current?.contentWindow.postMessage({
                type: 'SESSION_REFRESH',
                data: { token: newToken }
            }, process.env.REACT_APP_N8N_SERVER_URL);
        } catch (error) {
            console.error('Error refreshing n8n token:', error);
        }
    };

    if (!user || !n8nToken) {
        return <div>Please log in to access workflows</div>;
    }

    const iframeSrc = `${process.env.REACT_APP_N8N_SERVER_URL}/user/${userId}`;

    return (
        <div className="n8n-embed-container">
            {!isReady && (
                <div className="loading-overlay">
                    <div className="spinner">Loading n8n...</div>
                </div>
            )}
            <iframe
                ref={iframeRef}
                src={iframeSrc}
                width="100%"
                height={height}
                frameBorder="0"
                allow="fullscreen"
                sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
                style={{ 
                    display: isReady ? 'block' : 'none',
                    border: '1px solid #ddd',
                    borderRadius: '8px'
                }}
            />
        </div>
    );
};

export default N8nEmbed;
```

### 2. Vanilla JavaScript Integration

For non-React applications:

```html
<!DOCTYPE html>
<html>
<head>
    <title>n8n Integration</title>
    <style>
        .n8n-container {
            width: 100%;
            height: 600px;
            border: 1px solid #ddd;
            border-radius: 8px;
            position: relative;
        }
        
        .loading-overlay {
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(255, 255, 255, 0.9);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 1000;
        }
        
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <div class="n8n-container">
        <div id="loading" class="loading-overlay">
            <div>Loading n8n...</div>
        </div>
        <iframe 
            id="n8n-iframe"
            width="100%"
            height="100%"
            frameborder="0"
            allow="fullscreen"
            sandbox="allow-scripts allow-same-origin allow-forms allow-popups">
        </iframe>
    </div>

    <script>
        class N8nIntegration {
            constructor(config) {
                this.config = config;
                this.iframe = document.getElementById('n8n-iframe');
                this.loading = document.getElementById('loading');
                this.init();
            }
            
            init() {
                // Set iframe source
                this.iframe.src = `${this.config.n8nUrl}/user/${this.config.userId}`;
                
                // Set up message handling
                window.addEventListener('message', this.handleMessage.bind(this));
            }
            
            handleMessage(event) {
                if (event.origin !== this.config.n8nUrl) {
                    return;
                }
                
                const { type, data } = event.data;
                
                switch (type) {
                    case 'IFRAME_READY':
                        this.sendAuthData();
                        break;
                        
                    case 'AUTH_SUCCESS':
                        this.loading.classList.add('hidden');
                        break;
                        
                    case 'WORKFLOW_EXECUTED':
                        this.onWorkflowExecuted(data);
                        break;
                }
            }
            
            sendAuthData() {
                this.iframe.contentWindow.postMessage({
                    type: 'AUTH_TOKEN',
                    data: {
                        token: this.config.token,
                        userId: this.config.userId
                    }
                }, this.config.n8nUrl);
            }
            
            onWorkflowExecuted(data) {
                console.log('Workflow executed:', data);
                // Handle workflow execution events
            }
        }
        
        // Initialize when page loads
        document.addEventListener('DOMContentLoaded', () => {
            // Get auth data from your backend
            fetch('/api/user/n8n-auth')
                .then(response => response.json())
                .then(authData => {
                    new N8nIntegration({
                        n8nUrl: 'https://n8n.example.com',
                        userId: authData.userId,
                        token: authData.n8nToken
                    });
                })
                .catch(error => {
                    console.error('Failed to initialize n8n integration:', error);
                });
        });
    </script>
</body>
</html>
```

## API Integration

### 1. User Management API Client

Create `services/n8nApi.js`:

```javascript
const axios = require('axios');

class N8nApiClient {
    constructor() {
        this.baseUrl = process.env.N8N_API_URL;
        this.apiKey = process.env.N8N_API_KEY;
        
        this.client = axios.create({
            baseURL: this.baseUrl,
            headers: {
                'X-API-Key': this.apiKey,
                'Content-Type': 'application/json'
            },
            timeout: 10000
        });
    }

    // User management
    async createUser(userData) {
        const response = await this.client.post('/users', userData);
        return response.data;
    }

    async getUser(userId) {
        const response = await this.client.get(`/users/${userId}`);
        return response.data;
    }

    async updateUser(userId, updates) {
        const response = await this.client.put(`/users/${userId}`, updates);
        return response.data;
    }

    async deleteUser(userId) {
        const response = await this.client.delete(`/users/${userId}`);
        return response.data;
    }

    // User metrics
    async getUserMetrics(userId) {
        const response = await this.client.get(`/metrics/users/${userId}`);
        return response.data;
    }

    async getUserUsage(userId, period = 'daily') {
        const response = await this.client.get(`/reports/users/${userId}/${period}`);
        return response.data;
    }

    // System analytics
    async getSystemOverview() {
        const response = await this.client.get('/reports/system/overview');
        return response.data;
    }
}

module.exports = new N8nApiClient();
```

### 2. Webhook Handler

Create `routes/webhooks.js`:

```javascript
const express = require('express');
const crypto = require('crypto');
const router = express.Router();

// Webhook verification middleware
const verifyWebhook = (req, res, next) => {
    const signature = req.headers['x-n8n-signature'];
    const payload = JSON.stringify(req.body);
    const secret = process.env.N8N_WEBHOOK_SECRET;
    
    const expectedSignature = crypto
        .createHmac('sha256', secret)
        .update(payload)
        .digest('hex');
    
    if (signature !== expectedSignature) {
        return res.status(401).json({ error: 'Invalid signature' });
    }
    
    next();
};

// Handle n8n webhooks
router.post('/n8n', verifyWebhook, async (req, res) => {
    try {
        const { event, data } = req.body;
        
        switch (event) {
            case 'workflow.completed':
                await handleWorkflowCompleted(data);
                break;
                
            case 'workflow.failed':
                await handleWorkflowFailed(data);
                break;
                
            case 'execution.started':
                await handleExecutionStarted(data);
                break;
                
            case 'user.created':
                await handleUserCreated(data);
                break;
                
            default:
                console.log('Unhandled webhook event:', event);
        }
        
        res.json({ success: true });
    } catch (error) {
        console.error('Webhook error:', error);
        res.status(500).json({ error: 'Webhook processing failed' });
    }
});

async function handleWorkflowCompleted(data) {
    console.log('Workflow completed:', data);
    
    // Update user metrics in your database
    // Send notifications to user
    // Update billing information
}

async function handleWorkflowFailed(data) {
    console.log('Workflow failed:', data);
    
    // Log error
    // Notify user of failure
    // Update error metrics
}

async function handleExecutionStarted(data) {
    console.log('Execution started:', data);
    
    // Track execution start
    // Update real-time dashboard
}

async function handleUserCreated(data) {
    console.log('User created in n8n:', data);
    
    // Sync user data
    // Send welcome notification
}

module.exports = router;
```

## Security Configuration

### 1. CORS Configuration

```javascript
const cors = require('cors');

const corsOptions = {
    origin: [
        process.env.N8N_SERVER_URL,
        process.env.WEB_APP_DOMAIN
    ],
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
        'Content-Type',
        'Authorization',
        'X-API-Key',
        'X-User-ID',
        'X-N8N-Signature'
    ]
};

app.use(cors(corsOptions));
```

### 2. Helmet Security Configuration

```javascript
const helmet = require('helmet');

app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            frameSrc: ["'self'", process.env.N8N_SERVER_URL],
            scriptSrc: ["'self'", "'unsafe-inline'"],
            styleSrc: ["'self'", "'unsafe-inline'"],
            imgSrc: ["'self'", "data:", "https:"],
            connectSrc: ["'self'", process.env.N8N_SERVER_URL]
        }
    },
    frameOptions: {
        action: 'sameorigin'
    }
}));
```

### 3. Rate Limiting

```javascript
const rateLimit = require('express-rate-limit');

const apiLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
    message: 'Too many API requests from this IP'
});

const webhookLimiter = rateLimit({
    windowMs: 1 * 60 * 1000, // 1 minute
    max: 50, // limit each IP to 50 webhook requests per minute
    message: 'Too many webhook requests'
});

app.use('/api/', apiLimiter);
app.use('/webhooks/', webhookLimiter);
```

## Code Examples

### Complete Express.js App Structure

```
webapp/
├── package.json
├── .env
├── server.js
├── routes/
│   ├── auth.js
│   ├── users.js
│   └── webhooks.js
├── middleware/
│   ├── auth.js
│   └── validation.js
├── services/
│   ├── auth.js
│   └── n8nApi.js
├── public/
│   ├── index.html
│   └── js/
│       └── n8n-integration.js
└── views/
    └── dashboard.html
```

### Main Server File (`server.js`)

```javascript
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const webhookRoutes = require('./routes/webhooks');
const { requireAuth } = require('./middleware/auth');

const app = express();
const PORT = process.env.WEB_APP_PORT || 3000;

// Security middleware
app.use(helmet());
app.use(cors({
    origin: [process.env.N8N_SERVER_URL, process.env.WEB_APP_DOMAIN],
    credentials: true
}));

// Body parsing
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Static files
app.use(express.static('public'));

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', requireAuth, userRoutes);
app.use('/webhooks', webhookRoutes);

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Error handling
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ error: 'Something went wrong!' });
});

app.listen(PORT, () => {
    console.log(`Web app server running on port ${PORT}`);
});
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Iframe Not Loading

**Problem**: Iframe shows blank or error message

**Solutions**:
- Check CORS configuration on both servers
- Verify SSL certificates are valid
- Ensure domains are correctly configured
- Check browser console for CSP violations

```javascript
// Debug iframe loading
iframe.onload = () => console.log('Iframe loaded successfully');
iframe.onerror = (e) => console.error('Iframe load error:', e);
```

#### 2. Authentication Failures

**Problem**: Users can't authenticate with n8n

**Solutions**:
- Verify API keys are correct
- Check JWT token format and expiration
- Ensure user exists in both systems
- Validate token signing secrets

```javascript
// Debug authentication
console.log('Token payload:', jwt.decode(token));
console.log('Token valid:', jwt.verify(token, secret));
```

#### 3. Webhook Not Receiving Data

**Problem**: Webhooks from n8n not working

**Solutions**:
- Verify webhook URL is accessible from n8n server
- Check webhook signature validation
- Ensure proper HTTP method (POST)
- Validate webhook secret

```bash
# Test webhook manually
curl -X POST https://app.example.com/webhooks/n8n \
  -H "Content-Type: application/json" \
  -H "X-N8N-Signature: test-signature" \
  -d '{"event":"test","data":{}}'
```

#### 4. CORS Errors

**Problem**: Cross-origin request blocked

**Solutions**:
- Add proper CORS headers
- Include credentials in requests
- Verify origin allowlist

```javascript
// Check CORS preflight
fetch('/api/test', {
    method: 'OPTIONS',
    headers: { 'Access-Control-Request-Method': 'POST' }
}).then(response => console.log('CORS preflight:', response.headers));
```

### Debug Mode

Enable debug logging:

```javascript
// Add to your .env file
DEBUG=true
LOG_LEVEL=debug

// In your code
if (process.env.DEBUG === 'true') {
    console.log('Debug info:', debugData);
}
```

### Health Checks

Implement comprehensive health checks:

```javascript
app.get('/health/detailed', async (req, res) => {
    const health = {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        checks: {
            database: await checkDatabase(),
            n8nApi: await checkN8nApi(),
            redis: await checkRedis(),
            disk: await checkDiskSpace()
        }
    };
    
    const hasErrors = Object.values(health.checks).some(check => !check.healthy);
    
    res.status(hasErrors ? 503 : 200).json(health);
});
```

## Best Practices

### 1. Security Best Practices

- **Always use HTTPS** in production
- **Validate all inputs** from both user and n8n
- **Implement rate limiting** on all API endpoints
- **Use strong JWT secrets** and rotate them regularly
- **Validate webhook signatures** to prevent spoofing
- **Implement proper CORS** policies
- **Use CSP headers** to prevent XSS attacks

### 2. Performance Best Practices

- **Cache user tokens** to reduce API calls
- **Implement connection pooling** for database
- **Use CDN** for static assets
- **Compress responses** with gzip
- **Implement request deduplication** for expensive operations
- **Monitor and log performance** metrics

### 3. Reliability Best Practices

- **Implement circuit breakers** for external API calls
- **Add retry logic** with exponential backoff
- **Use health checks** for monitoring
- **Implement graceful shutdowns**
- **Monitor webhook delivery** and implement retries
- **Use database transactions** for data consistency

### 4. Monitoring and Logging

```javascript
// Request logging
app.use((req, res, next) => {
    const start = Date.now();
    
    res.on('finish', () => {
        const duration = Date.now() - start;
        console.log(`${req.method} ${req.url} ${res.statusCode} ${duration}ms`);
    });
    
    next();
});

// Error tracking
process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
```

### 5. Configuration Management

- **Use environment variables** for all configuration
- **Implement configuration validation** on startup
- **Use different configs** for development/staging/production
- **Document all environment variables**

### Example Environment Validation

```javascript
const requiredEnvVars = [
    'WEB_APP_DOMAIN',
    'N8N_SERVER_URL',
    'N8N_API_KEY',
    'JWT_SECRET',
    'DATABASE_URL'
];

const missingVars = requiredEnvVars.filter(varName => !process.env[varName]);

if (missingVars.length > 0) {
    console.error('Missing required environment variables:', missingVars);
    process.exit(1);
}
```

---

## Support

For additional support:

1. **Check the logs** on both servers for error messages
2. **Review the API documentation** at `https://n8n.example.com/api/docs`
3. **Test individual components** in isolation
4. **Use browser developer tools** to debug frontend issues
5. **Monitor network traffic** between servers

## Updates

This integration guide will be updated as new features are added to the n8n multi-user system. Always check for the latest version of this documentation.

---

**Last Updated**: December 2024  
**Version**: 1.0.0
