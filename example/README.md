# n8n User Manager - Simple Demo

A minimal web app demonstrating n8n user management via API.

## Setup

1. **Copy environment file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your n8n server details:**
   ```env
   N8N_API_URL=https://your-n8n-server.com
   N8N_ADMIN_EMAIL=admin@example.com
   N8N_ADMIN_PASSWORD=your-password
   PORT=3001
   ```

3. **Start with Docker:**
   ```bash
   docker-compose up -d
   ```

4. **Open browser:**
   ```
   http://localhost:3001
   ```

## Features

- ✅ Create new n8n users
- ✅ Login existing users
- ✅ List all managed users
- ✅ Load n8n editor in iframe (with limitations)

## Requirements

Your n8n server must have:
- `N8N_USER_MANAGEMENT_DISABLED=false`
- `N8N_BASIC_AUTH_ACTIVE=true` (for admin access)
- An owner account created

## Limitations

- **In-memory storage**: Users are stored in memory (lost on restart)
- **Iframe embedding**: n8n 1.118.2+ uses cookie-based auth which may not work in cross-origin iframes
- **Development only**: Not production-ready (no database, no security hardening)

## Note

This is a **minimal demonstration** only. For production use, you would need:
- Persistent database
- Proper authentication/authorization
- Session management
- Error handling
- Security hardening
