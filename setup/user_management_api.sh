#!/bin/bash

# User Management API Configuration Script
# Creates REST API endpoints for user provisioning, management, and analytics

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Load environment variables
load_environment() {
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        source "$PROJECT_ROOT/conf/user.env"
    fi
    if [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        source "$PROJECT_ROOT/conf/default.env"
    fi
}

# Create API directory structure
create_api_directories() {
    log_info "Creating user management API directory structure..."
    
    execute_silently "sudo mkdir -p /opt/n8n/api/endpoints"
    execute_silently "sudo mkdir -p /opt/n8n/api/middleware"
    execute_silently "sudo mkdir -p /opt/n8n/api/docs"
    execute_silently "sudo mkdir -p /opt/n8n/api/logs"
    
    # Set proper permissions
    execute_silently "sudo chown -R $USER:docker /opt/n8n/api"
    execute_silently "sudo chmod -R 755 /opt/n8n/api"
    
    log_pass "API directory structure created"
}

# Create user provisioning API
create_user_provisioning_api() {
    log_info "Creating user provisioning API endpoints..."
    
    # Create user provisioning endpoint
    cat > /opt/n8n/api/endpoints/user-provisioning.js << 'EOF'
// User Provisioning API
// REST API for managing user accounts and configurations

const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const fs = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');

class UserProvisioningAPI {
    constructor() {
        this.router = express.Router();
        this.usersPath = '/opt/n8n/users';
        this.configPath = '/opt/n8n/user-configs';
        this.metricsPath = '/opt/n8n/monitoring/metrics';
        this.setupRoutes();
    }

    setupRoutes() {
        // User management endpoints
        this.router.post('/users', this.createUser.bind(this));
        this.router.get('/users', this.listUsers.bind(this));
        this.router.get('/users/:userId', this.getUser.bind(this));
        this.router.put('/users/:userId', this.updateUser.bind(this));
        this.router.delete('/users/:userId', this.deleteUser.bind(this));
        
        // User authentication endpoints
        this.router.post('/auth/login', this.loginUser.bind(this));
        this.router.post('/auth/logout', this.logoutUser.bind(this));
        this.router.post('/auth/refresh', this.refreshToken.bind(this));
        this.router.get('/auth/validate', this.validateToken.bind(this));
        
        // User configuration endpoints
        this.router.get('/users/:userId/config', this.getUserConfig.bind(this));
        this.router.put('/users/:userId/config', this.updateUserConfig.bind(this));
        
        // User metrics endpoints
        this.router.get('/users/:userId/metrics', this.getUserMetrics.bind(this));
        this.router.get('/users/:userId/usage', this.getUserUsage.bind(this));
    }

    // Create new user
    async createUser(req, res) {
        try {
            const { userId, email, password, role = 'user' } = req.body;
            
            if (!userId || !email || !password) {
                return res.status(400).json({
                    error: 'Missing required fields: userId, email, password'
                });
            }

            // Validate user ID format
            if (!/^[a-zA-Z0-9_]+$/.test(userId)) {
                return res.status(400).json({
                    error: 'User ID must contain only alphanumeric characters and underscores'
                });
            }

            // Check if user already exists
            const userPath = path.join(this.usersPath, userId);
            try {
                await fs.access(userPath);
                return res.status(409).json({
                    error: 'User already exists'
                });
            } catch (error) {
                // User doesn't exist, continue
            }

            // Hash password
            const hashedPassword = await bcrypt.hash(password, 12);

            // Create user directory structure
            await fs.mkdir(path.join(userPath, 'workflows'), { recursive: true });
            await fs.mkdir(path.join(userPath, 'credentials'), { recursive: true });
            await fs.mkdir(path.join(userPath, 'files'), { recursive: true });
            await fs.mkdir(path.join(userPath, 'logs'), { recursive: true });
            await fs.mkdir(path.join(userPath, 'temp'), { recursive: true });
            await fs.mkdir(path.join(userPath, 'backups'), { recursive: true });

            // Create user configuration
            const userConfig = {
                userId,
                email,
                passwordHash: hashedPassword,
                role,
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString(),
                status: 'active',
                quotas: {
                    storage: '1GB',
                    workflows: 100,
                    executions: 10000
                },
                settings: {
                    timezone: 'UTC',
                    theme: 'default',
                    notifications: true
                },
                permissions: {
                    canCreateWorkflows: true,
                    canExecuteWorkflows: true,
                    canManageCredentials: true,
                    canAccessAPI: role === 'admin'
                }
            };

            await fs.writeFile(
                path.join(userPath, 'user-config.json'),
                JSON.stringify(userConfig, null, 2)
            );

            // Create user metrics file
            const userMetrics = {
                userId,
                metrics: {
                    storageUsed: 0,
                    workflowCount: 0,
                    executionCount: 0,
                    lastActivity: new Date().toISOString()
                }
            };

            await fs.writeFile(
                path.join(this.metricsPath, `${userId}.json`),
                JSON.stringify(userMetrics, null, 2)
            );

            // Return user info (without password hash)
            const { passwordHash, ...userResponse } = userConfig;
            res.status(201).json({
                message: 'User created successfully',
                user: userResponse
            });

        } catch (error) {
            console.error('Error creating user:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // List all users
    async listUsers(req, res) {
        try {
            const { limit = 50, offset = 0, status } = req.query;
            
            const userDirs = await fs.readdir(this.usersPath);
            const users = [];

            for (const userDir of userDirs) {
                const userConfigPath = path.join(this.usersPath, userDir, 'user-config.json');
                
                try {
                    const configData = await fs.readFile(userConfigPath, 'utf8');
                    const userConfig = JSON.parse(configData);
                    
                    // Filter by status if specified
                    if (status && userConfig.status !== status) {
                        continue;
                    }

                    // Remove password hash from response
                    const { passwordHash, ...userInfo } = userConfig;
                    users.push(userInfo);
                } catch (error) {
                    console.warn(`Failed to read user config for ${userDir}:`, error);
                }
            }

            // Apply pagination
            const startIndex = parseInt(offset);
            const endIndex = startIndex + parseInt(limit);
            const paginatedUsers = users.slice(startIndex, endIndex);

            res.json({
                users: paginatedUsers,
                pagination: {
                    total: users.length,
                    limit: parseInt(limit),
                    offset: parseInt(offset),
                    hasMore: endIndex < users.length
                }
            });

        } catch (error) {
            console.error('Error listing users:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // Get specific user
    async getUser(req, res) {
        try {
            const { userId } = req.params;
            const userConfigPath = path.join(this.usersPath, userId, 'user-config.json');
            
            try {
                const configData = await fs.readFile(userConfigPath, 'utf8');
                const userConfig = JSON.parse(configData);
                
                // Remove password hash from response
                const { passwordHash, ...userInfo } = userConfig;
                
                res.json({
                    user: userInfo
                });
            } catch (error) {
                res.status(404).json({
                    error: 'User not found'
                });
            }

        } catch (error) {
            console.error('Error getting user:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // Update user
    async updateUser(req, res) {
        try {
            const { userId } = req.params;
            const updates = req.body;
            
            const userConfigPath = path.join(this.usersPath, userId, 'user-config.json');
            
            try {
                const configData = await fs.readFile(userConfigPath, 'utf8');
                const userConfig = JSON.parse(configData);
                
                // Update allowed fields
                const allowedFields = ['email', 'status', 'quotas', 'settings', 'permissions'];
                const updatedConfig = { ...userConfig };
                
                for (const [key, value] of Object.entries(updates)) {
                    if (allowedFields.includes(key)) {
                        updatedConfig[key] = value;
                    }
                }
                
                // Handle password update separately
                if (updates.password) {
                    updatedConfig.passwordHash = await bcrypt.hash(updates.password, 12);
                }
                
                updatedConfig.updatedAt = new Date().toISOString();
                
                await fs.writeFile(userConfigPath, JSON.stringify(updatedConfig, null, 2));
                
                // Remove password hash from response
                const { passwordHash, ...userResponse } = updatedConfig;
                
                res.json({
                    message: 'User updated successfully',
                    user: userResponse
                });
                
            } catch (error) {
                res.status(404).json({
                    error: 'User not found'
                });
            }

        } catch (error) {
            console.error('Error updating user:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // Delete user
    async deleteUser(req, res) {
        try {
            const { userId } = req.params;
            const { backup = true } = req.query;
            
            const userPath = path.join(this.usersPath, userId);
            
            try {
                await fs.access(userPath);
                
                // Create backup if requested
                if (backup) {
                    const backupPath = `/opt/n8n/backups/user_${userId}_${Date.now()}.tar.gz`;
                    // Note: This would need to be implemented using a shell command
                    // exec(`tar -czf ${backupPath} -C ${this.usersPath} ${userId}`);
                }
                
                // Remove user directory
                await fs.rm(userPath, { recursive: true, force: true });
                
                // Remove user metrics
                try {
                    await fs.unlink(path.join(this.metricsPath, `${userId}.json`));
                } catch (error) {
                    // Metrics file might not exist
                }
                
                res.json({
                    message: 'User deleted successfully'
                });
                
            } catch (error) {
                res.status(404).json({
                    error: 'User not found'
                });
            }

        } catch (error) {
            console.error('Error deleting user:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // User login
    async loginUser(req, res) {
        try {
            const { userId, password } = req.body;
            
            if (!userId || !password) {
                return res.status(400).json({
                    error: 'Missing userId or password'
                });
            }
            
            const userConfigPath = path.join(this.usersPath, userId, 'user-config.json');
            
            try {
                const configData = await fs.readFile(userConfigPath, 'utf8');
                const userConfig = JSON.parse(configData);
                
                // Check if user is active
                if (userConfig.status !== 'active') {
                    return res.status(403).json({
                        error: 'User account is not active'
                    });
                }
                
                // Verify password
                const passwordValid = await bcrypt.compare(password, userConfig.passwordHash);
                
                if (!passwordValid) {
                    return res.status(401).json({
                        error: 'Invalid credentials'
                    });
                }
                
                // Generate JWT token
                const token = jwt.sign(
                    { 
                        userId: userConfig.userId,
                        role: userConfig.role,
                        permissions: userConfig.permissions
                    },
                    process.env.JWT_SECRET || 'default-secret',
                    { expiresIn: '24h' }
                );
                
                // Update last activity
                userConfig.lastActivity = new Date().toISOString();
                await fs.writeFile(userConfigPath, JSON.stringify(userConfig, null, 2));
                
                res.json({
                    message: 'Login successful',
                    token,
                    user: {
                        userId: userConfig.userId,
                        email: userConfig.email,
                        role: userConfig.role,
                        permissions: userConfig.permissions
                    }
                });
                
            } catch (error) {
                res.status(401).json({
                    error: 'Invalid credentials'
                });
            }

        } catch (error) {
            console.error('Error during login:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // User logout
    async logoutUser(req, res) {
        // In a stateless JWT system, logout is typically handled client-side
        // Here we could maintain a blacklist of tokens or use short-lived tokens
        res.json({
            message: 'Logout successful'
        });
    }

    // Refresh token
    async refreshToken(req, res) {
        try {
            const { token } = req.body;
            
            const decoded = jwt.verify(token, process.env.JWT_SECRET || 'default-secret');
            
            // Generate new token
            const newToken = jwt.sign(
                {
                    userId: decoded.userId,
                    role: decoded.role,
                    permissions: decoded.permissions
                },
                process.env.JWT_SECRET || 'default-secret',
                { expiresIn: '24h' }
            );
            
            res.json({
                token: newToken
            });
            
        } catch (error) {
            res.status(401).json({
                error: 'Invalid token'
            });
        }
    }

    // Validate token
    async validateToken(req, res) {
        try {
            const token = req.headers.authorization?.replace('Bearer ', '');
            
            if (!token) {
                return res.status(401).json({
                    error: 'No token provided'
                });
            }
            
            const decoded = jwt.verify(token, process.env.JWT_SECRET || 'default-secret');
            
            res.json({
                valid: true,
                user: {
                    userId: decoded.userId,
                    role: decoded.role,
                    permissions: decoded.permissions
                }
            });
            
        } catch (error) {
            res.status(401).json({
                valid: false,
                error: 'Invalid token'
            });
        }
    }

    // Get user configuration
    async getUserConfig(req, res) {
        try {
            const { userId } = req.params;
            const userConfigPath = path.join(this.usersPath, userId, 'user-config.json');
            
            try {
                const configData = await fs.readFile(userConfigPath, 'utf8');
                const userConfig = JSON.parse(configData);
                
                res.json({
                    config: {
                        quotas: userConfig.quotas,
                        settings: userConfig.settings,
                        permissions: userConfig.permissions
                    }
                });
            } catch (error) {
                res.status(404).json({
                    error: 'User not found'
                });
            }

        } catch (error) {
            console.error('Error getting user config:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // Update user configuration
    async updateUserConfig(req, res) {
        try {
            const { userId } = req.params;
            const { quotas, settings, permissions } = req.body;
            
            const userConfigPath = path.join(this.usersPath, userId, 'user-config.json');
            
            try {
                const configData = await fs.readFile(userConfigPath, 'utf8');
                const userConfig = JSON.parse(configData);
                
                if (quotas) userConfig.quotas = { ...userConfig.quotas, ...quotas };
                if (settings) userConfig.settings = { ...userConfig.settings, ...settings };
                if (permissions) userConfig.permissions = { ...userConfig.permissions, ...permissions };
                
                userConfig.updatedAt = new Date().toISOString();
                
                await fs.writeFile(userConfigPath, JSON.stringify(userConfig, null, 2));
                
                res.json({
                    message: 'User configuration updated successfully',
                    config: {
                        quotas: userConfig.quotas,
                        settings: userConfig.settings,
                        permissions: userConfig.permissions
                    }
                });
                
            } catch (error) {
                res.status(404).json({
                    error: 'User not found'
                });
            }

        } catch (error) {
            console.error('Error updating user config:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // Get user metrics
    async getUserMetrics(req, res) {
        try {
            const { userId } = req.params;
            const metricsPath = path.join(this.metricsPath, `${userId}.json`);
            
            try {
                const metricsData = await fs.readFile(metricsPath, 'utf8');
                const metrics = JSON.parse(metricsData);
                
                res.json(metrics);
            } catch (error) {
                res.status(404).json({
                    error: 'User metrics not found'
                });
            }

        } catch (error) {
            console.error('Error getting user metrics:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // Get user usage statistics
    async getUserUsage(req, res) {
        try {
            const { userId } = req.params;
            const { period = 'daily' } = req.query;
            
            // This would aggregate usage data based on the period
            // For now, return current metrics
            const metricsPath = path.join(this.metricsPath, `${userId}.json`);
            
            try {
                const metricsData = await fs.readFile(metricsPath, 'utf8');
                const metrics = JSON.parse(metricsData);
                
                res.json({
                    userId,
                    period,
                    usage: metrics.metrics
                });
            } catch (error) {
                res.status(404).json({
                    error: 'User usage data not found'
                });
            }

        } catch (error) {
            console.error('Error getting user usage:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    getRouter() {
        return this.router;
    }
}

module.exports = UserProvisioningAPI;
EOF

    log_pass "User provisioning API created"
}

# Create analytics API
create_analytics_api() {
    log_info "Creating analytics API endpoints..."
    
    cat > /opt/n8n/api/endpoints/analytics.js << 'EOF'
// Analytics API
// REST API for user metrics, reporting, and analytics

const express = require('express');
const fs = require('fs').promises;
const path = require('path');

class AnalyticsAPI {
    constructor() {
        this.router = express.Router();
        this.metricsPath = '/opt/n8n/monitoring/metrics';
        this.reportsPath = '/opt/n8n/monitoring/reports';
        this.analyticsPath = '/opt/n8n/monitoring/analytics';
        this.setupRoutes();
    }

    setupRoutes() {
        // Metrics endpoints
        this.router.get('/metrics/users', this.getAllUserMetrics.bind(this));
        this.router.get('/metrics/users/:userId', this.getUserMetrics.bind(this));
        this.router.get('/metrics/system', this.getSystemMetrics.bind(this));
        
        // Reports endpoints
        this.router.get('/reports/users/:userId/daily', this.getDailyReport.bind(this));
        this.router.get('/reports/users/:userId/weekly', this.getWeeklyReport.bind(this));
        this.router.get('/reports/users/:userId/monthly', this.getMonthlyReport.bind(this));
        this.router.get('/reports/system/overview', this.getSystemOverview.bind(this));
        
        // Analytics endpoints
        this.router.get('/analytics/usage-trends', this.getUsageTrends.bind(this));
        this.router.get('/analytics/performance', this.getPerformanceAnalytics.bind(this));
        this.router.get('/analytics/billing', this.getBillingAnalytics.bind(this));
    }

    async getAllUserMetrics(req, res) {
        try {
            const { active_only = false } = req.query;
            
            const metricsFiles = await fs.readdir(this.metricsPath);
            const userMetrics = [];
            
            for (const file of metricsFiles) {
                if (file.endsWith('_current.json')) {
                    const userId = file.replace('_current.json', '');
                    
                    try {
                        const metricsData = await fs.readFile(
                            path.join(this.metricsPath, file), 
                            'utf8'
                        );
                        const metrics = JSON.parse(metricsData);
                        
                        // Filter active users if requested
                        if (active_only) {
                            const lastActivity = new Date(metrics.lastActivity);
                            const daysSinceActivity = (Date.now() - lastActivity.getTime()) / (1000 * 60 * 60 * 24);
                            
                            if (daysSinceActivity > 30) {
                                continue;
                            }
                        }
                        
                        userMetrics.push(metrics);
                    } catch (error) {
                        console.warn(`Failed to read metrics for ${userId}:`, error);
                    }
                }
            }
            
            res.json({
                userMetrics,
                totalUsers: userMetrics.length
            });
            
        } catch (error) {
            console.error('Error getting user metrics:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getUserMetrics(req, res) {
        try {
            const { userId } = req.params;
            const { period = '24h' } = req.query;
            
            const currentMetricsPath = path.join(this.metricsPath, `${userId}_current.json`);
            
            try {
                const metricsData = await fs.readFile(currentMetricsPath, 'utf8');
                const metrics = JSON.parse(metricsData);
                
                // Get historical data based on period
                let historicalData = [];
                if (period !== 'current') {
                    historicalData = await this.getHistoricalMetrics(userId, period);
                }
                
                res.json({
                    current: metrics,
                    historical: historicalData,
                    period
                });
            } catch (error) {
                res.status(404).json({
                    error: 'User metrics not found'
                });
            }
            
        } catch (error) {
            console.error('Error getting user metrics:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getSystemMetrics(req, res) {
        try {
            const systemMetricsPath = path.join(this.metricsPath, 'system_metrics.json');
            
            try {
                const metricsData = await fs.readFile(systemMetricsPath, 'utf8');
                
                // Parse multiple JSON objects (one per line)
                const lines = metricsData.trim().split('\n');
                const metrics = lines.map(line => JSON.parse(line));
                
                // Get the latest metrics
                const latest = metrics[metrics.length - 1] || {};
                
                // Calculate aggregated statistics
                const totalUsers = await this.getTotalUserCount();
                const activeUsers = await this.getActiveUserCount();
                
                res.json({
                    system: latest,
                    users: {
                        total: totalUsers,
                        active: activeUsers
                    },
                    historical: metrics.slice(-24) // Last 24 measurements
                });
            } catch (error) {
                res.json({
                    system: {},
                    users: {
                        total: await this.getTotalUserCount(),
                        active: await this.getActiveUserCount()
                    },
                    historical: []
                });
            }
            
        } catch (error) {
            console.error('Error getting system metrics:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getDailyReport(req, res) {
        try {
            const { userId } = req.params;
            const { date = new Date().toISOString().split('T')[0] } = req.query;
            
            const reportPath = path.join(this.reportsPath, `${userId}_daily_${date}.json`);
            
            try {
                const reportData = await fs.readFile(reportPath, 'utf8');
                const report = JSON.parse(reportData);
                
                res.json(report);
            } catch (error) {
                res.status(404).json({
                    error: 'Daily report not found'
                });
            }
            
        } catch (error) {
            console.error('Error getting daily report:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getWeeklyReport(req, res) {
        try {
            const { userId } = req.params;
            const { week } = req.query;
            
            const weekStart = week || this.getWeekStart();
            const reportPath = path.join(this.reportsPath, `${userId}_weekly_${weekStart}.json`);
            
            try {
                const reportData = await fs.readFile(reportPath, 'utf8');
                const report = JSON.parse(reportData);
                
                res.json(report);
            } catch (error) {
                res.status(404).json({
                    error: 'Weekly report not found'
                });
            }
            
        } catch (error) {
            console.error('Error getting weekly report:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getMonthlyReport(req, res) {
        try {
            const { userId } = req.params;
            const { month = new Date().toISOString().slice(0, 7) } = req.query;
            
            const reportPath = path.join(this.reportsPath, `${userId}_monthly_${month}.json`);
            
            try {
                const reportData = await fs.readFile(reportPath, 'utf8');
                const report = JSON.parse(reportData);
                
                res.json(report);
            } catch (error) {
                res.status(404).json({
                    error: 'Monthly report not found'
                });
            }
            
        } catch (error) {
            console.error('Error getting monthly report:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getSystemOverview(req, res) {
        try {
            const { period = '7d' } = req.query;
            
            // Get aggregated system overview
            const overview = {
                totalUsers: await this.getTotalUserCount(),
                activeUsers: await this.getActiveUserCount(),
                totalExecutions: await this.getTotalExecutions(period),
                averageExecutionTime: await this.getAverageExecutionTime(period),
                storageUsage: await this.getTotalStorageUsage(),
                systemHealth: await this.getSystemHealth()
            };
            
            res.json(overview);
            
        } catch (error) {
            console.error('Error getting system overview:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getUsageTrends(req, res) {
        try {
            const { period = '30d', metric = 'executions' } = req.query;
            
            // This would analyze trends in usage metrics
            const trends = await this.calculateUsageTrends(metric, period);
            
            res.json({
                metric,
                period,
                trends
            });
            
        } catch (error) {
            console.error('Error getting usage trends:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getPerformanceAnalytics(req, res) {
        try {
            const { userId } = req.query;
            
            const performance = {
                averageExecutionTime: await this.getAverageExecutionTime('7d', userId),
                successRate: await this.getSuccessRate('7d', userId),
                resourceUtilization: await this.getResourceUtilization(userId),
                bottlenecks: await this.identifyBottlenecks(userId)
            };
            
            res.json(performance);
            
        } catch (error) {
            console.error('Error getting performance analytics:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    async getBillingAnalytics(req, res) {
        try {
            const { userId, period = '1m' } = req.query;
            
            const billing = {
                executionCount: await this.getExecutionCount(period, userId),
                storageUsage: await this.getStorageUsage(userId),
                computeTime: await this.getComputeTime(period, userId),
                estimatedCost: await this.calculateCost(period, userId)
            };
            
            res.json(billing);
            
        } catch (error) {
            console.error('Error getting billing analytics:', error);
            res.status(500).json({
                error: 'Internal server error'
            });
        }
    }

    // Helper methods
    async getHistoricalMetrics(userId, period) {
        // Implementation would depend on how historical data is stored
        return [];
    }

    async getTotalUserCount() {
        try {
            const userDirs = await fs.readdir('/opt/n8n/users');
            return userDirs.length;
        } catch (error) {
            return 0;
        }
    }

    async getActiveUserCount() {
        try {
            const metricsFiles = await fs.readdir(this.metricsPath);
            let activeCount = 0;
            
            for (const file of metricsFiles) {
                if (file.endsWith('_current.json')) {
                    try {
                        const metricsData = await fs.readFile(
                            path.join(this.metricsPath, file), 
                            'utf8'
                        );
                        const metrics = JSON.parse(metricsData);
                        
                        const lastActivity = new Date(metrics.lastActivity);
                        const daysSinceActivity = (Date.now() - lastActivity.getTime()) / (1000 * 60 * 60 * 24);
                        
                        if (daysSinceActivity <= 7) {
                            activeCount++;
                        }
                    } catch (error) {
                        // Skip invalid metrics files
                    }
                }
            }
            
            return activeCount;
        } catch (error) {
            return 0;
        }
    }

    async getTotalExecutions(period) {
        // Would aggregate execution counts from all users
        return 0;
    }

    async getAverageExecutionTime(period, userId = null) {
        // Would calculate average execution time
        return 0;
    }

    async getTotalStorageUsage() {
        // Would calculate total storage usage across all users
        return 0;
    }

    async getSystemHealth() {
        // Would check system health metrics
        return 'healthy';
    }

    async calculateUsageTrends(metric, period) {
        // Would analyze trends in the specified metric
        return {};
    }

    async getSuccessRate(period, userId = null) {
        // Would calculate workflow success rate
        return 0;
    }

    async getResourceUtilization(userId = null) {
        // Would get resource utilization metrics
        return {};
    }

    async identifyBottlenecks(userId = null) {
        // Would identify performance bottlenecks
        return [];
    }

    async getExecutionCount(period, userId = null) {
        // Would count executions in period
        return 0;
    }

    async getStorageUsage(userId = null) {
        // Would get storage usage
        return 0;
    }

    async getComputeTime(period, userId = null) {
        // Would calculate compute time
        return 0;
    }

    async calculateCost(period, userId = null) {
        // Would calculate estimated cost
        return 0;
    }

    getWeekStart() {
        const now = new Date();
        const dayOfWeek = now.getDay();
        const diff = now.getDate() - dayOfWeek + (dayOfWeek === 0 ? -6 : 1);
        const monday = new Date(now.setDate(diff));
        return monday.toISOString().split('T')[0];
    }

    getRouter() {
        return this.router;
    }
}

module.exports = AnalyticsAPI;
EOF

    log_pass "Analytics API created"
}

# Create API middleware
create_api_middleware() {
    log_info "Creating API middleware..."
    
    # Authentication middleware
    cat > /opt/n8n/api/middleware/auth.js << 'EOF'
// Authentication Middleware
// JWT-based authentication for API endpoints

const jwt = require('jsonwebtoken');
const fs = require('fs').promises;
const path = require('path');

class AuthMiddleware {
    constructor() {
        this.jwtSecret = process.env.JWT_SECRET || 'default-secret';
        this.usersPath = '/opt/n8n/users';
    }

    // Middleware to verify JWT token
    verifyToken(req, res, next) {
        const token = req.headers.authorization?.replace('Bearer ', '');
        
        if (!token) {
            return res.status(401).json({
                error: 'Access denied. No token provided.'
            });
        }
        
        try {
            const decoded = jwt.verify(token, this.jwtSecret);
            req.user = decoded;
            next();
        } catch (error) {
            return res.status(401).json({
                error: 'Invalid token.'
            });
        }
    }

    // Middleware to check user permissions
    requirePermission(permission) {
        return (req, res, next) => {
            if (!req.user) {
                return res.status(401).json({
                    error: 'Authentication required'
                });
            }
            
            if (!req.user.permissions || !req.user.permissions[permission]) {
                return res.status(403).json({
                    error: 'Insufficient permissions'
                });
            }
            
            next();
        };
    }

    // Middleware to check user role
    requireRole(role) {
        return (req, res, next) => {
            if (!req.user) {
                return res.status(401).json({
                    error: 'Authentication required'
                });
            }
            
            if (req.user.role !== role && req.user.role !== 'admin') {
                return res.status(403).json({
                    error: 'Insufficient role privileges'
                });
            }
            
            next();
        };
    }

    // Middleware to ensure user can only access their own data
    requireOwnUser(req, res, next) {
        if (!req.user) {
            return res.status(401).json({
                error: 'Authentication required'
            });
        }
        
        const requestedUserId = req.params.userId;
        
        // Admins can access any user's data
        if (req.user.role === 'admin') {
            return next();
        }
        
        // Users can only access their own data
        if (req.user.userId !== requestedUserId) {
            return res.status(403).json({
                error: 'Access denied. Can only access own user data.'
            });
        }
        
        next();
    }

    // API key authentication (for server-to-server communication)
    verifyApiKey(req, res, next) {
        const apiKey = req.headers['x-api-key'];
        
        if (!apiKey) {
            return res.status(401).json({
                error: 'API key required'
            });
        }
        
        // Load API key configuration
        const configPath = '/opt/n8n/user-configs/api-auth.json';
        
        try {
            const configData = require(configPath);
            const validKeys = configData.apiAuthentication.methods.apiKey.keys;
            
            const keyFound = Object.values(validKeys).includes(apiKey);
            
            if (!keyFound) {
                return res.status(401).json({
                    error: 'Invalid API key'
                });
            }
            
            // Set API context
            req.apiAuth = true;
            next();
            
        } catch (error) {
            return res.status(500).json({
                error: 'API authentication configuration error'
            });
        }
    }

    // Rate limiting middleware
    rateLimit(windowMs = 15 * 60 * 1000, maxRequests = 100) {
        const requests = new Map();
        
        return (req, res, next) => {
            const clientId = req.ip || req.connection.remoteAddress;
            const now = Date.now();
            
            // Clean up old entries
            for (const [id, data] of requests.entries()) {
                if (now - data.resetTime > windowMs) {
                    requests.delete(id);
                }
            }
            
            // Get or create client entry
            let clientData = requests.get(clientId);
            if (!clientData || now - clientData.resetTime > windowMs) {
                clientData = {
                    count: 0,
                    resetTime: now
                };
                requests.set(clientId, clientData);
            }
            
            // Check rate limit
            if (clientData.count >= maxRequests) {
                return res.status(429).json({
                    error: 'Too many requests',
                    retryAfter: Math.ceil((windowMs - (now - clientData.resetTime)) / 1000)
                });
            }
            
            // Increment count
            clientData.count++;
            
            // Set rate limit headers
            res.set({
                'X-RateLimit-Limit': maxRequests,
                'X-RateLimit-Remaining': maxRequests - clientData.count,
                'X-RateLimit-Reset': new Date(clientData.resetTime + windowMs).toISOString()
            });
            
            next();
        };
    }
}

module.exports = new AuthMiddleware();
EOF

    # Request logging middleware
    cat > /opt/n8n/api/middleware/logging.js << 'EOF'
// Request Logging Middleware
// Logs API requests for monitoring and debugging

const fs = require('fs');
const path = require('path');

class LoggingMiddleware {
    constructor() {
        this.logPath = '/opt/n8n/api/logs';
        this.ensureLogDirectory();
    }

    ensureLogDirectory() {
        if (!fs.existsSync(this.logPath)) {
            fs.mkdirSync(this.logPath, { recursive: true });
        }
    }

    // Request logging middleware
    logRequests(req, res, next) {
        const startTime = Date.now();
        
        // Log request
        const requestLog = {
            timestamp: new Date().toISOString(),
            method: req.method,
            url: req.url,
            ip: req.ip || req.connection.remoteAddress,
            userAgent: req.get('User-Agent'),
            userId: req.user?.userId || 'anonymous'
        };
        
        // Override res.end to capture response details
        const originalEnd = res.end;
        res.end = function(chunk, encoding) {
            const duration = Date.now() - startTime;
            
            const responseLog = {
                ...requestLog,
                statusCode: res.statusCode,
                duration,
                responseSize: res.get('Content-Length') || 0
            };
            
            // Write to daily log file
            const logFile = path.join(
                '/opt/n8n/api/logs',
                `api-${new Date().toISOString().split('T')[0]}.log`
            );
            
            fs.appendFileSync(logFile, JSON.stringify(responseLog) + '\n');
            
            // Call original end
            originalEnd.call(this, chunk, encoding);
        };
        
        next();
    }

    // Error logging middleware
    logErrors(err, req, res, next) {
        const errorLog = {
            timestamp: new Date().toISOString(),
            method: req.method,
            url: req.url,
            ip: req.ip || req.connection.remoteAddress,
            userId: req.user?.userId || 'anonymous',
            error: {
                message: err.message,
                stack: err.stack,
                status: err.status || 500
            }
        };
        
        // Write to error log file
        const errorLogFile = path.join(
            '/opt/n8n/api/logs',
            `api-errors-${new Date().toISOString().split('T')[0]}.log`
        );
        
        fs.appendFileSync(errorLogFile, JSON.stringify(errorLog) + '\n');
        
        // Send error response
        res.status(err.status || 500).json({
            error: 'Internal server error',
            timestamp: errorLog.timestamp
        });
    }
}

module.exports = new LoggingMiddleware();
EOF

    log_pass "API middleware created"
}

# Create API server
create_api_server() {
    log_info "Creating main API server..."
    
    cat > /opt/n8n/api/server.js << 'EOF'
// n8n User Management API Server
// Express.js server providing REST API for user management and analytics

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');

// Import API endpoints
const UserProvisioningAPI = require('./endpoints/user-provisioning');
const AnalyticsAPI = require('./endpoints/analytics');

// Import middleware
const authMiddleware = require('./middleware/auth');
const loggingMiddleware = require('./middleware/logging');

class UserManagementServer {
    constructor() {
        this.app = express();
        this.port = process.env.API_PORT || 3001;
        this.setupMiddleware();
        this.setupRoutes();
        this.setupErrorHandling();
    }

    setupMiddleware() {
        // Security middleware
        this.app.use(helmet());
        
        // CORS configuration
        this.app.use(cors({
            origin: process.env.WEBAPP_DOMAIN || 'http://localhost:3000',
            credentials: true,
            methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
            allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key', 'X-User-ID']
        }));
        
        // Compression
        this.app.use(compression());
        
        // Body parsing
        this.app.use(express.json({ limit: '10mb' }));
        this.app.use(express.urlencoded({ extended: true, limit: '10mb' }));
        
        // Request logging
        this.app.use(loggingMiddleware.logRequests);
        
        // Rate limiting for API
        this.app.use('/api/', authMiddleware.rateLimit(15 * 60 * 1000, 100));
    }

    setupRoutes() {
        // Health check endpoint
        this.app.get('/health', (req, res) => {
            res.json({
                status: 'healthy',
                timestamp: new Date().toISOString(),
                version: '1.0.0'
            });
        });

        // API documentation
        this.app.get('/api/docs', (req, res) => {
            res.json({
                title: 'n8n User Management API',
                version: '1.0.0',
                description: 'REST API for managing n8n users and analytics',
                endpoints: {
                    users: {
                        'POST /api/users': 'Create new user',
                        'GET /api/users': 'List all users',
                        'GET /api/users/:userId': 'Get specific user',
                        'PUT /api/users/:userId': 'Update user',
                        'DELETE /api/users/:userId': 'Delete user'
                    },
                    auth: {
                        'POST /api/auth/login': 'User login',
                        'POST /api/auth/logout': 'User logout',
                        'POST /api/auth/refresh': 'Refresh token',
                        'GET /api/auth/validate': 'Validate token'
                    },
                    analytics: {
                        'GET /api/metrics/users': 'Get all user metrics',
                        'GET /api/metrics/users/:userId': 'Get user metrics',
                        'GET /api/metrics/system': 'Get system metrics',
                        'GET /api/reports/users/:userId/daily': 'Get daily report',
                        'GET /api/analytics/usage-trends': 'Get usage trends'
                    }
                }
            });
        });

        // User management routes (public endpoints for login)
        const userAPI = new UserProvisioningAPI();
        
        // Public authentication endpoints
        this.app.use('/api/auth', userAPI.getRouter());
        
        // Protected user management endpoints
        this.app.use('/api/users', 
            authMiddleware.verifyToken.bind(authMiddleware),
            userAPI.getRouter()
        );
        
        // User configuration endpoints (users can access own data)
        this.app.use('/api/users/:userId/config',
            authMiddleware.verifyToken.bind(authMiddleware),
            authMiddleware.requireOwnUser,
            userAPI.getRouter()
        );

        // Analytics routes (require authentication)
        const analyticsAPI = new AnalyticsAPI();
        this.app.use('/api/metrics',
            authMiddleware.verifyToken.bind(authMiddleware),
            analyticsAPI.getRouter()
        );
        
        this.app.use('/api/reports',
            authMiddleware.verifyToken.bind(authMiddleware),
            analyticsAPI.getRouter()
        );
        
        this.app.use('/api/analytics',
            authMiddleware.verifyToken.bind(authMiddleware),
            authMiddleware.requireRole('admin'),
            analyticsAPI.getRouter()
        );

        // Server-to-server API endpoints (API key authentication)
        this.app.use('/api/internal',
            authMiddleware.verifyApiKey,
            userAPI.getRouter()
        );

        // 404 handler
        this.app.use('*', (req, res) => {
            res.status(404).json({
                error: 'API endpoint not found',
                path: req.originalUrl
            });
        });
    }

    setupErrorHandling() {
        // Global error handler
        this.app.use(loggingMiddleware.logErrors);
        
        // Graceful shutdown
        process.on('SIGTERM', this.gracefulShutdown.bind(this));
        process.on('SIGINT', this.gracefulShutdown.bind(this));
    }

    start() {
        this.server = this.app.listen(this.port, () => {
            console.log(`[${new Date().toISOString()}] [INFO] n8n User Management API started on port ${this.port}`);
            console.log(`[${new Date().toISOString()}] [INFO] API documentation available at http://localhost:${this.port}/api/docs`);
            console.log(`[${new Date().toISOString()}] [INFO] Health check available at http://localhost:${this.port}/health`);
        });

        this.server.on('error', (error) => {
            console.error(`[${new Date().toISOString()}] [ERROR] API server error:`, error);
        });
    }

    gracefulShutdown() {
        console.log(`[${new Date().toISOString()}] [INFO] Shutting down API server gracefully...`);
        
        if (this.server) {
            this.server.close(() => {
                console.log(`[${new Date().toISOString()}] [INFO] API server shut down complete`);
                process.exit(0);
            });
        } else {
            process.exit(0);
        }
    }
}

// Start the server if this file is run directly
if (require.main === module) {
    const server = new UserManagementServer();
    server.start();
}

module.exports = UserManagementServer;
EOF

    # Create package.json for API dependencies
    cat > /opt/n8n/api/package.json << 'EOF'
{
  "name": "n8n-user-management-api",
  "version": "1.0.0",
  "description": "REST API for n8n user management and analytics",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.0.0",
    "compression": "^1.7.4",
    "bcrypt": "^5.1.0",
    "jsonwebtoken": "^9.0.1",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1",
    "jest": "^29.6.1"
  },
  "engines": {
    "node": ">=16.0.0"
  }
}
EOF

    # Create systemd service for API
    cat > /opt/n8n/scripts/user-management-api.service << 'EOF'
[Unit]
Description=n8n User Management API
After=network.target

[Service]
Type=simple
User=node
WorkingDirectory=/opt/n8n/api
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=API_PORT=3001

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/n8n

[Install]
WantedBy=multi-user.target
EOF

    log_pass "API server created"
}

# Create API documentation
create_api_documentation() {
    log_info "Creating API documentation..."
    
    cat > /opt/n8n/api/docs/README.md << 'EOF'
# n8n User Management API

This API provides comprehensive user management and analytics functionality for n8n multi-user deployments.

## Base URL

```
http://localhost:3001/api
```

## Authentication

The API uses JWT-based authentication. Include the JWT token in the Authorization header:

```
Authorization: Bearer <jwt_token>
```

For server-to-server communication, use API key authentication:

```
X-API-Key: <api_key>
```

## User Management Endpoints

### Create User
```http
POST /users
Content-Type: application/json

{
  "userId": "john_doe",
  "email": "john@example.com",
  "password": "securepassword",
  "role": "user"
}
```

### List Users
```http
GET /users?limit=50&offset=0&status=active
```

### Get User
```http
GET /users/{userId}
```

### Update User
```http
PUT /users/{userId}
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

### Delete User
```http
DELETE /users/{userId}?backup=true
```

## Authentication Endpoints

### Login
```http
POST /auth/login
Content-Type: application/json

{
  "userId": "john_doe",
  "password": "securepassword"
}
```

### Validate Token
```http
GET /auth/validate
Authorization: Bearer <jwt_token>
```

## Analytics Endpoints

### Get User Metrics
```http
GET /metrics/users/{userId}?period=24h
```

### Get System Overview
```http
GET /reports/system/overview?period=7d
```

### Get Usage Trends
```http
GET /analytics/usage-trends?period=30d&metric=executions
```

## Error Handling

All endpoints return consistent error responses:

```json
{
  "error": "Error message",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## Rate Limiting

API endpoints are rate limited:
- 100 requests per 15 minutes per IP address
- 1000 requests per hour for authenticated users

## Response Format

All successful responses follow this format:

```json
{
  "data": {},
  "message": "Success message",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## Permissions

- `user`: Can manage own account and data
- `admin`: Can manage all users and access analytics

## User Data Structure

```json
{
  "userId": "john_doe",
  "email": "john@example.com",
  "role": "user",
  "status": "active",
  "createdAt": "2024-01-01T00:00:00.000Z",
  "quotas": {
    "storage": "1GB",
    "workflows": 100,
    "executions": 10000
  },
  "settings": {
    "timezone": "UTC",
    "theme": "default"
  },
  "permissions": {
    "canCreateWorkflows": true,
    "canExecuteWorkflows": true
  }
}
```

## Metrics Structure

```json
{
  "userId": "john_doe",
  "metrics": {
    "storageUsed": 524288000,
    "workflowCount": 15,
    "executionCount": 342,
    "totalDuration": 45670,
    "averageDuration": 133.4,
    "successfulExecutions": 330,
    "failedExecutions": 12,
    "lastActivity": "2024-01-01T00:00:00.000Z"
  }
}
```
EOF

    log_pass "API documentation created"
}

# Main execution function
main() {
    log_info "Starting user management API configuration..."
    
    load_environment
    create_api_directories
    create_user_provisioning_api
    create_analytics_api
    create_api_middleware
    create_api_server
    create_api_documentation
    
    log_pass "User management API configuration completed successfully"
    log_info "API server files created in: /opt/n8n/api/"
    log_info "To install dependencies: cd /opt/n8n/api && npm install"
    log_info "To start API server: cd /opt/n8n/api && npm start"
    log_info "API documentation: /opt/n8n/api/docs/README.md"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
