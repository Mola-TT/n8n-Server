# n8n User Management Web Application

A modern, responsive web application for managing n8n users. This application provides a beautiful UI for creating, viewing, updating, and deleting users in your n8n multi-user setup.

## Features

- **User Creation** - Create new n8n users with custom storage quotas
- **User Management** - View, edit, and delete existing users
- **Real-time Analytics** - Monitor total users, active users, storage usage, and workflows
- **User Details** - View detailed information about each user including:
  - Storage usage and quotas
  - Workflow counts
  - Execution statistics
  - Last active timestamps
- **Search & Filter** - Quickly find users by name, email, or ID
- **Password Reset** - Reset user passwords directly from the interface
- **Responsive Design** - Works seamlessly on desktop, tablet, and mobile devices
- **Modern UI** - Beautiful, intuitive interface with smooth animations

## Screenshots

The application features:
- Clean, modern design with card-based layout
- Color-coded status indicators
- Real-time server connection monitoring
- Toast notifications for user feedback
- Modal dialogs for detailed user information
- Analytics dashboard with key metrics

## Installation

### Prerequisites

- A running n8n server with the user management API enabled
- **For Windows Local Development**: Python 3.7+ installed
- **For Docker**: Docker and Docker Compose installed
- Modern web browser (Chrome, Firefox, Safari, Edge)

### Option 1: Windows Local Development (Recommended for Local PC)

**Quick Start:**

```batch
REM Navigate to the example directory
cd example

REM Run the batch script (it will guide you through setup)
serve.bat
```

The batch script will:
1. Check if Python is installed
2. Create `webapp.env` from template if it doesn't exist
3. Prompt you to configure your n8n API settings
4. Start the server on `http://localhost:8080`

**Manual Setup:**

```batch
REM 1. Copy the environment template
copy env.template webapp.env

REM 2. Edit webapp.env with your settings
notepad webapp.env

REM 3. Start the Python server
python serve.py
```

**Or use PowerShell:**

```powershell
# Navigate to the example directory
cd example

# Copy and edit configuration
Copy-Item env.template webapp.env
notepad webapp.env

# Start the server
python serve.py
```

The application will be available at `http://localhost:8080`

### Option 2: Docker Deployment

**Quick Start:**

```bash
# Navigate to the example directory
cd example

# Configure the API connection
# Copy the template and edit webapp.env
cp env.template webapp.env
# Edit webapp.env and set your N8N_API_BASE_URL and N8N_API_KEY

# Build and run with Docker Compose
docker-compose up -d
```

The application will be available at `http://localhost:8080`

**Manual Docker Commands:**

```bash
# Build the Docker image
docker build -t n8n-user-management-example .

# Run the container
docker run -d \
  --name n8n-user-management-example \
  -p 8080:80 \
  --restart unless-stopped \
  n8n-user-management-example
```

**Docker Configuration:**

- **Image Name**: `n8n-user-management-example`
- **Container Name**: `n8n-user-management-example`
- **Port Mapping**: `8080:8080` (host:container)
- **Base Image**: `python:3.11-alpine` (lightweight, ~50MB)
- **Restart Policy**: `unless-stopped`

**Stopping the Container:**

```bash
# Using Docker Compose
docker-compose down

# Using Docker directly
docker stop n8n-user-management-example
docker rm n8n-user-management-example
```

**Viewing Logs:**

```bash
# Using Docker Compose
docker-compose logs -f

# Using Docker directly
docker logs -f n8n-user-management-example
```

**Updating the Application:**

```bash
# Pull latest changes and rebuild
git pull
docker-compose down
docker-compose up -d --build
```

### Option 3: Traditional Web Server Deployment

For production deployments on Linux servers, you can use any web server (Apache, Nginx, etc.):

1. **Copy the files to your web server:**

```bash
# Copy files to your web server's document root
cp -r example /var/www/html/n8n-admin
cd /var/www/html/n8n-admin
```

2. **Configure the API connection:**

```bash
# Copy and edit the environment file
cp env.template webapp.env
nano webapp.env
```

3. **Run the Python server as a service:**

```bash
# Start the server
python3 serve.py

# Or use systemd for production
# Create /etc/systemd/system/n8n-webapp.service
```

4. **Access the application:**

Open your web browser and navigate to:
```
http://your-server:8080/
```

## Configuration

### Environment-Based Configuration

The application uses environment variables for configuration, stored in the `webapp.env` file.

**Configuration File: `webapp.env`**

```bash
# n8n API Configuration
N8N_API_BASE_URL=http://localhost:5678/api/v1
N8N_API_KEY=your-api-key-here

# Application Settings
REFRESH_INTERVAL=30000
DEBUG_MODE=false
```

### Configuration Options

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `N8N_API_BASE_URL` | Base URL for n8n API | `http://localhost:5678/api/v1` | `https://n8n.yourdomain.com/api/v1` |
| `N8N_API_KEY` | API key for authentication | `your-api-key-here` | `n8n_api_abc123...` |
| `REFRESH_INTERVAL` | Auto-refresh interval (ms) | `30000` | `60000` |
| `DEBUG_MODE` | Enable debug logging | `false` | `true` |

### Environment-Specific Configuration

**Local Development:**
```bash
N8N_API_BASE_URL=http://localhost:5678/api/v1
N8N_API_KEY=your-local-api-key
DEBUG_MODE=true
```

**Production:**
```bash
N8N_API_BASE_URL=https://n8n.yourdomain.com/api/v1
N8N_API_KEY=your-production-api-key
DEBUG_MODE=false
```

**Docker Deployment:**

The Docker container automatically reads environment variables from `webapp.env` and injects them into the web application at startup. No need to modify JavaScript files directly.

## API Endpoints

The application expects the following API endpoints to be available:

### Health Check
```
GET /health
```

### User Management
```
GET    /users              - List all users
POST   /users              - Create new user
GET    /users/:userId      - Get user details
DELETE /users/:userId      - Delete user
PUT    /users/:userId/password - Reset user password
```

### Analytics
```
GET /analytics - Get system analytics
```

### Request/Response Examples

**Create User:**
```json
POST /users
{
    "userId": "user123",
    "email": "user@example.com",
    "name": "John Doe",
    "password": "securepassword",
    "storageQuota": 10
}
```

**User Response:**
```json
{
    "userId": "user123",
    "email": "user@example.com",
    "name": "John Doe",
    "storageQuota": 10,
    "storageUsed": 1048576,
    "workflowCount": 5,
    "executionCount": 150,
    "totalExecutionTime": 3600,
    "createdAt": "2025-01-01T00:00:00Z",
    "lastActive": "2025-01-10T12:00:00Z",
    "status": "active"
}
```

## Security Considerations

⚠️ **IMPORTANT SECURITY NOTES:**

1. **Environment File Security**: 
   - Never commit `webapp.env` to version control (it's gitignored by default)
   - Use `env.template` as a reference for required variables
   - Store production credentials securely (e.g., secrets manager, encrypted vault)
   - Rotate API keys regularly

2. **API Key Exposure**: While environment variables improve security, the API key is still exposed in the browser. For production deployments, you should:
   - Implement a backend proxy that handles API authentication
   - Use session-based authentication instead of API keys
   - Store sensitive credentials on the server side

3. **CORS Configuration**: Ensure your n8n server has proper CORS policies configured to allow requests from your web application domain.

4. **HTTPS**: Always use HTTPS in production to encrypt data in transit.

5. **Authentication**: Consider implementing additional authentication layers for the web application itself.

6. **Rate Limiting**: Implement rate limiting on the API to prevent abuse.

## Production Deployment Recommendations

### Using a Backend Proxy

Instead of calling the n8n API directly from the browser, create a backend proxy:

```javascript
// Instead of direct API calls:
fetch('https://n8n-server.com/api/users', {
    headers: { 'X-API-Key': 'secret-key' }
});

// Use a backend proxy:
fetch('/api/users', {
    credentials: 'include' // Use session cookies
});
```

### Nginx Configuration Example

```nginx
server {
    listen 443 ssl;
    server_name admin.yourdomain.com;

    # Serve the web application
    location / {
        root /var/www/html/n8n-admin;
        index index.html;
    }

    # Proxy API requests to n8n server
    location /api/ {
        proxy_pass https://n8n-server.internal/api/;
        proxy_set_header X-API-Key $api_key;
        proxy_set_header Host $host;
    }

    ssl_certificate /etc/letsencrypt/live/admin.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.yourdomain.com/privkey.pem;
}
```

## Customization

### Styling

All styles are contained in `styles.css`. You can customize:

- **Colors**: Modify CSS variables in `:root`
- **Layout**: Adjust grid and flexbox properties
- **Animations**: Modify keyframe animations and transitions
- **Responsive breakpoints**: Update media queries

### Functionality

The main application logic is in `app.js`. You can extend it to:

- Add new user management features
- Implement additional analytics
- Customize data visualization
- Add export/import functionality

## Browser Support

- Chrome/Edge (latest)
- Firefox (latest)
- Safari (latest)
- Opera (latest)

## Troubleshooting

### Connection Issues

**Problem**: "Disconnected" status indicator

**Solutions**:
1. Verify the API base URL in `config.js`
2. Check that the n8n server is running
3. Verify CORS configuration on the n8n server
4. Check browser console for detailed error messages

### Authentication Errors

**Problem**: API requests fail with 401/403 errors

**Solutions**:
1. Verify the API key in `config.js`
2. Check that the API key is valid on the n8n server
3. Ensure the API key has proper permissions

### Users Not Loading

**Problem**: User list shows "Failed to load users"

**Solutions**:
1. Check browser console for error messages
2. Verify the `/users` endpoint is accessible
3. Check network tab for failed requests
4. Verify API response format matches expected structure

## Development

### File Structure

```
example/
├── index.html              # Main HTML structure
├── styles.css              # All styling and responsive design
├── app.js                  # Application logic and API integration
├── env-config.js           # Environment variable loader
├── webapp.env              # Environment configuration (gitignored)
├── env.template            # Environment configuration template
├── serve.py                # Python HTTP server with config injection
├── serve.bat               # Windows batch script to start server
├── Dockerfile              # Docker image configuration
├── docker-compose.yml      # Docker Compose configuration
└── README.md               # This file
```

### Adding New Features

1. **UI Changes**: Modify `index.html` and `styles.css`
2. **Functionality**: Extend the `UserManagementApp` class in `app.js`
3. **API Integration**: Add new methods to handle API calls
4. **Configuration**: Update `config.js` for new settings

## Integration with n8n Server

This web application is designed to work with the n8n server scripts from the main project:

- `setup/user_management_api.sh` - Provides the REST API endpoints
- `setup/multi_user_config.sh` - Configures multi-user architecture
- `setup/user_monitoring.sh` - Provides analytics data

Ensure these components are properly configured on your n8n server before using this web application.

## Support

For issues related to:
- **Web Application**: Check browser console and network requests
- **API Integration**: Verify n8n server configuration and API endpoints
- **Server Setup**: Refer to the main n8n-server project documentation

## License

This web application is part of the n8n-server project and follows the same license terms.

## Contributing

Contributions are welcome! Please follow the project's coding standards:
- Minimal, clean code
- Direct implementation
- Proper documentation
- Responsive design principles

## Docker Details

### Container Specifications

- **Base Image**: `python:3.11-alpine` (~50MB compressed)
- **Exposed Port**: 8080
- **Health Check**: Automatic health monitoring every 30 seconds
- **Restart Policy**: Automatically restarts unless manually stopped
- **Network**: Uses `n8n-network` bridge network for container communication
- **Server**: Python built-in HTTP server with config injection

### Customizing Docker Configuration

**Change Port Mapping:**

Edit `docker-compose.yml`:
```yaml
ports:
  - "3000:8080"  # Access on port 3000 instead of 8080
```

**Connect to Existing n8n Network:**

If you have an existing n8n Docker setup, connect to the same network:
```yaml
networks:
  n8n-network:
    external: true  # Use existing network
```

**Add Environment Variables:**

```yaml
environment:
  - TZ=America/New_York
  - CUSTOM_VAR=value
```

### Building for Different Architectures

The Dockerfile uses `python:3.11-alpine` which supports multiple architectures:

```bash
# Build for ARM64 (e.g., Raspberry Pi, Apple Silicon)
docker buildx build --platform linux/arm64 -t n8n-user-management-example .

# Build for AMD64 (standard x86_64)
docker buildx build --platform linux/amd64 -t n8n-user-management-example .

# Build multi-platform image
docker buildx build --platform linux/amd64,linux/arm64 -t n8n-user-management-example .
```

## Windows Local Development

### Running the Server

**Using the Batch Script (Easiest):**

Simply double-click `serve.bat` or run it from Command Prompt:

```batch
serve.bat
```

**Using Python Directly:**

```batch
python serve.py
```

**Using PowerShell:**

```powershell
python serve.py
```

### Changing the Port

By default, the server runs on port 8080. To change it:

```batch
set PORT=3000
python serve.py
```

Or in PowerShell:

```powershell
$env:PORT=3000
python serve.py
```

### Troubleshooting Windows Setup

**Python Not Found:**
- Download and install Python from https://www.python.org/
- Make sure to check "Add Python to PATH" during installation
- Restart your terminal after installation

**Port Already in Use:**
- Change the port using the PORT environment variable
- Or stop the application using that port

**Configuration Not Loading:**
- Make sure `webapp.env` exists in the same directory as `serve.py`
- Check that the file format is correct (KEY=value, one per line)
- Verify there are no special characters or extra spaces

## Version History

- **1.3.0** - Simplified for Windows local development
  - Removed Nginx dependency
  - Added Python HTTP server (`serve.py`)
  - Created Windows batch script (`serve.bat`) for easy startup
  - Simplified Docker setup with Python base image
  - Better suited for local PC development
  - Cross-platform support (Windows, Linux, macOS)

- **1.2.0** - Environment-based configuration
  - Moved configuration to environment variables
  - Added `webapp.env` file for easy configuration
  - Created `env.template` for reference
  - Docker container auto-injects environment variables
  - No need to modify JavaScript files for configuration
  - Improved security by separating config from code

- **1.1.0** - Docker support added
  - Dockerfile for containerized deployment
  - Docker Compose configuration
  - Nginx configuration for production-ready serving
  - Health checks and restart policies
  - Comprehensive Docker documentation
  
- **1.0.0** - Initial release with core user management features
  - User creation, viewing, editing, deletion
  - Real-time analytics dashboard
  - Search and filter functionality
  - Responsive design
  - Toast notifications

