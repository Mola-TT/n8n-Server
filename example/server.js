require('dotenv').config();
const express = require('express');
const axios = require('axios');
const path = require('path');

const app = express();
app.use(express.json());
app.use(express.static('public'));

const N8N_API = process.env.N8N_API_URL;
const ADMIN_EMAIL = process.env.N8N_ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.N8N_ADMIN_PASSWORD;

// In-memory user store (for demo only)
const users = new Map();

// Get admin session
async function getAdminSession() {
  const response = await axios.post(`${N8N_API}/rest/login`, {
    emailOrLdapLoginId: ADMIN_EMAIL,
    password: ADMIN_PASSWORD
  }, {
    withCredentials: true,
    httpsAgent: new (require('https').Agent)({ rejectUnauthorized: false })
  });
  
  const cookies = response.headers['set-cookie'];
  return cookies ? cookies.join('; ') : '';
}

// Create user in n8n
app.post('/api/users/create', async (req, res) => {
  try {
    const { email, password, firstName, lastName } = req.body;
    
    // Get admin session
    const adminCookie = await getAdminSession();
    
    // Create user in n8n
    const createResponse = await axios.post(`${N8N_API}/rest/users`, {
      email,
      password,
      firstName,
      lastName,
      role: 'global:member'
    }, {
      headers: { Cookie: adminCookie },
      httpsAgent: new (require('https').Agent)({ rejectUnauthorized: false })
    });
    
    // Login as new user to get their session
    const loginResponse = await axios.post(`${N8N_API}/rest/login`, {
      emailOrLdapLoginId: email,
      password: password
    }, {
      withCredentials: true,
      httpsAgent: new (require('https').Agent)({ rejectUnauthorized: false })
    });
    
    const userCookie = loginResponse.headers['set-cookie']?.join('; ') || '';
    
    // Store user info
    users.set(email, {
      email,
      firstName,
      lastName,
      n8nCookie: userCookie,
      n8nData: loginResponse.data
    });
    
    res.json({
      success: true,
      message: 'User created successfully',
      user: { email, firstName, lastName }
    });
  } catch (error) {
    console.error('Create user error:', error.response?.data || error.message);
    res.status(500).json({
      success: false,
      error: error.response?.data?.message || error.message
    });
  }
});

// Login user
app.post('/api/users/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    const response = await axios.post(`${N8N_API}/rest/login`, {
      emailOrLdapLoginId: email,
      password: password
    }, {
      withCredentials: true,
      httpsAgent: new (require('https').Agent)({ rejectUnauthorized: false })
    });
    
    const userCookie = response.headers['set-cookie']?.join('; ') || '';
    
    users.set(email, {
      email,
      n8nCookie: userCookie,
      n8nData: response.data
    });
    
    res.json({
      success: true,
      message: 'Login successful',
      user: response.data.data
    });
  } catch (error) {
    console.error('Login error:', error.response?.data || error.message);
    res.status(401).json({
      success: false,
      error: 'Invalid credentials'
    });
  }
});

// Get user's n8n iframe URL
app.get('/api/users/:email/n8n-url', (req, res) => {
  const user = users.get(req.params.email);
  if (!user) {
    return res.status(404).json({ success: false, error: 'User not found' });
  }
  
  res.json({
    success: true,
    n8nUrl: N8N_API,
    cookie: user.n8nCookie
  });
});

// List all users (from memory)
app.get('/api/users', (req, res) => {
  const userList = Array.from(users.values()).map(u => ({
    email: u.email,
    firstName: u.firstName,
    lastName: u.lastName
  }));
  res.json({ success: true, users: userList });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
  console.log(`n8n API: ${N8N_API}`);
});

