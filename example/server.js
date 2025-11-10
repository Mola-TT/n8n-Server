const express = require('express');
const axios = require('axios');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = 3000;

const N8N_API_URL = process.env.N8N_API_URL || 'https://n8n.example.com';
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';
const N8N_ADMIN_JWT_TOKEN = process.env.N8N_ADMIN_JWT_TOKEN;
const N8N_ADMIN_API_KEY = process.env.N8N_ADMIN_API_KEY;
const N8N_BASIC_AUTH_USER = process.env.N8N_BASIC_AUTH_USER;
const N8N_BASIC_AUTH_PASSWORD = process.env.N8N_BASIC_AUTH_PASSWORD;

// In-memory user store (replace with database in production)
const users = new Map();

// Cache for admin credentials
let cachedAdminJWT = N8N_ADMIN_JWT_TOKEN;
let cachedAdminApiKey = N8N_ADMIN_API_KEY;

// Function to get admin JWT token (login with Basic Auth if needed)
async function getAdminJWT() {
  // Return cached JWT if available
  if (cachedAdminJWT) {
    return cachedAdminJWT;
  }

  // Try to get JWT using Basic Auth credentials
  if (N8N_BASIC_AUTH_USER && N8N_BASIC_AUTH_PASSWORD) {
    try {
      console.log('Logging in to n8n as admin:', N8N_BASIC_AUTH_USER);
      
      const response = await axios.post(
        `${N8N_API_URL}/rest/login`,
        {
          emailOrLdapLoginId: N8N_BASIC_AUTH_USER,
          password: N8N_BASIC_AUTH_PASSWORD
        },
        {
          headers: {
            'Content-Type': 'application/json'
          }
        }
      );
      
      cachedAdminJWT = response.data.data?.token || response.data.token;
      console.log('✓ Got admin JWT token via login');
      return cachedAdminJWT;
    } catch (error) {
      if (error.response?.status === 404) {
        console.warn('⚠️  n8n login endpoint not found (JWT-only mode?)');
        console.warn('   You need to provide N8N_ADMIN_JWT_TOKEN manually in .env');
        console.warn('   Visit: http://localhost:3001/admin-setup.html');
      } else {
        console.error('❌ Could not login to n8n:');
        console.error('Status:', error.response?.status);
        console.error('Error:', error.response?.data || error.message);
        console.error('User:', N8N_BASIC_AUTH_USER);
      }
    }
  }

  return null;
}

// Function to get or create admin API key
async function getAdminApiKey() {
  // Return cached API key if available
  if (cachedAdminApiKey) {
    return cachedAdminApiKey;
  }

  // Get admin JWT token first
  const adminJWT = await getAdminJWT();
  if (!adminJWT) {
    console.error('Cannot get API key without admin JWT token');
    return null;
  }

  // Try to get API key using admin JWT token
  try {
    console.log('Getting admin API key using JWT token...');
    
    const response = await axios.post(
      `${N8N_API_URL}/api/v1/me/api-key`,
      {},
      {
        headers: {
          'Authorization': `Bearer ${adminJWT}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    cachedAdminApiKey = response.data.data?.apiKey || response.data.apiKey;
    console.log('✓ Got admin API key automatically');
    return cachedAdminApiKey;
  } catch (error) {
    console.error('❌ Could not get admin API key:');
    console.error('Status:', error.response?.status);
    console.error('Error:', error.response?.data || error.message);
  }

  return null;
}

// Initialize admin credentials on startup
(async function initializeAdmin() {
  console.log('\n' + '='.repeat(60));
  console.log('Initializing n8n admin credentials...');
  console.log('='.repeat(60));
  
  if (cachedAdminApiKey) {
    console.log('✓ Using N8N_ADMIN_API_KEY from environment');
  } else if (cachedAdminJWT) {
    console.log('✓ Using N8N_ADMIN_JWT_TOKEN from environment');
    await getAdminApiKey();
  } else if (N8N_BASIC_AUTH_USER && N8N_BASIC_AUTH_PASSWORD) {
    console.log('→ Attempting auto-login with credentials...');
    const jwt = await getAdminJWT();
    if (jwt) {
      await getAdminApiKey();
    } else {
      console.log('\n' + '⚠️  AUTO-LOGIN FAILED'.padStart(40));
      console.log('   Your n8n appears to be in JWT-only mode.');
      console.log('   Please provide admin JWT token manually:');
      console.log('   1. Visit: http://localhost:3001/admin-setup.html');
      console.log('   2. Enter your n8n credentials');
      console.log('   3. Copy the JWT token to .env file');
      console.log('   4. Restart: docker-compose restart\n');
    }
  } else {
    console.warn('⚠️  No admin credentials configured!');
    console.warn('   Add N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD to .env');
    console.warn('   OR visit: http://localhost:3001/admin-setup.html');
  }
  
  console.log('='.repeat(60) + '\n');
})();

app.use(express.json());
app.use(express.static('public'));

// Middleware to verify JWT token
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ success: false, error: 'No token provided' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ success: false, error: 'Invalid token' });
    }
    req.user = user;
    next();
  });
}

// User registration - creates user in both webapp and n8n
app.post('/api/auth/register', async (req, res) => {
  const { username, email, password } = req.body;

  if (!username || !email || !password) {
    return res.status(400).json({ success: false, error: 'Username, email, and password required' });
  }

  if (users.has(username)) {
    return res.status(409).json({ success: false, error: 'User already exists' });
  }

  if (!N8N_ADMIN_API_KEY && !N8N_ADMIN_JWT_TOKEN && (!N8N_BASIC_AUTH_USER || !N8N_BASIC_AUTH_PASSWORD)) {
    return res.status(500).json({
      success: false,
      error: 'Admin credentials not configured',
      hint: 'Add N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD to .env file'
    });
  }

  try {
    console.log('Creating n8n user:', email);
    
    // Step 1: Get admin API key (automatically if needed)
    const adminApiKey = await getAdminApiKey();
    
    // Create user in n8n with admin API key
    const headers = {
      'Content-Type': 'application/json'
    };
    
    if (adminApiKey) {
      headers['X-N8N-API-KEY'] = adminApiKey;
      console.log('Using admin API key');
    } else {
      return res.status(500).json({
        success: false,
        error: 'Could not get admin API key',
        hint: 'Check N8N_ADMIN_JWT_TOKEN is valid'
      });
    }
    
    const n8nUserResponse = await axios.post(
      `${N8N_API_URL}/api/v1/users`,
      {
        email: email,
        firstName: username,
        lastName: '',
        password: password,
        role: 'global:member'
      },
      { headers }
    );

    const n8nUserId = n8nUserResponse.data.id;
    console.log('✓ Created n8n user:', n8nUserId);

    // Step 2: Login as new user to get their JWT token
    const loginResponse = await axios.post(
      `${N8N_API_URL}/rest/login`,
      {
        emailOrLdapLoginId: email,
        password: password
      },
      {
        headers: { 'Content-Type': 'application/json' }
      }
    );

    const userJWT = loginResponse.data.data?.token || loginResponse.data.token;
    console.log('✓ Got user JWT token');

    // Step 3: Create API key for new user using their JWT
    let userApiKey = null;
    try {
      const apiKeyResponse = await axios.post(
        `${N8N_API_URL}/api/v1/me/api-key`,
        {},
        {
          headers: {
            'Authorization': `Bearer ${userJWT}`,
            'Content-Type': 'application/json'
          }
        }
      );
      userApiKey = apiKeyResponse.data.data?.apiKey || apiKeyResponse.data.apiKey;
      console.log('✓ Created user API key');
    } catch (apiError) {
      console.warn('Could not create API key:', apiError.response?.data?.message || apiError.message);
    }

    // Store user in webapp with n8n credentials
    const userId = `user_${Date.now()}`;
    const user = { 
      userId, 
      username, 
      email, 
      password, // In production, hash this!
      n8nUserId,
      n8nJWT: userJWT,
      n8nApiKey: userApiKey,
      createdAt: new Date().toISOString() 
    };
    users.set(username, user);

    // Generate webapp JWT token
    const token = jwt.sign(
      { 
        userId, 
        username, 
        email, 
        n8nUserId,
        n8nJWT: userJWT,
        n8nApiKey: userApiKey
      },
      JWT_SECRET,
      { expiresIn: '7d' }
    );

    res.json({
      success: true,
      user: { userId, username, email, n8nUserId },
      token,
      n8nCredentials: {
        email: email,
        password: password,
        jwtToken: userJWT,
        apiKey: userApiKey
      },
      message: 'User created successfully in both webapp and n8n'
    });
  } catch (error) {
    console.error('Error creating user:', error.response?.data || error.message);
    res.status(error.response?.status || 500).json({
      success: false,
      error: error.response?.data?.message || error.message,
      hint: error.response?.status === 401 ? 'Check N8N_ADMIN_JWT_TOKEN is valid' : 'Failed to create user in n8n'
    });
  }
});

// User login - authenticates against n8n
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ success: false, error: 'Username and password required' });
  }

  const user = users.get(username);
  if (!user) {
    return res.status(404).json({ success: false, error: 'User not found' });
  }

  try {
    // Verify credentials with n8n by logging in
    const loginResponse = await axios.post(
      `${N8N_API_URL}/rest/login`,
      {
        emailOrLdapLoginId: user.email,
        password: password
      },
      {
        headers: { 'Content-Type': 'application/json' }
      }
    );

    const userJWT = loginResponse.data.data?.token || loginResponse.data.token;
    console.log('User authenticated with n8n:', user.email);

    // Update stored JWT if changed
    user.n8nJWT = userJWT;
    users.set(username, user);

    // Generate webapp JWT token
    const token = jwt.sign(
      { 
        userId: user.userId, 
        username: user.username, 
        email: user.email,
        n8nUserId: user.n8nUserId,
        n8nJWT: userJWT,
        n8nApiKey: user.n8nApiKey
      },
      JWT_SECRET,
      { expiresIn: '7d' }
    );

    res.json({
      success: true,
      user: { 
        userId: user.userId, 
        username: user.username, 
        email: user.email,
        n8nUserId: user.n8nUserId
      },
      token,
      n8nCredentials: {
        jwtToken: userJWT,
        apiKey: user.n8nApiKey
      },
      n8nLoginUrl: `${N8N_API_URL}/signin?email=${encodeURIComponent(user.email)}`
    });
  } catch (error) {
    console.error('Login error:', error.response?.data || error.message);
    res.status(401).json({
      success: false,
      error: 'Invalid credentials'
    });
  }
});

// Get current user info
app.get('/api/auth/me', authenticateToken, (req, res) => {
  res.json({
    success: true,
    user: req.user
  });
});

// List all users (admin endpoint)
app.get('/api/users', (req, res) => {
  const userList = Array.from(users.values()).map(u => ({
    userId: u.userId,
    username: u.username,
    email: u.email,
    createdAt: u.createdAt
  }));
  
  res.json({
    success: true,
    users: userList,
    count: userList.length
  });
});

// Debug endpoint to test n8n connection
app.get('/api/debug/n8n-connection', async (req, res) => {
  const debug = {
    N8N_API_URL,
    hasBasicAuthUser: !!N8N_BASIC_AUTH_USER,
    hasBasicAuthPassword: !!N8N_BASIC_AUTH_PASSWORD,
    hasAdminJWT: !!N8N_ADMIN_JWT_TOKEN,
    hasAdminApiKey: !!N8N_ADMIN_API_KEY,
    hasCachedJWT: !!cachedAdminJWT,
    hasCachedApiKey: !!cachedAdminApiKey,
    jwtPreview: cachedAdminJWT ? cachedAdminJWT.substring(0, 20) + '...' : 'NOT SET'
  };

  // Test cached JWT token
  if (cachedAdminJWT) {
    try {
      const response = await axios.get(
        `${N8N_API_URL}/api/v1/me`,
        {
          headers: {
            'Authorization': `Bearer ${cachedAdminJWT}`
          }
        }
      );
      debug.jwtTokenValid = true;
      debug.adminUser = response.data;
    } catch (error) {
      debug.jwtTokenValid = false;
      debug.jwtError = error.response?.data || error.message;
    }
  } else if (N8N_BASIC_AUTH_USER && N8N_BASIC_AUTH_PASSWORD) {
    debug.message = 'No cached JWT. Will auto-login on first user registration.';
  }

  res.json(debug);
});

// Admin setup with JWT token directly
app.post('/api/admin/setup-with-token', async (req, res) => {
  const { jwtToken } = req.body;

  if (!jwtToken) {
    return res.status(400).json({
      success: false,
      error: 'JWT token required'
    });
  }

  try {
    console.log('Admin setup: Verifying JWT token...');
    
    // Verify token by trying to use it
    const verifyResponse = await axios.get(
      `${N8N_API_URL}/api/v1/me`,
      {
        headers: {
          'Authorization': `Bearer ${jwtToken}`,
          'Content-Type': 'application/json'
        }
      }
    );

    console.log('✓ JWT token is valid');

    // Try to get API key with the JWT token
    let adminApiKey = null;
    try {
      const apiKeyResponse = await axios.post(
        `${N8N_API_URL}/api/v1/me/api-key`,
        {},
        {
          headers: {
            'Authorization': `Bearer ${jwtToken}`,
            'Content-Type': 'application/json'
          }
        }
      );
      adminApiKey = apiKeyResponse.data.data?.apiKey || apiKeyResponse.data.apiKey;
      console.log('✓ Got admin API key');
    } catch (apiError) {
      console.warn('Could not get API key:', apiError.response?.data?.message || apiError.message);
    }

    // Cache the credentials
    cachedAdminJWT = jwtToken;
    cachedAdminApiKey = adminApiKey;

    res.json({
      success: true,
      message: 'Admin setup complete with JWT token'
    });
  } catch (error) {
    console.error('Admin setup error:', error.response?.data || error.message);
    res.status(error.response?.status || 500).json({
      success: false,
      error: error.response?.data?.message || error.message,
      hint: error.response?.status === 401 ? 'Invalid JWT token' : 'Failed to verify token with n8n'
    });
  }
});

// Admin setup endpoint - Get JWT token by logging in
app.post('/api/admin/setup', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({
      success: false,
      error: 'Email and password required'
    });
  }

  try {
    console.log('Admin setup: Logging in to n8n as:', email);
    
    // Login to n8n to get admin JWT token
    const loginResponse = await axios.post(
      `${N8N_API_URL}/rest/login`,
      {
        emailOrLdapLoginId: email,
        password: password
      },
      {
        headers: {
          'Content-Type': 'application/json'
        }
      }
    );

    const adminJWT = loginResponse.data.data?.token || loginResponse.data.token;
    console.log('✓ Got admin JWT token');

    // Try to get API key with the JWT token
    let adminApiKey = null;
    try {
      const apiKeyResponse = await axios.post(
        `${N8N_API_URL}/api/v1/me/api-key`,
        {},
        {
          headers: {
            'Authorization': `Bearer ${adminJWT}`,
            'Content-Type': 'application/json'
          }
        }
      );
      adminApiKey = apiKeyResponse.data.data?.apiKey || apiKeyResponse.data.apiKey;
      console.log('✓ Got admin API key');
    } catch (apiError) {
      console.warn('Could not get API key:', apiError.response?.data?.message || apiError.message);
    }

    // Cache the credentials
    cachedAdminApiKey = adminApiKey;

    res.json({
      success: true,
      message: 'Admin setup complete',
      credentials: {
        jwtToken: adminJWT,
        apiKey: adminApiKey
      },
      instructions: {
        step1: 'Copy the JWT token below',
        step2: 'Add to your .env file as N8N_ADMIN_JWT_TOKEN=...',
        step3: 'Restart the container: docker-compose restart'
      }
    });
  } catch (error) {
    console.error('Admin setup error:', error.response?.data || error.message);
    res.status(error.response?.status || 500).json({
      success: false,
      error: error.response?.data?.message || error.message,
      hint: error.response?.status === 401 ? 'Invalid n8n admin credentials' : 'Failed to connect to n8n'
    });
  }
});

// Trigger n8n webhook (requires authentication)
app.post('/api/trigger-workflow', authenticateToken, async (req, res) => {
  const { webhookPath, data } = req.body;
  
  try {
    const headers = {
      'Content-Type': 'application/json'
    };
    
    // Use user's n8n JWT token or API key
    if (req.user.n8nApiKey) {
      headers['X-N8N-API-KEY'] = req.user.n8nApiKey;
      console.log('Using user n8n API key:', req.user.email);
    } else if (req.user.n8nJWT) {
      headers['Authorization'] = `Bearer ${req.user.n8nJWT}`;
      console.log('Using user n8n JWT:', req.user.email);
    } else if (N8N_BASIC_AUTH_USER && N8N_BASIC_AUTH_PASSWORD) {
      const auth = Buffer.from(`${N8N_BASIC_AUTH_USER}:${N8N_BASIC_AUTH_PASSWORD}`).toString('base64');
      headers['Authorization'] = `Basic ${auth}`;
      console.log('Using admin basic auth (fallback)');
    } else {
      console.warn('No n8n authentication configured!');
    }
    
    // Include user context in webhook data
    const webhookData = {
      ...data,
      _user: {
        userId: req.user.userId,
        username: req.user.username,
        email: req.user.email
      }
    };
    
    const response = await axios.post(
      `${N8N_API_URL}/webhook/${webhookPath}`,
      webhookData,
      { headers }
    );
    
    res.json({ success: true, data: response.data });
  } catch (error) {
    console.error('Error triggering n8n webhook:', error.message);
    console.error('Full error:', error.response?.data || error);
    
    const statusCode = error.response?.status || 500;
    let errorMessage = error.response?.data?.message || error.message;
    let hint;
    
    if (error.response?.status === 404) {
      errorMessage = `Webhook not found: ${webhookPath}. Make sure you have created a webhook workflow in n8n with this path.`;
      hint = 'Create a workflow in n8n with a Webhook trigger node using this path';
    } else if (error.response?.status === 401) {
      errorMessage = 'Authentication failed with n8n server. Check N8N_BASIC_AUTH_USER and N8N_BASIC_AUTH_PASSWORD in .env';
      hint = `Current user: ${N8N_BASIC_AUTH_USER || 'NOT SET'}`;
    }
    
    res.status(statusCode).json({ 
      success: false, 
      error: errorMessage,
      webhookUrl: `${N8N_API_URL}/webhook/${webhookPath}`,
      hint
    });
  }
});

// Get n8n workflows for authenticated user
app.get('/api/workflows', authenticateToken, async (req, res) => {
  try {
    const headers = {};
    
    // Use user's n8n API key or JWT
    if (req.user.n8nApiKey) {
      headers['X-N8N-API-KEY'] = req.user.n8nApiKey;
    } else if (req.user.n8nJWT) {
      headers['Authorization'] = `Bearer ${req.user.n8nJWT}`;
    } else {
      return res.status(401).json({
        success: false,
        error: 'User n8n authentication not available. Please login again.'
      });
    }

    const response = await axios.get(
      `${N8N_API_URL}/api/v1/workflows`,
      { headers }
    );

    res.json({ 
      success: true, 
      workflows: response.data.data || response.data,
      user: req.user
    });
  } catch (error) {
    console.error('Error fetching workflows:', error.response?.data || error.message);
    res.status(error.response?.status || 500).json({ 
      success: false, 
      error: error.response?.data?.message || error.message
    });
  }
});

app.listen(PORT, () => {
  console.log(`Web app running on http://localhost:${PORT}`);
  console.log(`Connected to n8n at: ${N8N_API_URL}`);
});

