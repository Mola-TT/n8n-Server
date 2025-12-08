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
    
    // Get workflows with details
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
    const totalNodes = workflows.reduce((sum, w) => sum + (w.nodes?.length || 0), 0);
    
    // Get credentials count
    let credentialsCount = 0;
    try {
      const credRes = await axios.get(`${N8N_API}/rest/credentials`, { ...axiosConfig, headers });
      const credData = credRes.data;
      if (Array.isArray(credData)) {
        credentialsCount = credData.length;
      } else if (Array.isArray(credData.data)) {
        credentialsCount = credData.data.length;
      }
    } catch (e) {
      console.log('Could not fetch credentials:', e.message);
    }
    
    // Group executions by day for chart
    const executionsByDay = {};
    executions.forEach(e => {
      if (!e.startedAt) return;
      const date = new Date(e.startedAt).toISOString().split('T')[0];
      if (!executionsByDay[date]) {
        executionsByDay[date] = { total: 0, success: 0, failed: 0, duration: 0 };
      }
      executionsByDay[date].total++;
      if (e.status === 'success' || e.finished === true) executionsByDay[date].success++;
      if (e.status === 'error' || e.status === 'crashed' || e.status === 'failed') executionsByDay[date].failed++;
      if (e.startedAt && e.stoppedAt) {
        executionsByDay[date].duration += new Date(e.stoppedAt) - new Date(e.startedAt);
      }
    });
    
    // Group executions by hour for activity heatmap
    const executionsByHour = Array(24).fill(0);
    executions.forEach(e => {
      if (e.startedAt) {
        const hour = new Date(e.startedAt).getHours();
        executionsByHour[hour]++;
      }
    });
    
    // Calculate performance metrics
    const executionTimes = executions
      .filter(e => e.startedAt && e.stoppedAt)
      .map(e => new Date(e.stoppedAt) - new Date(e.startedAt));
    
    const avgExecutionTime = executionTimes.length > 0 
      ? executionTimes.reduce((a, b) => a + b, 0) / executionTimes.length 
      : 0;
    const minExecutionTime = executionTimes.length > 0 ? Math.min(...executionTimes) : 0;
    const maxExecutionTime = executionTimes.length > 0 ? Math.max(...executionTimes) : 0;
    
    // Recent executions
    const recentExecutions = executions.slice(0, 10).map(e => ({
      id: e.id,
      workflowName: e.workflowData?.name || e.workflowName || 'Unknown',
      status: e.status || (e.finished ? 'success' : 'unknown'),
      startedAt: e.startedAt,
      stoppedAt: e.stoppedAt,
      duration: e.startedAt && e.stoppedAt 
        ? new Date(e.stoppedAt) - new Date(e.startedAt) 
        : null,
      mode: e.mode || 'manual'
    }));
    
    // Top workflows by execution count
    const workflowExecutionCounts = {};
    executions.forEach(e => {
      const name = e.workflowData?.name || e.workflowName || 'Unknown';
      workflowExecutionCounts[name] = (workflowExecutionCounts[name] || 0) + 1;
    });
    const topWorkflows = Object.entries(workflowExecutionCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([name, count]) => ({ name, count }));
    
    // Get actual statistics from n8n API
    let settings = {};
    try {
      const settingsRes = await axios.get(`${N8N_API}/rest/settings`, { ...axiosConfig, headers });
      settings = settingsRes.data || {};
    } catch (e) {
      console.log('Could not fetch settings:', e.message);
    }

    // Calculate actual storage from workflow data sizes (approximate)
    let totalWorkflowSize = 0;
    workflows.forEach(w => {
      // Estimate workflow size based on nodes and connections
      const nodeCount = w.nodes?.length || 0;
      const connectionCount = Object.keys(w.connections || {}).length;
      totalWorkflowSize += (nodeCount * 500) + (connectionCount * 100) + 1000; // bytes estimate
    });

    // Real quotas based on actual API data
    const quotas = {
      storage: { 
        used: totalWorkflowSize, 
        limit: 1024 * 1024 * 1024, // 1GB default limit
        available: false // n8n API doesn't expose real storage
      },
      workflows: { used: workflows.length, limit: settings.enterprise?.workflowLimit || 100 },
      executions: { used: totalExecutions, limit: settings.enterprise?.executionLimit || 10000 },
      credentials: { used: credentialsCount, limit: settings.enterprise?.credentialLimit || 50 }
    };
    
    // Calculate storage breakdown from real data
    const storageBreakdown = {
      workflows: totalWorkflowSize,
      files: 0, // Would need file system access
      logs: 0,  // Would need file system access
      temp: 0   // Would need file system access
    };
    
    // Calculate billing estimates based on real execution data
    const billingRates = {
      perExecution: 0.001, // $0.001 per execution
      perGBStorage: 0.10,  // $0.10 per GB per month
      perComputeHour: 0.05 // $0.05 per compute hour
    };
    
    const computeHours = totalExecutionTime / (1000 * 60 * 60);
    const storageGB = totalWorkflowSize / (1024 * 1024 * 1024);
    
    const billing = {
      executions: { count: totalExecutions, cost: totalExecutions * billingRates.perExecution },
      storage: { gb: storageGB, cost: storageGB * billingRates.perGBStorage },
      compute: { hours: computeHours, cost: computeHours * billingRates.perComputeHour },
      total: (totalExecutions * billingRates.perExecution) + 
             (storageGB * billingRates.perGBStorage) + 
             (computeHours * billingRates.perComputeHour)
    };
    
    res.json({
      success: true,
      user: {
        id: user.id || 'unknown',
        email: user.email || session.email,
        firstName: user.firstName || '',
        lastName: user.lastName || '',
        role: user.role || 'member',
        createdAt: user.createdAt
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
          averageMs: Math.round(avgExecutionTime),
          averageFormatted: formatDuration(avgExecutionTime),
          minMs: minExecutionTime,
          maxMs: maxExecutionTime
        },
        workflows: {
          total: workflows.length,
          active: activeWorkflows,
          inactive: workflows.length - activeWorkflows,
          totalNodes
        },
        credentials: credentialsCount
      },
      quotas,
      storage: {
        used: totalWorkflowSize,
        limit: quotas.storage.limit,
        usedFormatted: formatBytes(totalWorkflowSize),
        limitFormatted: formatBytes(quotas.storage.limit),
        percentage: Math.round((totalWorkflowSize / quotas.storage.limit) * 100),
        isEstimate: true, // Storage is estimated from workflow data, not actual file system
        breakdown: {
          workflows: { bytes: storageBreakdown.workflows, formatted: formatBytes(storageBreakdown.workflows) },
          files: { bytes: storageBreakdown.files, formatted: formatBytes(storageBreakdown.files), notAvailable: true },
          logs: { bytes: storageBreakdown.logs, formatted: formatBytes(storageBreakdown.logs), notAvailable: true },
          temp: { bytes: storageBreakdown.temp, formatted: formatBytes(storageBreakdown.temp), notAvailable: true }
        }
      },
      performance: {
        avgExecutionTime: Math.round(avgExecutionTime),
        minExecutionTime,
        maxExecutionTime,
        successRate: totalExecutions > 0 ? Math.round((successfulExecutions / totalExecutions) * 100) : 0,
        failureRate: totalExecutions > 0 ? Math.round((failedExecutions / totalExecutions) * 100) : 0
      },
      billing,
      charts: {
        executionsByDay: Object.entries(executionsByDay)
          .sort((a, b) => a[0].localeCompare(b[0]))
          .slice(-14)
          .map(([date, data]) => ({ date, ...data })),
        executionsByHour,
        topWorkflows
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
  if (ms < 1000) return `${Math.round(ms)}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  if (ms < 3600000) return `${Math.floor(ms / 60000)}m ${Math.floor((ms % 60000) / 1000)}s`;
  return `${Math.floor(ms / 3600000)}h ${Math.floor((ms % 3600000) / 60000)}m`;
}

// Helper function to format bytes
function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
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
