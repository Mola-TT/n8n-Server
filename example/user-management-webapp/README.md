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
- Web server (Apache, Nginx, or any static file server)
- Modern web browser (Chrome, Firefox, Safari, Edge)

### Setup Steps

1. **Copy the files to your web server:**

```bash
# Copy the entire webapp directory to your web server's document root
cp -r user-management-webapp /var/www/html/n8n-admin
```

2. **Configure the API connection:**

Edit `config.js` and update the following values:

```javascript
const API_CONFIG = {
    baseUrl: 'https://your-n8n-domain.com/api/v1',
    apiKey: 'your-api-key-here'
};
```

3. **Set up your n8n server:**

Ensure your n8n server has the user management API enabled. The API should be accessible at the URL you configured in step 2.

4. **Access the application:**

Open your web browser and navigate to:
```
http://your-server/n8n-admin/
```

## Configuration

### API Configuration (`config.js`)

```javascript
const API_CONFIG = {
    // Base URL for the n8n user management API
    baseUrl: 'https://your-n8n-domain.com/api/v1',
    
    // API Key for authentication
    apiKey: 'your-api-key-here',
    
    // Refresh interval (milliseconds)
    refreshInterval: 30000,
    
    // Enable debug logging
    debug: false
};
```

### Environment-Specific Configuration

**Local Development:**
```javascript
API_CONFIG.baseUrl = 'http://localhost:5678/api/v1';
```

**Production with Nginx:**
```javascript
API_CONFIG.baseUrl = 'https://n8n.yourdomain.com/api/v1';
```

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

1. **API Key Exposure**: The current implementation stores the API key in client-side code. For production deployments, you should:
   - Implement a backend proxy that handles API authentication
   - Use session-based authentication instead of API keys
   - Store sensitive credentials on the server side

2. **CORS Configuration**: Ensure your n8n server has proper CORS policies configured to allow requests from your web application domain.

3. **HTTPS**: Always use HTTPS in production to encrypt data in transit.

4. **Authentication**: Consider implementing additional authentication layers for the web application itself.

5. **Rate Limiting**: Implement rate limiting on the API to prevent abuse.

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
user-management-webapp/
├── index.html          # Main HTML structure
├── styles.css          # All styling and responsive design
├── app.js              # Application logic and API integration
├── config.js           # API configuration
└── README.md           # This file
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

## Version History

- **1.0.0** - Initial release with core user management features
  - User creation, viewing, editing, deletion
  - Real-time analytics dashboard
  - Search and filter functionality
  - Responsive design
  - Toast notifications

