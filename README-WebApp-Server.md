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

### Frontend Dependencies (Next.js)

Add these to your frontend `package.json`:

```json
{
  "dependencies": {
    "next": "14.0.4",
    "react": "^18",
    "react-dom": "^18",
    "typescript": "^5",
    "@types/node": "^20",
    "@types/react": "^18",
    "@types/react-dom": "^18",
    "axios": "^1.6.2",
    "tailwindcss": "^3.3.6"
  }
}
```

### Backend Dependencies (FastAPI)

Add these to your backend `requirements.txt`:

```txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.4.2
pydantic-settings==2.0.3
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.6
sqlalchemy==2.0.23
psycopg2-binary==2.9.9
httpx==0.25.2
python-dotenv==1.0.0
```

## Server Setup

### 1. Environment Configuration

Create a `.env` file in your web app root:

```bash
# =============================================================================
# SERVER ADDRESSES (Only 3 addresses required - URLs auto-derived)
# =============================================================================

# n8n Server
N8N_SERVER_IP="YOUR_N8N_SERVER_IP"              # Your n8n server IP
N8N_SERVER_DOMAIN="n8n.example.com"           # Your n8n domain
# Auto-derived: N8N_WEBHOOK_URL, N8N_EDITOR_BASE_URL

# Web App Server (this server)
WEBAPP_SERVER_IP="YOUR_WEBAPP_IP"
WEBAPP_SERVER_PORT="3001"
# Auto-derived: WEBAPP_DOMAIN, WEBAPP_WEBHOOK_URL, WEBAPP_UPLOAD_URL, WEBAPP_DOWNLOAD_URL

# =============================================================================
# FRONTEND CONFIGURATION (Next.js)
# =============================================================================
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXT_PUBLIC_N8N_URL=https://n8n.example.com
NEXT_PUBLIC_WEBAPP_URL=https://app.example.com

# =============================================================================
# AUTHENTICATION
# =============================================================================
JWT_SECRET=your-super-secure-jwt-secret-here
JWT_EXPIRES_IN=24h

# API Keys (provided by n8n server admin)
N8N_API_KEY=your-n8n-api-key-here
N8N_WEBHOOK_SECRET=your-webhook-secret-here

# =============================================================================
# DATABASE (your existing web app database)
# =============================================================================
DATABASE_URL=postgresql://user:password@localhost:5432/webapp_db

# =============================================================================
# SECURITY
# =============================================================================
CORS_ORIGIN=https://n8n.example.com
IFRAME_ALLOWED_ORIGINS=https://n8n.example.com
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

### 1. FastAPI Authentication Service

Create `backend/app/auth/service.py`:

```python
import httpx
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class AuthService:
    def __init__(self):
        self.n8n_api_url = settings.N8N_API_URL
        self.api_key = settings.N8N_API_KEY
        self.jwt_secret = settings.JWT_SECRET
        
    async def authenticate_user(self, email: str, password: str) -> Optional[Dict[str, Any]]:
        """Authenticate user with local system and get n8n token"""
        try:
            # Step 1: Authenticate with your local system
            local_user = await self._authenticate_local(email, password)
            if not local_user:
                return None
            
            # Step 2: Get n8n authentication token
            n8n_token = await self._get_n8n_token(local_user["id"], email, password)
            
            # Step 3: Generate local JWT
            local_token = self._create_access_token({"sub": str(local_user["id"])})
            
            return {
                "user": local_user,
                "local_token": local_token,
                "n8n_token": n8n_token
            }
        except Exception as e:
            print(f"Authentication error: {e}")
            return None
    
    async def create_user(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create user in both local and n8n systems"""
        try:
            # Create user locally first
            local_user = await self._create_local_user(user_data)
            
            # Create user in n8n
            n8n_user = await self._create_n8n_user({
                "userId": local_user["id"],
                "email": local_user["email"],
                "password": user_data["password"],
                "role": "user"
            })
            
            return {"local_user": local_user, "n8n_user": n8n_user}
        except Exception as e:
            print(f"User creation error: {e}")
            raise

    async def _authenticate_local(self, email: str, password: str) -> Optional[Dict[str, Any]]:
        """Implement your local authentication logic here"""
        # Example implementation - replace with your actual auth logic
        if email == "test@example.com" and password == "password123":
            return {
                "id": 1,
                "email": email,
                "name": "Test User"
            }
        return None
    
    async def _get_n8n_token(self, user_id: int, email: str, password: str) -> str:
        """Get authentication token from n8n server"""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.n8n_api_url}/auth/login",
                json={"userId": user_id, "email": email, "password": password},
                headers={"Content-Type": "application/json"}
            )
            response.raise_for_status()
            return response.json()["token"]
    
    def _create_access_token(self, data: Dict[str, Any]) -> str:
        """Create JWT access token"""
        to_encode = data.copy()
        expire = datetime.utcnow() + timedelta(hours=24)
        to_encode.update({"exp": expire})
        
        return jwt.encode(to_encode, self.jwt_secret, algorithm="HS256")

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

### 2. FastAPI Authentication Router

Create `backend/app/auth/router.py`:

```python
from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import HTTPBearer
from pydantic import BaseModel
from typing import Dict, Any

from .service import auth_service

router = APIRouter()
security = HTTPBearer()

class LoginRequest(BaseModel):
    email: str
    password: str

class RegisterRequest(BaseModel):
    email: str
    password: str
    name: str

class AuthResponse(BaseModel):
    user: Dict[str, Any]
    local_token: str
    n8n_token: str

@router.post("/login", response_model=AuthResponse)
async def login(request: LoginRequest):
    """Authenticate user and return tokens"""
    result = await auth_service.authenticate_user(request.email, request.password)
    
    if not result:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    return AuthResponse(**result)

@router.post("/register")
async def register(request: RegisterRequest):
    """Register new user in both systems"""
    try:
        result = await auth_service.create_user({
            "email": request.email,
            "password": request.password,
            "name": request.name
        })
        return {"message": "User created successfully", "user_id": result["local_user"]["id"]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
```

## Iframe Embedding

### 1. Next.js Frontend Integration

Create `frontend/src/components/N8nEmbed.tsx`:

```typescript
'use client';

import React, { useEffect, useRef, useState } from 'react';
import { useAuth } from '../hooks/useAuth';

interface N8nEmbedProps {
  userId?: number;
  height?: string;
  className?: string;
}

const N8nEmbed: React.FC<N8nEmbedProps> = ({ userId, height = '600px', className = '' }) => {
    const iframeRef = useRef<HTMLIFrameElement>(null);
    const { user, n8nToken } = useAuth();
    const [isReady, setIsReady] = useState(false);
    const [error, setError] = useState<string | null>(null);
    
    useEffect(() => {
        const iframe = iframeRef.current;
        if (!iframe || !n8nToken) return;

        // Set up postMessage communication
        const handleMessage = (event: MessageEvent) => {
            if (event.origin !== process.env.NEXT_PUBLIC_N8N_URL) {
                console.warn('Received message from unauthorized origin:', event.origin);
                return;
            }

            const { type, data } = event.data;

            switch (type) {
                case 'IFRAME_READY':
                    console.log('n8n iframe ready');
                    // Send authentication data to n8n
                    iframe.contentWindow?.postMessage({
                        type: 'AUTH_TOKEN',
                        data: {
                            token: n8nToken,
                            userId: user.id
                        }
                    }, process.env.NEXT_PUBLIC_N8N_URL!);
                    break;
                    
                case 'AUTH_SUCCESS':
                    console.log('n8n authentication successful');
                    setIsReady(true);
                    setError(null);
                    break;

                case 'AUTH_ERROR':
                    console.error('n8n authentication failed:', data);
                    setError('Authentication failed');
                    break;
                    
                case 'WORKFLOW_EXECUTED':
                    console.log('Workflow executed:', data);
                    // Handle workflow execution events
                    break;
                    
                case 'SESSION_REFRESH':
                    console.log('Session refresh requested');
                    // Handle session refresh requests
                    refreshN8nToken();
                    break;

                default:
                    console.log('Unhandled message type:', type);
            }
        };

        window.addEventListener('message', handleMessage);
        
        return () => {
            window.removeEventListener('message', handleMessage);
        };
    }, [n8nToken, user]);

    const refreshN8nToken = async () => {
        try {
            // In a real implementation, you'd refresh the token
            console.log('Refreshing n8n token...');
            // const newToken = await refreshToken();
            // Send updated token to iframe
        } catch (error) {
            console.error('Error refreshing n8n token:', error);
            setError('Session refresh failed');
        }
    };

    if (!user || !n8nToken) {
        return (
            <div className={`flex items-center justify-center bg-gray-100 rounded-lg ${className}`} style={{ height }}>
                <div className="text-center">
                    <p className="text-gray-600">Please log in to access n8n workflows</p>
                </div>
            </div>
        );
    }

    if (error) {
        return (
            <div className={`flex items-center justify-center bg-red-50 border border-red-200 rounded-lg ${className}`} style={{ height }}>
                <div className="text-center">
                    <p className="text-red-600">{error}</p>
                    <button 
                        onClick={() => window.location.reload()} 
                        className="mt-2 px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
                    >
                        Retry
                    </button>
                </div>
            </div>
        );
    }

    const iframeSrc = `${process.env.NEXT_PUBLIC_N8N_URL}/user/${user.id}`;

    return (
        <div className={`relative ${className}`} style={{ height }}>
            {!isReady && (
                <div className="absolute inset-0 flex items-center justify-center bg-white bg-opacity-90 z-10">
                    <div className="text-center">
                        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
                        <p className="mt-2 text-gray-600">Loading n8n...</p>
                    </div>
                </div>
            )}
            <iframe
                ref={iframeRef}
                src={iframeSrc}
                width="100%"
                height="100%"
                frameBorder="0"
                allow="fullscreen"
                sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
                className={`rounded-lg border border-gray-300 ${isReady ? 'block' : 'opacity-50'}`}
                title="n8n Workflow Editor"
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

### 1. FastAPI User Management API Client

Create `backend/app/n8n/client.py`:

```python
import httpx
from typing import Dict, Any, Optional
from app.core.config import settings

class N8nApiClient:
    def __init__(self):
        self.base_url = settings.N8N_API_URL
        self.api_key = settings.N8N_API_KEY
        self.timeout = 10.0
    
    async def _make_request(self, method: str, endpoint: str, **kwargs) -> Dict[str, Any]:
        """Make HTTP request to n8n API"""
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        headers = {
            'X-API-Key': self.api_key,
            'Content-Type': 'application/json'
        }
        
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.request(method, url, headers=headers, **kwargs)
            response.raise_for_status()
            return response.json()

    # User management
    async def create_user(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        return await self._make_request('POST', '/users', json=user_data)

    async def get_user(self, user_id: int) -> Dict[str, Any]:
        return await self._make_request('GET', f'/users/{user_id}')

    async def update_user(self, user_id: int, updates: Dict[str, Any]) -> Dict[str, Any]:
        return await self._make_request('PUT', f'/users/{user_id}', json=updates)

    async def delete_user(self, user_id: int) -> Dict[str, Any]:
        return await self._make_request('DELETE', f'/users/{user_id}')

    # User metrics
    async def get_user_metrics(self, user_id: int) -> Dict[str, Any]:
        return await self._make_request('GET', f'/metrics/users/{user_id}')

    async def get_user_usage(self, user_id: int, period: str = 'daily') -> Dict[str, Any]:
        return await self._make_request('GET', f'/reports/users/{user_id}/{period}')

    # System analytics
    async def get_system_overview(self) -> Dict[str, Any]:
        return await self._make_request('GET', '/reports/system/overview')

n8n_client = N8nApiClient()
```

### 2. FastAPI Webhook Handler

Create `backend/app/n8n/webhooks.py`:

```python
from fastapi import APIRouter, HTTPException, Request
import hashlib
import hmac
from typing import Dict, Any
from app.core.config import settings

router = APIRouter()

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
