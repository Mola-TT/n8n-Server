# n8n Iframe Embedding Example

This example demonstrates how to embed n8n in an iframe within your web application, with automatic session management handled by a proxy server.

## Architecture

```
Browser → Your Proxy Server → n8n Server (with Nginx)
         (this example)      (your n8n installation)
```

The proxy server:
1. Authenticates users via n8n's API
2. Stores session cookies securely (server-side)
3. Proxies all n8n requests, injecting the session cookie
4. Strips headers that would block iframe embedding

Security is handled by:
- n8n server's Nginx configuration (rate limiting, CORS, CSP)
- Proxy server's httpOnly session cookies
- n8n's built-in authentication

## Quick Start

1. Copy the environment template:
   ```bash
   cp env.template .env
   ```

2. Edit `.env` with your n8n server details:
   ```env
   N8N_API_URL=https://your-n8n-server.com
   N8N_ADMIN_EMAIL=admin@example.com
   N8N_ADMIN_PASSWORD=your-admin-password
   ```

3. Run with Docker:
   ```bash
   docker compose up -d
   ```

4. Open http://localhost:3001 and login with an n8n user account

## Configuration

### Required Settings

| Variable | Required | Description |
|----------|----------|-------------|
| `N8N_API_URL` | Yes | URL of your n8n server (e.g., `https://45.76.151.204`) |
| `N8N_ADMIN_EMAIL` | Yes | Admin email for user invitation API |
| `N8N_ADMIN_PASSWORD` | Yes | Admin password |

### Optional Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `N8N_BASIC_AUTH_USER` | - | Basic auth user (if n8n uses it) |
| `N8N_BASIC_AUTH_PASSWORD` | - | Basic auth password |
| `PORT` | 3000 | Server port |
| `USER_MGMT_API_URL` | - | User Management API URL for storage metrics |
| `USER_MGMT_API_KEY` | - | API key for User Management API |

## Production Deployment

For production:
1. Use Redis for session storage (replace the in-memory Map)
2. Set `COOKIE_SECURE=true` for HTTPS
3. Configure proper CORS on your n8n server's Nginx
4. Use a process manager like PM2 or run in Docker

## Files

- `server.js` - Express proxy server
- `public/index.html` - Simple login UI with embedded n8n iframe
- `docker-compose.yml` - Docker configuration
- `env.template` - Environment variable template
