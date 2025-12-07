/**
 * n8n Iframe Embedding Example - Proxy Server
 * 
 * This is a minimal example demonstrating how to embed n8n in an iframe
 * with automatic session management. Security is handled server-side.
 */
require('dotenv').config();
const express = require('express');
const axios = require('axios');
const cookieParser = require('cookie-parser');
const { createProxyMiddleware } = require('http-proxy-middleware');
const { v4: uuidv4 } = require('uuid');
const https = require('https');

const app = express();
app.use(express.json());
app.use(cookieParser());

// Configuration from environment
const N8N_API = process.env.N8N_API_URL;
const ADMIN_EMAIL = process.env.N8N_ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.N8N_ADMIN_PASSWORD;
const PROXY_COOKIE_NAME = process.env.N8N_PROXY_COOKIE || 'n8n_proxy_session';
const BASIC_AUTH_USER = process.env.N8N_BASIC_AUTH_USER;
const BASIC_AUTH_PASSWORD = process.env.N8N_BASIC_AUTH_PASSWORD;

const COOKIE_OPTIONS = {
  httpOnly: true,
  sameSite: 'Lax',
  secure: process.env.COOKIE_SECURE === 'true',
  maxAge: 7 * 24 * 60 * 60 * 1000 // 7 days
};

if (!N8N_API) {
  throw new Error('N8N_API_URL environment variable is required');
}

// HTTPS agent for self-signed certificates (dev only)
const httpsAgent = new https.Agent({ rejectUnauthorized: false });

const axiosConfig = {
  httpsAgent,
  auth: BASIC_AUTH_USER && BASIC_AUTH_PASSWORD 
    ? { username: BASIC_AUTH_USER, password: BASIC_AUTH_PASSWORD } 
    : undefined
};

// Session storage (use Redis in production)
const sessionStore = new Map();

// Parse Set-Cookie headers to Cookie header format
function parseSetCookies(headers) {
  if (!headers?.length) return '';
  return headers.map(c => c.split(';')[0]).join('; ');
}

// Create or update session
function createSession(email, n8nCookie, res) {
  if (!n8nCookie) return null;
  
  // Remove existing sessions for this user
  for (const [t, s] of sessionStore.entries()) {
    if (s.email === email) sessionStore.delete(t);
  }
  
  const token = uuidv4();
  sessionStore.set(token, { email, n8nCookie, lastActive: Date.now() });
  res.cookie(PROXY_COOKIE_NAME, token, COOKIE_OPTIONS);
  return token;
}

// Get admin session for user management
async function getAdminSession() {
  const response = await axios.post(`${N8N_API}/rest/login`, {
    emailOrLdapLoginId: ADMIN_EMAIL,
    password: ADMIN_PASSWORD
  }, { ...axiosConfig, withCredentials: true });
  return parseSetCookies(response.headers['set-cookie']);
}

// Serve static files
app.use(express.static('public'));

// Create user via n8n invitation flow
app.post('/api/users/create', async (req, res) => {
  try {
    const { email, password, firstName, lastName } = req.body;
    const adminCookie = await getAdminSession();
    
    // Try to create invitation
    const inviteRes = await axios.post(`${N8N_API}/rest/invitations`, 
      [{ email, role: 'global:member' }],
      { ...axiosConfig, headers: { Cookie: adminCookie } }
    );
    
    const invitation = inviteRes.data?.data?.[0]?.user;
    
    // If no invitation returned, user may exist - try login
    if (!invitation?.id) {
      const loginRes = await axios.post(`${N8N_API}/rest/login`, {
        emailOrLdapLoginId: email, password
      }, { ...axiosConfig, withCredentials: true });
      
      const cookie = parseSetCookies(loginRes.headers['set-cookie']);
      createSession(email, cookie, res);
      return res.json({ success: true, user: loginRes.data.data });
    }
    
    // Accept invitation
    const url = new URL(invitation.inviteAcceptUrl);
    await axios.post(`${N8N_API}/rest/invitations/${invitation.id}/accept`, {
      inviterId: url.searchParams.get('inviterId'),
      firstName: firstName || email.split('@')[0],
      lastName: lastName || '',
      password
    }, axiosConfig);
    
    // Login new user
    const loginRes = await axios.post(`${N8N_API}/rest/login`, {
      emailOrLdapLoginId: email, password
    }, { ...axiosConfig, withCredentials: true });
    
    const cookie = parseSetCookies(loginRes.headers['set-cookie']);
    createSession(email, cookie, res);
    res.json({ success: true, user: { email, firstName, lastName } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Login existing user
app.post('/api/users/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const response = await axios.post(`${N8N_API}/rest/login`, {
      emailOrLdapLoginId: email, password
    }, { ...axiosConfig, withCredentials: true });
    
    const cookie = parseSetCookies(response.headers['set-cookie']);
    createSession(email, cookie, res);
    res.json({ success: true, user: response.data.data });
  } catch (error) {
    res.status(401).json({ success: false, error: 'Invalid credentials' });
  }
});

// List users (demo only - returns empty since we don't persist)
app.get('/api/users', (req, res) => {
  res.json({ success: true, users: [] });
});

// Get current user's usage metrics
app.get('/api/usage', async (req, res) => {
  try {
    const token = req.cookies[PROXY_COOKIE_NAME];
    if (!token) {
      return res.status(401).json({ success: false, error: 'Not authenticated' });
    }
    
    const session = sessionStore.get(token);
    if (!session) {
      return res.status(401).json({ success: false, error: 'Session not found' });
    }
    
    const headers = { Cookie: session.n8nCookie };
    
    // Get user info from n8n - try multiple endpoints for compatibility
    let user = { id: 'unknown', email: session.email, firstName: '', lastName: '' };
    try {
      const userRes = await axios.get(`${N8N_API}/rest/users/me`, { ...axiosConfig, headers });
      user = userRes.data.data || userRes.data;
    } catch (e) {
      try {
        const userRes = await axios.get(`${N8N_API}/rest/me`, { ...axiosConfig, headers });
        user = userRes.data.data || userRes.data;
      } catch (e2) {
        console.log('Could not fetch user info, using session email');
      }
    }
    
    // Get executions data from n8n
    let executions = [];
    try {
      const executionsRes = await axios.get(`${N8N_API}/rest/executions`, {
        ...axiosConfig,
        headers,
        params: { limit: 100 }
      });
      const execData = executionsRes.data;
      // Handle different n8n API response formats
      if (Array.isArray(execData)) {
        executions = execData;
      } else if (Array.isArray(execData.data)) {
        executions = execData.data;
      } else if (Array.isArray(execData.results)) {
        executions = execData.results;
      } else if (execData.data && Array.isArray(execData.data.results)) {
        executions = execData.data.results;
      } else {
        console.log('Unexpected executions format:', JSON.stringify(execData).slice(0, 200));
        executions = [];
      }
    } catch (e) {
      console.log('Could not fetch executions:', e.message);
    }
    
    // Calculate metrics
    const totalExecutions = executions.length;
    const successfulExecutions = executions.filter(e => e.status === 'success' || e.finished === true).length;
    const failedExecutions = executions.filter(e => e.status === 'error' || e.status === 'crashed' || e.status === 'failed').length;
    const runningExecutions = executions.filter(e => e.status === 'running' || e.status === 'waiting').length;
    
    // Calculate total execution time
    let totalExecutionTime = 0;
    executions.forEach(e => {
      if (e.startedAt && e.stoppedAt) {
        totalExecutionTime += new Date(e.stoppedAt) - new Date(e.startedAt);
      }
    });
    
    // Get workflows count
    let workflows = [];
    try {
      const workflowsRes = await axios.get(`${N8N_API}/rest/workflows`, { ...axiosConfig, headers });
      const wfData = workflowsRes.data;
      if (Array.isArray(wfData)) {
        workflows = wfData;
      } else if (Array.isArray(wfData.data)) {
        workflows = wfData.data;
      } else if (wfData.data && Array.isArray(wfData.data.workflows)) {
        workflows = wfData.data.workflows;
      } else {
        console.log('Unexpected workflows format:', JSON.stringify(wfData).slice(0, 200));
        workflows = [];
      }
    } catch (e) {
      console.log('Could not fetch workflows:', e.message);
    }
    
    const activeWorkflows = workflows.filter(w => w.active).length;
    
    // Group executions by day for chart
    const executionsByDay = {};
    executions.forEach(e => {
      if (!e.startedAt) return;
      const date = new Date(e.startedAt).toISOString().split('T')[0];
      if (!executionsByDay[date]) {
        executionsByDay[date] = { total: 0, success: 0, failed: 0 };
      }
      executionsByDay[date].total++;
      if (e.status === 'success' || e.finished === true) executionsByDay[date].success++;
      if (e.status === 'error' || e.status === 'crashed' || e.status === 'failed') executionsByDay[date].failed++;
    });
    
    // Recent executions
    const recentExecutions = executions.slice(0, 10).map(e => ({
      id: e.id,
      workflowName: e.workflowData?.name || e.workflowName || 'Unknown',
      status: e.status || (e.finished ? 'success' : 'unknown'),
      startedAt: e.startedAt,
      stoppedAt: e.stoppedAt,
      duration: e.startedAt && e.stoppedAt 
        ? new Date(e.stoppedAt) - new Date(e.startedAt) 
        : null
    }));
    
    res.json({
      success: true,
      user: {
        id: user.id || 'unknown',
        email: user.email || session.email,
        firstName: user.firstName || '',
        lastName: user.lastName || ''
      },
      metrics: {
        executions: {
          total: totalExecutions,
          successful: successfulExecutions,
          failed: failedExecutions,
          running: runningExecutions,
          successRate: totalExecutions > 0 
            ? Math.round((successfulExecutions / totalExecutions) * 100) 
            : 0
        },
        executionTime: {
          totalMs: totalExecutionTime,
          totalFormatted: formatDuration(totalExecutionTime),
          averageMs: totalExecutions > 0 ? Math.round(totalExecutionTime / totalExecutions) : 0
        },
        workflows: {
          total: workflows.length,
          active: activeWorkflows,
          inactive: workflows.length - activeWorkflows
        }
      },
      charts: {
        executionsByDay: Object.entries(executionsByDay)
          .sort((a, b) => a[0].localeCompare(b[0]))
          .slice(-14) // Last 14 days
          .map(([date, data]) => ({ date, ...data }))
      },
      recentExecutions,
      generatedAt: new Date().toISOString()
    });
  } catch (error) {
    console.error('Usage API error:', error.message);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Helper function to format duration
function formatDuration(ms) {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  if (ms < 3600000) return `${Math.floor(ms / 60000)}m ${Math.floor((ms % 60000) / 1000)}s`;
  return `${Math.floor(ms / 3600000)}h ${Math.floor((ms % 3600000) / 60000)}m`;
}

// Proxy middleware configuration
const proxyMiddleware = createProxyMiddleware({
  target: N8N_API,
  changeOrigin: true,
  ws: true,
  secure: false,
  agent: httpsAgent,
  onProxyReq: (proxyReq) => {
    if (BASIC_AUTH_USER && BASIC_AUTH_PASSWORD) {
      const auth = Buffer.from(`${BASIC_AUTH_USER}:${BASIC_AUTH_PASSWORD}`).toString('base64');
      proxyReq.setHeader('Authorization', `Basic ${auth}`);
    }
  },
  onProxyRes: (proxyRes, req) => {
    // Remove headers that block iframe embedding (security handled by server nginx)
    delete proxyRes.headers['x-frame-options'];
    delete proxyRes.headers['content-security-policy'];
    
    // Update session if n8n refreshes cookie
    const setCookie = proxyRes.headers['set-cookie'];
    if (setCookie && req.sessionToken) {
      const session = sessionStore.get(req.sessionToken);
      if (session) {
        session.n8nCookie = parseSetCookies(setCookie);
        session.lastActive = Date.now();
      }
    }
  },
  onError: (err, req, res) => {
    res.status(502).json({ error: 'Proxy error' });
  }
});

// n8n paths to proxy
const N8N_PATHS = ['/assets', '/static', '/home', '/workflow', '/credentials', 
                   '/executions', '/settings', '/rest', '/signin', '/signup', '/favicon.ico'];

// Proxy handler with session injection
app.use((req, res, next) => {
  // Skip proxy for our own API routes
  if (req.path.startsWith('/api/')) return next();
  if (!N8N_PATHS.some(p => req.path.startsWith(p))) return next();
  
  const token = req.cookies[PROXY_COOKIE_NAME];
  if (token) {
    const session = sessionStore.get(token);
    if (session?.n8nCookie) {
      req.sessionToken = token;
      req.headers['cookie'] = session.n8nCookie;
    }
  }
  
  return proxyMiddleware(req, res, next);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Proxy server running on port ${PORT}`));
