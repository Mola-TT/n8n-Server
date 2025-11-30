require('dotenv').config();
const express = require('express');
const axios = require('axios');
const cookieParser = require('cookie-parser');
const { createProxyMiddleware } = require('http-proxy-middleware');
const { v4: uuidv4 } = require('uuid');
const jwt = require('jsonwebtoken');
const https = require('https');
const path = require('path');

const app = express();
app.use(express.json());
app.use(cookieParser());
app.use(express.static('public'));

const N8N_API = process.env.N8N_API_URL;
const ADMIN_EMAIL = process.env.N8N_ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.N8N_ADMIN_PASSWORD;
const PROXY_COOKIE_NAME = process.env.N8N_PROXY_COOKIE || 'n8n_proxy_session';
const SESSION_JWT_SECRET = process.env.N8N_IFRAME_JWT_SECRET || 'n8n-dev-iframe-secret';
const BASIC_AUTH_USER = process.env.N8N_BASIC_AUTH_USER;
const BASIC_AUTH_PASSWORD = process.env.N8N_BASIC_AUTH_PASSWORD;
const ADMIN_AUTH = process.env.N8N_ADMIN_AUTH_USER && process.env.N8N_ADMIN_AUTH_PASSWORD ? {
  username: process.env.N8N_ADMIN_AUTH_USER,
  password: process.env.N8N_ADMIN_AUTH_PASSWORD
} : (BASIC_AUTH_USER && BASIC_AUTH_PASSWORD ? {
  username: BASIC_AUTH_USER,
  password: BASIC_AUTH_PASSWORD
} : undefined);
const COOKIE_OPTIONS = {
  httpOnly: true,
  sameSite: 'Lax',
  secure: process.env.COOKIE_SECURE === 'true'
};

if (!N8N_API) {
  throw new Error('N8N_API_URL is required for the proxy demo');
}

const httpsAgent = new https.Agent({
  rejectUnauthorized: false
});

const baseAxiosConfig = {
  httpsAgent,
  auth: BASIC_AUTH_USER && BASIC_AUTH_PASSWORD ? {
    username: BASIC_AUTH_USER,
    password: BASIC_AUTH_PASSWORD
  } : undefined
};

// In-memory user store (for demo only)
const users = new Map();
const sessionStore = new Map(); // token -> { email, n8nCookie, lastActive }

function generateIframeToken(email) {
  if (!email) {
    return null;
  }
  return jwt.sign({ email }, SESSION_JWT_SECRET, { expiresIn: '10m' });
}

function issueSession(email, n8nCookie, res) {
  if (!n8nCookie) {
    return null;
  }

  // remove stale sessions for the same email
  for (const [token, session] of sessionStore.entries()) {
    if (session.email === email) {
      sessionStore.delete(token);
    }
  }

  const token = uuidv4();
  sessionStore.set(token, {
    email,
    n8nCookie,
    lastActive: Date.now()
  });
  res.cookie(PROXY_COOKIE_NAME, token, COOKIE_OPTIONS);
  return token;
}

function getSessionForEmail(email) {
  for (const [token, session] of sessionStore.entries()) {
    if (session.email === email) {
      return { token, session };
    }
  }
  return null;
}

function ensureProxySession(req, res, next) {
  const token = req.cookies[PROXY_COOKIE_NAME];
  if (!token) {
    return res.status(401).send('Missing proxy session. Please log in.');
  }

  const session = sessionStore.get(token);
  if (!session) {
    return res.status(401).send('Proxy session expired. Please log in again.');
  }

  session.lastActive = Date.now();
  req.sessionToken = token;
  req.n8nSession = session;
  next();
}

// Get admin session
async function getAdminSession() {
  const response = await axios.post(`${N8N_API}/rest/login`, {
    emailOrLdapLoginId: ADMIN_EMAIL,
    password: ADMIN_PASSWORD
  }, {
    ...baseAxiosConfig,
    withCredentials: true
  });
  
  const cookies = response.headers['set-cookie'];
  return cookies ? cookies.join('; ') : '';
}

// Create user in n8n via invitation flow
app.post('/api/users/create', async (req, res) => {
  try {
    const { email, password, firstName, lastName } = req.body;
    
    // Get admin session
    const adminCookie = await getAdminSession();
    
    // Step 1: Create invitation for the user
    console.log('Creating invitation for:', email);
    const inviteResponse = await axios.post(`${N8N_API}/rest/invitations`, [{
      email,
      role: 'global:member'
    }], {
      ...baseAxiosConfig,
      headers: { Cookie: adminCookie }
    });
    
    console.log('Invite response:', JSON.stringify(inviteResponse.data, null, 2));
    
    // n8n returns: { data: [{ user: { id, email, inviteAcceptUrl }, error: "" }] }
    const inviteResult = inviteResponse.data?.data?.[0];
    const invitation = inviteResult?.user;
    
    if (!invitation?.id) {
      console.error('Invalid invitation response:', inviteResponse.data);
      throw new Error(inviteResult?.error || 'Failed to create invitation - no invitation ID returned');
    }
    
    const inviteAcceptUrl = invitation.inviteAcceptUrl;
    
    // Step 2: Accept the invitation to complete user creation
    // Extract inviterId from URL (format: .../signup?inviterId=xxx&inviteeId=yyy)
    const inviteUrl = new URL(inviteAcceptUrl);
    const inviterId = inviteUrl.searchParams.get('inviterId');
    const inviteeId = invitation.id;
    
    console.log('Accepting invitation:', { inviterId, inviteeId });
    
    const acceptResponse = await axios.post(`${N8N_API}/rest/invitations/${inviteeId}/accept`, {
      inviterId,
      firstName: firstName || email.split('@')[0],
      lastName: lastName || '',
      password
    }, baseAxiosConfig);
    
    console.log('Accept response:', JSON.stringify(acceptResponse.data, null, 2));
    
    // Step 3: Login as new user to get their session
    const loginResponse = await axios.post(`${N8N_API}/rest/login`, {
      emailOrLdapLoginId: email,
      password: password
    }, {
      ...baseAxiosConfig,
      withCredentials: true
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

    const sessionToken = issueSession(email, userCookie, res);
    
    res.json({
      success: true,
      message: 'User created successfully',
      user: { email, firstName, lastName },
      iframeUrl: '/iframe-wrapper.html',
      sessionToken,
      iframeToken: generateIframeToken(email)
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
      ...baseAxiosConfig,
      withCredentials: true
    });
    
    const userCookie = response.headers['set-cookie']?.join('; ') || '';
    
    users.set(email, {
      email,
      n8nCookie: userCookie,
      n8nData: response.data
    });

    const sessionToken = issueSession(email, userCookie, res);
    
    res.json({
      success: true,
      message: 'Login successful',
      user: response.data.data,
      iframeUrl: '/iframe-wrapper.html',
      sessionToken,
      iframeToken: generateIframeToken(email)
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

  let sessionToken = req.cookies[PROXY_COOKIE_NAME];
  if (!sessionToken) {
    sessionToken = issueSession(req.params.email, user.n8nCookie, res);
  }
  
  res.json({
    success: true,
    iframeUrl: '/iframe-wrapper.html',
    sessionToken,
    iframeToken: generateIframeToken(req.params.email)
  });
});

app.post('/api/iframe/session', (req, res) => {
  const { token } = req.body || {};
  if (!token) {
    return res.status(400).json({ success: false, error: 'Missing token' });
  }

  try {
    const payload = jwt.verify(token, SESSION_JWT_SECRET);
    const email = payload.email;
    if (!email) {
      return res.status(400).json({ success: false, error: 'Invalid token payload' });
    }

    let sessionEntry = getSessionForEmail(email);
    if (sessionEntry) {
      res.cookie(PROXY_COOKIE_NAME, sessionEntry.token, COOKIE_OPTIONS);
    } else {
      const user = users.get(email);
      if (!user?.n8nCookie) {
        return res.status(404).json({ success: false, error: 'No active n8n session for user' });
      }
      const sessionToken = issueSession(email, user.n8nCookie, res);
      sessionEntry = { token: sessionToken };
    }

    return res.json({ success: true, email });
  } catch (error) {
    console.error('Iframe session error:', error.message);
    return res.status(401).json({ success: false, error: 'Invalid token' });
  }
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

const proxyMiddleware = createProxyMiddleware({
  target: N8N_API,
  changeOrigin: true,
  ws: true,
  logLevel: 'debug',
  secure: false,
  agent: httpsAgent,
  pathRewrite: (pathStr) => pathStr.replace(/^\/n8n/, ''),
  onProxyReq: (proxyReq, req) => {
    console.log(`[PROXY] ${req.method} ${req.url} -> ${N8N_API}${req.url.replace(/^\/n8n/, '')}`);
    if (req.n8nSession?.n8nCookie) {
      proxyReq.setHeader('Cookie', req.n8nSession.n8nCookie);
    }
    // Pass through basic auth if configured
    if (BASIC_AUTH_USER && BASIC_AUTH_PASSWORD) {
      const auth = Buffer.from(`${BASIC_AUTH_USER}:${BASIC_AUTH_PASSWORD}`).toString('base64');
      proxyReq.setHeader('Authorization', `Basic ${auth}`);
    }
  },
  onProxyRes: (proxyRes, req) => {
    console.log(`[PROXY RES] ${req.url} -> ${proxyRes.statusCode}`);
    
    // Remove headers that block iframe embedding
    delete proxyRes.headers['x-frame-options'];
    delete proxyRes.headers['content-security-policy'];
    delete proxyRes.headers['content-security-policy-report-only'];
    
    // Update cookies from n8n
    const setCookie = proxyRes.headers['set-cookie'];
    if (setCookie && req.sessionToken) {
      sessionStore.set(req.sessionToken, {
        email: req.n8nSession.email,
        n8nCookie: setCookie.join('; '),
        lastActive: Date.now()
      });
    }
  },
  onError: (err, req, res) => {
    console.error(`[PROXY ERROR] ${req.url}:`, err.message);
    res.status(502).json({ error: 'Proxy error', message: err.message });
  }
});

app.use('/n8n', ensureProxySession, proxyMiddleware);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
  console.log(`n8n API: ${N8N_API}`);
});

