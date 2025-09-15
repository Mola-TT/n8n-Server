# n8n Local Development with Docker
## Next.js Frontend + FastAPI Backend Integration

This guide provides step-by-step instructions for setting up a local development environment using Docker to integrate with your remote n8n server running on `n8n.example.com`.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Docker Configuration](#docker-configuration)
4. [Environment Setup](#environment-setup)
5. [FastAPI Backend Setup](#fastapi-backend-setup)
6. [Next.js Frontend Setup](#nextjs-frontend-setup)
7. [n8n Integration](#n8n-integration)
8. [Development Workflow](#development-workflow)
9. [Troubleshooting](#troubleshooting)

## Prerequisites

### Development Machine Requirements

- **Docker Desktop**: Latest version with Docker Compose
- **Node.js**: Version 18.x or newer (for local development)
- **Python**: Version 3.9+ (for FastAPI development)
- **Git**: For version control

### Install Docker Desktop

```bash
# Windows/macOS: Download from https://docker.com/desktop
# Linux (Ubuntu):
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER
# Log out and back in
```

## Project Structure

```
your-webapp/
├── docker-compose.dev.yml
├── .env.development
├── README.md
├── frontend/                   # Next.js application
│   ├── Dockerfile.dev
│   ├── package.json
│   ├── next.config.js
│   ├── src/
│   │   ├── components/
│   │   │   └── N8nEmbed.tsx
│   │   ├── hooks/
│   │   │   └── useAuth.ts
│   │   ├── services/
│   │   │   └── api.ts
│   │   └── pages/
│   │       ├── login.tsx
│   │       └── dashboard.tsx
│   └── public/
├── backend/                    # FastAPI application
│   ├── Dockerfile.dev
│   ├── requirements.txt
│   ├── main.py
│   ├── app/
│   │   ├── __init__.py
│   │   ├── auth/
│   │   │   ├── __init__.py
│   │   │   ├── router.py
│   │   │   └── service.py
│   │   ├── n8n/
│   │   │   ├── __init__.py
│   │   │   ├── client.py
│   │   │   └── webhooks.py
│   │   ├── models/
│   │   │   ├── __init__.py
│   │   │   └── user.py
│   │   └── core/
│   │       ├── __init__.py
│   │       ├── config.py
│   │       └── security.py
└── nginx/                      # Development reverse proxy
    ├── Dockerfile.dev
    └── nginx.dev.conf
```

## Docker Configuration

### 1. Main Docker Compose File

Create `docker-compose.dev.yml`:

```yaml
version: '3.8'

services:
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - ./frontend:/app
      - /app/node_modules
      - /app/.next
    environment:
      - NODE_ENV=development
      - NEXT_PUBLIC_API_URL=http://localhost:8000
      - NEXT_PUBLIC_N8N_URL=https://n8n.example.com
      - NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000
    depends_on:
      - backend
    command: npm run dev
    networks:
      - app-network

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.dev
    ports:
      - "8000:8000"
    volumes:
      - ./backend:/app
    environment:
      - ENVIRONMENT=development
      - DATABASE_URL=postgresql://dev_user:dev_pass@db:5432/webapp_dev
      - N8N_SERVER_URL=https://n8n.example.com
      - N8N_API_URL=https://n8n.example.com/api
      - JWT_SECRET=your-local-development-jwt-secret-here
      - CORS_ORIGINS=http://localhost:3000,https://n8n.example.com
    depends_on:
      - db
      - redis
    command: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
    networks:
      - app-network

  db:
    image: postgres:15
    environment:
      - POSTGRES_USER=dev_user
      - POSTGRES_PASSWORD=dev_pass
      - POSTGRES_DB=webapp_dev
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backend/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - app-network

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - app-network

  nginx:
    build:
      context: ./nginx
      dockerfile: Dockerfile.dev
    ports:
      - "80:80"
    depends_on:
      - frontend
      - backend
    volumes:
      - ./nginx/nginx.dev.conf:/etc/nginx/nginx.conf:ro
    networks:
      - app-network

volumes:
  postgres_data:
  redis_data:

networks:
  app-network:
    driver: bridge
```

### 2. Development Environment Variables

Create `.env.development`:

```bash
# =============================================================================
# LOCAL DEVELOPMENT CONFIGURATION
# =============================================================================

# Application URLs
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXT_PUBLIC_N8N_URL=https://n8n.example.com
NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000

# n8n Server Configuration (Remote)
N8N_SERVER_URL=https://n8n.example.com
N8N_API_URL=https://n8n.example.com/api
N8N_WEBHOOK_URL=https://n8n.example.com/webhook

# Authentication
JWT_SECRET=your-super-secure-local-development-jwt-secret-here
JWT_EXPIRES_IN=24h

# API Keys (get these from your n8n server admin)
N8N_API_KEY=your-n8n-api-key-from-server
N8N_WEBHOOK_SECRET=your-webhook-secret-from-server

# Local Database
DATABASE_URL=postgresql://dev_user:dev_pass@db:5432/webapp_dev
REDIS_URL=redis://redis:6379/0

# CORS Configuration
CORS_ORIGINS=http://localhost:3000,http://localhost:80,https://n8n.example.com

# Development Settings
ENVIRONMENT=development
DEBUG=true
LOG_LEVEL=debug

# SSL Configuration (development uses HTTP)
SSL_ENABLED=false
```

## FastAPI Backend Setup

### 1. Backend Dockerfile

Create `backend/Dockerfile.dev`:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Development command (overridden in docker-compose)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

### 2. Backend Requirements

Create `backend/requirements.txt`:

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
alembic==1.12.1
redis==5.0.1
httpx==0.25.2
python-dotenv==1.0.0
pytest==7.4.3
pytest-asyncio==0.21.1
```

### 3. FastAPI Main Application

Create `backend/main.py`:

```python
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
import uvicorn

from app.core.config import settings
from app.auth.router import router as auth_router
from app.n8n.webhooks import router as webhook_router

app = FastAPI(
    title="n8n Integration API",
    description="FastAPI backend for n8n multi-user integration",
    version="1.0.0",
    docs_url="/docs" if settings.ENVIRONMENT == "development" else None,
    redoc_url="/redoc" if settings.ENVIRONMENT == "development" else None,
)

# CORS middleware for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Trust localhost and n8n domain
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["localhost", "127.0.0.1", "n8n.example.com", "*"]  # * for development
)

# Include routers
app.include_router(auth_router, prefix="/api/auth", tags=["authentication"])
app.include_router(webhook_router, prefix="/webhooks", tags=["webhooks"])

@app.get("/")
async def root():
    return {"message": "n8n Integration API", "environment": settings.ENVIRONMENT}

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "environment": settings.ENVIRONMENT,
        "n8n_server": settings.N8N_SERVER_URL
    }

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.ENVIRONMENT == "development"
    )
```

### 4. Configuration Settings

Create `backend/app/core/config.py`:

```python
from pydantic_settings import BaseSettings
from typing import List
import os

class Settings(BaseSettings):
    # Environment
    ENVIRONMENT: str = "development"
    DEBUG: bool = True
    
    # Application
    APP_NAME: str = "n8n Integration API"
    API_V1_STR: str = "/api/v1"
    
    # Database
    DATABASE_URL: str = "postgresql://dev_user:dev_pass@localhost:5432/webapp_dev"
    
    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"
    
    # JWT
    JWT_SECRET: str = "your-super-secure-jwt-secret-here"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRES_IN: str = "24h"
    
    # n8n Configuration
    N8N_SERVER_URL: str = "https://n8n.example.com"
    N8N_API_URL: str = "https://n8n.example.com/api"
    N8N_API_KEY: str = ""
    N8N_WEBHOOK_SECRET: str = ""
    
    # CORS
    CORS_ORIGINS: List[str] = [
        "http://localhost:3000",
        "http://localhost:80", 
        "https://n8n.example.com"
    ]
    
    class Config:
        env_file = ".env"
        case_sensitive = True

    @property
    def cors_origins_list(self) -> List[str]:
        if isinstance(self.CORS_ORIGINS, str):
            return [origin.strip() for origin in self.CORS_ORIGINS.split(",")]
        return self.CORS_ORIGINS

settings = Settings()
```

### 5. Authentication Service

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
    
    async def _create_local_user(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create user in local database"""
        # Implement your user creation logic here
        hashed_password = pwd_context.hash(user_data["password"])
        
        # Example return - replace with actual database insertion
        return {
            "id": 1,  # Would be generated by database
            "email": user_data["email"],
            "name": user_data.get("name", ""),
            "password_hash": hashed_password
        }
    
    async def _create_n8n_user(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create user in n8n system"""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.n8n_api_url}/users",
                json=user_data,
                headers={
                    "X-API-Key": self.api_key,
                    "Content-Type": "application/json"
                }
            )
            response.raise_for_status()
            return response.json()
    
    def _create_access_token(self, data: Dict[str, Any]) -> str:
        """Create JWT access token"""
        to_encode = data.copy()
        expire = datetime.utcnow() + timedelta(hours=24)
        to_encode.update({"exp": expire})
        
        return jwt.encode(to_encode, self.jwt_secret, algorithm="HS256")
    
    def verify_token(self, token: str) -> Optional[Dict[str, Any]]:
        """Verify JWT token"""
        try:
            payload = jwt.decode(token, self.jwt_secret, algorithms=["HS256"])
            return payload
        except JWTError:
            return None

auth_service = AuthService()
```

### 6. Authentication Router

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

@router.get("/n8n-auth")
async def get_n8n_auth(token: str = Depends(security)):
    """Get n8n authentication data for iframe"""
    user = auth_service.verify_token(token.credentials)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid token")
    
    # In a real implementation, you'd fetch the stored n8n token
    # For now, return mock data
    return {
        "userId": user["sub"],
        "n8nToken": "mock-n8n-token-for-development"
    }
```

## Next.js Frontend Setup

### 1. Frontend Dockerfile

Create `frontend/Dockerfile.dev`:

```dockerfile
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Expose port
EXPOSE 3000

# Development command (overridden in docker-compose)
CMD ["npm", "run", "dev"]
```

### 2. Next.js Configuration

Create `frontend/next.config.js`:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    appDir: true,
  },
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: 'http://backend:8000/api/:path*',
      },
    ];
  },
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          {
            key: 'X-Frame-Options',
            value: 'SAMEORIGIN',
          },
          {
            key: 'Content-Security-Policy',
            value: "frame-ancestors 'self' https://n8n.example.com;",
          },
        ],
      },
    ];
  },
};

module.exports = nextConfig;
```

### 3. Package.json

Create `frontend/package.json`:

```json
{
  "name": "n8n-webapp-frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "14.0.4",
    "react": "^18",
    "react-dom": "^18",
    "typescript": "^5",
    "@types/node": "^20",
    "@types/react": "^18",
    "@types/react-dom": "^18",
    "axios": "^1.6.2",
    "tailwindcss": "^3.3.6",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.32"
  },
  "devDependencies": {
    "eslint": "^8",
    "eslint-config-next": "14.0.4"
  }
}
```

### 4. Authentication Hook

Create `frontend/src/hooks/useAuth.ts`:

```typescript
import { useState, useEffect, createContext, useContext } from 'react';
import { apiClient } from '../services/api';

interface User {
  id: number;
  email: string;
  name: string;
}

interface AuthContextType {
  user: User | null;
  localToken: string | null;
  n8nToken: string | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  loading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};

export const useAuthProvider = (): AuthContextType => {
  const [user, setUser] = useState<User | null>(null);
  const [localToken, setLocalToken] = useState<string | null>(null);
  const [n8nToken, setN8nToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Check for stored tokens on mount
    const storedToken = localStorage.getItem('localToken');
    const storedN8nToken = localStorage.getItem('n8nToken');
    const storedUser = localStorage.getItem('user');

    if (storedToken && storedN8nToken && storedUser) {
      setLocalToken(storedToken);
      setN8nToken(storedN8nToken);
      setUser(JSON.parse(storedUser));
    }
    setLoading(false);
  }, []);

  const login = async (email: string, password: string) => {
    try {
      const response = await apiClient.post('/auth/login', { email, password });
      const { user, local_token, n8n_token } = response.data;

      setUser(user);
      setLocalToken(local_token);
      setN8nToken(n8n_token);

      localStorage.setItem('localToken', local_token);
      localStorage.setItem('n8nToken', n8n_token);
      localStorage.setItem('user', JSON.stringify(user));
    } catch (error) {
      console.error('Login failed:', error);
      throw error;
    }
  };

  const logout = () => {
    setUser(null);
    setLocalToken(null);
    setN8nToken(null);
    localStorage.removeItem('localToken');
    localStorage.removeItem('n8nToken');
    localStorage.removeItem('user');
  };

  return {
    user,
    localToken,
    n8nToken,
    login,
    logout,
    loading,
  };
};

export { AuthContext };
```

### 5. API Client

Create `frontend/src/services/api.ts`:

```typescript
import axios from 'axios';

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';

export const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor to add auth token
apiClient.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('localToken');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response interceptor for error handling
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // Clear local storage and redirect to login
      localStorage.clear();
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);
```

### 6. n8n Embed Component

Create `frontend/src/components/N8nEmbed.tsx`:

```typescript
'use client';

import React, { useEffect, useRef, useState } from 'react';
import { useAuth } from '../hooks/useAuth';

interface N8nEmbedProps {
  height?: string;
  className?: string;
}

const N8nEmbed: React.FC<N8nEmbedProps> = ({ height = '600px', className = '' }) => {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const { user, n8nToken } = useAuth();
  const [isReady, setIsReady] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe || !n8nToken || !user) return;

    const handleMessage = (event: MessageEvent) => {
      // Verify origin is from n8n server
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

## n8n Integration

### 7. Dashboard Page

Create `frontend/src/pages/dashboard.tsx`:

```typescript
'use client';

import React from 'react';
import { useAuth } from '../hooks/useAuth';
import N8nEmbed from '../components/N8nEmbed';

const Dashboard: React.FC = () => {
  const { user, logout } = useAuth();

  if (!user) {
    return <div>Loading...</div>;
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <h1 className="text-2xl font-bold text-gray-900">
              n8n Workflow Dashboard
            </h1>
            <div className="flex items-center space-x-4">
              <span className="text-gray-700">Welcome, {user.name}</span>
              <button
                onClick={logout}
                className="bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700"
              >
                Logout
              </button>
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-xl font-semibold mb-4">Your n8n Workflows</h2>
          <N8nEmbed height="700px" className="w-full" />
        </div>
      </main>
    </div>
  );
};

export default Dashboard;
```

## Development Workflow

### 1. Initial Setup

```bash
# Clone your project
git clone <your-repo>
cd your-webapp

# Copy environment template
cp .env.development.example .env.development

# Edit .env.development with your n8n server details
nano .env.development
```

### 2. Start Development Environment

```bash
# Start all services
docker-compose -f docker-compose.dev.yml up --build

# Or start specific services
docker-compose -f docker-compose.dev.yml up frontend backend

# View logs
docker-compose -f docker-compose.dev.yml logs -f frontend
docker-compose -f docker-compose.dev.yml logs -f backend
```

### 3. Development URLs

- **Frontend**: http://localhost:3000
- **Backend API**: http://localhost:8000
- **Backend Docs**: http://localhost:8000/docs
- **Database**: localhost:5432
- **Redis**: localhost:6379

### 4. Testing n8n Integration

```bash
# Test authentication
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Test n8n connectivity
curl -X GET http://localhost:8000/health
```

### 5. Development Commands

```bash
# Install new frontend dependencies
docker-compose -f docker-compose.dev.yml exec frontend npm install <package>

# Install new backend dependencies
docker-compose -f docker-compose.dev.yml exec backend pip install <package>

# Run database migrations
docker-compose -f docker-compose.dev.yml exec backend alembic upgrade head

# Access database
docker-compose -f docker-compose.dev.yml exec db psql -U dev_user -d webapp_dev

# Restart specific service
docker-compose -f docker-compose.dev.yml restart backend

# Stop all services
docker-compose -f docker-compose.dev.yml down

# Stop and remove volumes
docker-compose -f docker-compose.dev.yml down -v
```

## Troubleshooting

### Common Issues

#### 1. n8n Iframe Not Loading

**Problem**: Iframe shows CORS or CSP errors

**Solution**:
```bash
# Check your n8n server configuration includes localhost domains
# Verify PRODUCTION=false in your n8n server's user.env

# Test iframe access directly
curl -I https://n8n.example.com/user/1
```

#### 2. API Connection Issues

**Problem**: Frontend can't connect to backend

**Solution**:
```bash
# Check backend is running
docker-compose -f docker-compose.dev.yml ps

# Check backend logs
docker-compose -f docker-compose.dev.yml logs backend

# Test API directly
curl http://localhost:8000/health
```

#### 3. Database Connection Issues

**Problem**: Backend can't connect to database

**Solution**:
```bash
# Check database is running
docker-compose -f docker-compose.dev.yml ps db

# Check database logs
docker-compose -f docker-compose.dev.yml logs db

# Test database connection
docker-compose -f docker-compose.dev.yml exec backend python -c "from app.core.config import settings; print(settings.DATABASE_URL)"
```

#### 4. CORS Issues

**Problem**: Browser blocks cross-origin requests

**Solution**:
```typescript
// Add to your Next.js config
async headers() {
  return [
    {
      source: '/api/:path*',
      headers: [
        { key: 'Access-Control-Allow-Origin', value: '*' },
        { key: 'Access-Control-Allow-Methods', value: 'GET,POST,PUT,DELETE,OPTIONS' },
        { key: 'Access-Control-Allow-Headers', value: 'Content-Type,Authorization' },
      ],
    },
  ];
}
```

### Debug Mode

Enable detailed logging:

```bash
# Backend debug
docker-compose -f docker-compose.dev.yml exec backend python -c "import logging; logging.basicConfig(level=logging.DEBUG)"

# Frontend debug
# Add to .env.development:
DEBUG=true
NEXT_PUBLIC_DEBUG=true
```

### Network Testing

```bash
# Test container connectivity
docker-compose -f docker-compose.dev.yml exec frontend curl http://backend:8000/health

# Test external connectivity
docker-compose -f docker-compose.dev.yml exec backend curl https://n8n.example.com/health
```

---

## Next Steps

1. **Configure your n8n server** to allow localhost domains (PRODUCTION=false)
2. **Update API keys** in .env.development with real values from your n8n server
3. **Implement your authentication logic** in the backend
4. **Customize the frontend** to match your app's design
5. **Add error handling** and monitoring
6. **Set up CI/CD pipeline** for deployment

This setup provides a complete local development environment that can securely connect to your remote n8n server while maintaining development efficiency.
