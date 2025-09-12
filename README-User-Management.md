# n8n Multi-User Management & API Documentation

Comprehensive documentation for JWT authentication, user management, folder structure, monitoring, and API endpoints in the n8n server setup.

## Table of Contents

1. [JWT Authentication](#jwt-authentication)
2. [User Management](#user-management)
3. [User Folder Structure](#user-folder-structure)
4. [User Monitoring & Analytics](#user-monitoring--analytics)
5. [API Endpoints](#api-endpoints)
6. [Security & Permissions](#security--permissions)
7. [Configuration](#configuration)
8. [Troubleshooting](#troubleshooting)

## JWT Authentication

### Overview
The system implements JWT-based authentication for secure user access and session management.

### JWT Configuration
```bash
# Environment variables
JWT_SECRET=your-secure-secret-key
JWT_EXPIRES_IN=24h
JWT_ALGORITHM=HS256
```

### Token Structure
```json
{
  "userId": "john_doe",
  "role": "user",
  "permissions": {
    "read": true,
    "write": true,
    "admin": false
  },
  "iat": 1640995200,
  "exp": 1641081600
}
```

### Authentication Flow
1. **Login**: POST `/api/auth/login` with credentials
2. **Token Response**: Receive JWT token with user data
3. **API Access**: Include token in `Authorization: Bearer <token>` header
4. **Token Refresh**: POST `/api/auth/refresh` to extend session
5. **Logout**: POST `/api/auth/logout` (client-side token removal)

### Token Validation
```javascript
// Middleware automatically validates tokens
app.use('/api/protected', verifyToken, (req, res) => {
  // req.user contains decoded token data
  console.log(req.user.userId, req.user.role);
});
```

## User Management

### User Creation
```bash
# Via API
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "john_doe",
    "email": "john@example.com",
    "password": "securepassword",
    "role": "user"
  }'

# Via Script
/opt/n8n/scripts/provision-user.sh john_doe john@example.com
```

### User Roles
- **user**: Standard user with own data access
- **admin**: Full system access and user management
- **viewer**: Read-only access to own data

### User Status
- **active**: User can login and access system
- **inactive**: User account disabled
- **suspended**: Temporary access restriction
- **deleted**: User marked for cleanup

### User Quotas
```json
{
  "quotas": {
    "storage": "1GB",
    "workflows": 100,
    "executions": 10000,
    "apiCalls": 1000
  }
}
```

## User Folder Structure

### Directory Layout
```
/opt/n8n/
├── users/                          # User data isolation
│   └── {userId}/                   # Per-user directory
│       ├── workflows/              # User workflows
│       ├── credentials/            # User credentials
│       ├── files/                  # User file storage
│       ├── logs/                   # User execution logs
│       ├── temp/                   # Temporary files
│       ├── backups/                # User backups
│       └── user-config.json        # User configuration
├── user-configs/                   # Global user configurations
├── user-sessions/                  # Session management
├── user-logs/                      # Centralized user logs
├── monitoring/                     # User monitoring data
│   ├── metrics/                    # User metrics
│   ├── reports/                    # Generated reports
│   ├── analytics/                  # Analytics data
│   └── alerts/                     # Alert configurations
└── api/                           # API server files
    ├── endpoints/                  # API endpoint modules
    ├── middleware/                 # Authentication middleware
    └── server.js                   # Main API server
```

### User Directory Permissions
```bash
# User directories
chown -R $USER:docker /opt/n8n/users/{userId}
chmod -R 755 /opt/n8n/users/{userId}

# Monitoring directories
chown -R $USER:docker /opt/n8n/monitoring
chmod -R 755 /opt/n8n/monitoring
```

### User Configuration File
```json
{
  "userId": "john_doe",
  "email": "john@example.com",
  "createdAt": "2024-01-01T00:00:00.000Z",
  "lastActivity": "2024-01-01T12:00:00.000Z",
  "status": "active",
  "role": "user",
  "permissions": {
    "read": true,
    "write": true,
    "admin": false
  },
  "quotas": {
    "storage": "1GB",
    "workflows": 100,
    "executions": 10000
  },
  "settings": {
    "timezone": "UTC",
    "theme": "default",
    "notifications": true
  }
}
```

## User Monitoring & Analytics

### Execution Time Tracking
- Real-time workflow execution monitoring
- Performance metrics collection per user
- Execution time analysis and optimization
- Resource usage tracking

### Storage Monitoring
- Per-user storage usage tracking
- Quota enforcement and alerts
- Automated cleanup of temporary files
- Storage optimization recommendations

### Analytics Features
- **Daily Reports**: User activity summaries
- **Weekly Reports**: Performance trends
- **Monthly Reports**: Usage patterns and billing data
- **Real-time Metrics**: Live performance monitoring
- **Usage Trends**: Historical data analysis

### Monitoring Data Structure
```json
{
  "userId": "john_doe",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "metrics": {
    "executions": {
      "total": 150,
      "successful": 145,
      "failed": 5,
      "averageTime": "2.5s"
    },
    "storage": {
      "used": "250MB",
      "quota": "1GB",
      "percentage": 25
    },
    "workflows": {
      "active": 15,
      "total": 20,
      "lastModified": "2024-01-01T10:00:00.000Z"
    }
  }
}
```

### Automated Cleanup
- **Inactive Users**: 90-day cleanup policy
- **Temporary Files**: 7-day retention
- **Execution Logs**: 30-day retention
- **Old Backups**: 60-day retention

## API Endpoints

### Authentication Endpoints

#### Login
```http
POST /api/auth/login
Content-Type: application/json

{
  "userId": "john_doe",
  "password": "securepassword"
}
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "userId": "john_doe",
    "email": "john@example.com",
    "role": "user",
    "permissions": {
      "read": true,
      "write": true,
      "admin": false
    }
  }
}
```

#### Token Validation
```http
GET /api/auth/validate
Authorization: Bearer <jwt_token>
```

#### Token Refresh
```http
POST /api/auth/refresh
Content-Type: application/json

{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### User Management Endpoints

#### Create User
```http
POST /api/users
Authorization: Bearer <admin_token>
Content-Type: application/json

{
  "userId": "new_user",
  "email": "new@example.com",
  "password": "securepassword",
  "role": "user"
}
```

#### List Users
```http
GET /api/users?limit=50&offset=0&status=active
Authorization: Bearer <admin_token>
```

#### Get User
```http
GET /api/users/{userId}
Authorization: Bearer <token>
```

#### Update User
```http
PUT /api/users/{userId}
Authorization: Bearer <token>
Content-Type: application/json

{
  "email": "newemail@example.com",
  "status": "active",
  "quotas": {
    "storage": "2GB",
    "workflows": 200
  }
}
```

#### Delete User
```http
DELETE /api/users/{userId}?backup=true
Authorization: Bearer <admin_token>
```

### Metrics & Analytics Endpoints

#### Get User Metrics
```http
GET /api/metrics/users/{userId}?period=24h
Authorization: Bearer <token>
```

#### Get System Overview
```http
GET /api/reports/system/overview?period=7d
Authorization: Bearer <admin_token>
```

#### Get Usage Trends
```http
GET /api/analytics/usage-trends?period=30d&metric=executions
Authorization: Bearer <admin_token>
```

#### Get User Reports
```http
GET /api/reports/users/{userId}/daily?date=2024-01-01
Authorization: Bearer <token>
```

### Configuration Endpoints

#### Get User Configuration
```http
GET /api/users/{userId}/config
Authorization: Bearer <token>
```

#### Update User Configuration
```http
PUT /api/users/{userId}/config
Authorization: Bearer <token>
Content-Type: application/json

{
  "settings": {
    "timezone": "America/New_York",
    "theme": "dark",
    "notifications": false
  }
}
```

## Security & Permissions

### Permission System
```javascript
// Permission levels
const permissions = {
  read: true,      // Can view own data
  write: true,     // Can modify own data
  admin: false     // Can manage other users
};
```

### Role-Based Access Control
- **User Role**: Access to own data only
- **Admin Role**: Full system access
- **Viewer Role**: Read-only access

### Security Headers
```javascript
// CORS configuration
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true
}));

// Security headers
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'"],
      styleSrc: ["'self'", "'unsafe-inline'"]
    }
  }
}));
```

### Rate Limiting
```javascript
// Rate limiting configuration
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP'
});
```

## Configuration

### Environment Variables
```bash
# JWT Configuration
JWT_SECRET=your-secure-secret-key
JWT_EXPIRES_IN=24h

# API Configuration
API_PORT=3000
API_HOST=localhost
ALLOWED_ORIGINS=http://localhost:3000,https://yourdomain.com

# User Management
MAX_USERS=1000
DEFAULT_USER_QUOTA_STORAGE=1GB
DEFAULT_USER_QUOTA_WORKFLOWS=100

# Monitoring
METRICS_RETENTION_DAYS=90
CLEANUP_INACTIVE_DAYS=90
```

### Docker Configuration
```yaml
# docker-compose.yml additions for multi-user
services:
  n8n:
    environment:
      - N8N_USER_FOLDER=/opt/n8n/users/{userId}
      - N8N_USER_ID={userId}
    volumes:
      - /opt/n8n/users:/opt/n8n/users
      - /opt/n8n/monitoring:/opt/n8n/monitoring
```

### Nginx Configuration
```nginx
# User-specific routing
location /api/users/ {
    proxy_pass http://localhost:3000;
    proxy_set_header X-User-ID $user_id;
    proxy_set_header Authorization $http_authorization;
}

# Rate limiting per user
limit_req_zone $user_id zone=user_api:10m rate=10r/s;
```

## Troubleshooting

### Common Issues

#### JWT Token Errors
```bash
# Check JWT secret configuration
grep JWT_SECRET /opt/n8n/docker/.env

# Verify token format
echo "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." | base64 -d
```

#### User Directory Permissions
```bash
# Fix user directory permissions
sudo chown -R $USER:docker /opt/n8n/users
sudo chmod -R 755 /opt/n8n/users

# Check specific user directory
ls -la /opt/n8n/users/{userId}
```

#### API Server Issues
```bash
# Check API server status
systemctl status n8n-api

# View API logs
tail -f /opt/n8n/logs/api.log

# Test API connectivity
curl -X GET http://localhost:3000/api/health
```

#### Monitoring Data Issues
```bash
# Check monitoring directory
ls -la /opt/n8n/monitoring/

# Verify metrics collection
cat /opt/n8n/monitoring/metrics/{userId}_$(date +%Y-%m-%d).json

# Check cron jobs
crontab -l | grep n8n
```

### Debug Commands
```bash
# User management debug
/opt/n8n/scripts/debug-user.sh {userId}

# API server debug
/opt/n8n/scripts/debug-api.sh

# Monitoring debug
/opt/n8n/scripts/debug-monitoring.sh {userId}
```

### Log Locations
- **API Logs**: `/opt/n8n/logs/api.log`
- **User Logs**: `/opt/n8n/user-logs/{userId}/`
- **Monitoring Logs**: `/opt/n8n/monitoring/logs/`
- **System Logs**: `/var/log/syslog`

### Performance Optimization
```bash
# Monitor resource usage
/opt/n8n/scripts/monitor-resources.sh

# Clean up old data
/opt/n8n/scripts/cleanup-old-data.sh

# Optimize database
/opt/n8n/scripts/optimize-database.sh
```

## Integration Examples

### Web Application Integration
```javascript
// Frontend authentication
const login = async (userId, password) => {
  const response = await fetch('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ userId, password })
  });
  const data = await response.json();
  localStorage.setItem('token', data.token);
  return data.user;
};

// API calls with authentication
const apiCall = async (endpoint, options = {}) => {
  const token = localStorage.getItem('token');
  return fetch(endpoint, {
    ...options,
    headers: {
      ...options.headers,
      'Authorization': `Bearer ${token}`
    }
  });
};
```

### Server-to-Server Integration
```bash
# API key authentication for server communication
curl -X GET http://n8n-server:3000/api/internal/users \
  -H "X-API-Key: your-api-key"
```

This documentation provides comprehensive coverage of the multi-user n8n system, including authentication, user management, monitoring, and API usage. For additional support, refer to the main README.md or contact the system administrator.
