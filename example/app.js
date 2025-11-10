// n8n User Management Web Application
// Main application logic

class UserManagementApp {
    constructor() {
        this.apiBaseUrl = API_CONFIG.baseUrl;
        this.apiKey = API_CONFIG.apiKey;
        this.users = [];
        this.currentUser = null;
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.checkServerConnection();
        this.loadUsers();
        this.loadAnalytics();
        
        // Auto-refresh every 30 seconds
        setInterval(() => {
            this.loadUsers();
            this.loadAnalytics();
        }, 30000);
    }

    setupEventListeners() {
        // Create user form
        document.getElementById('createUserForm').addEventListener('submit', (e) => {
            e.preventDefault();
            this.createUser();
        });

        // Refresh users button
        document.getElementById('refreshUsers').addEventListener('click', () => {
            this.loadUsers();
            this.showToast('Refreshing user list...', 'info');
        });

        // Search users
        document.getElementById('searchUsers').addEventListener('input', (e) => {
            this.filterUsers(e.target.value);
        });

        // Modal close
        document.querySelector('.close').addEventListener('click', () => {
            this.closeModal();
        });

        // Modal actions
        document.getElementById('resetPasswordBtn').addEventListener('click', () => {
            this.resetUserPassword();
        });

        document.getElementById('deleteUserBtn').addEventListener('click', () => {
            this.deleteUser();
        });

        // Close modal on outside click
        window.addEventListener('click', (e) => {
            const modal = document.getElementById('userModal');
            if (e.target === modal) {
                this.closeModal();
            }
        });
    }

    async checkServerConnection() {
        const statusIndicator = document.getElementById('serverStatus');
        const statusText = document.getElementById('serverStatusText');

        try {
            const response = await fetch(`${this.apiBaseUrl}/health`, {
                headers: this.getHeaders()
            });

            if (response.ok) {
                statusIndicator.classList.add('connected');
                statusIndicator.classList.remove('disconnected');
                statusText.textContent = 'Connected';
            } else {
                throw new Error('Server not responding');
            }
        } catch (error) {
            statusIndicator.classList.add('disconnected');
            statusIndicator.classList.remove('connected');
            statusText.textContent = 'Disconnected';
            console.error('Server connection error:', error);
        }
    }

    getHeaders() {
        return {
            'Content-Type': 'application/json',
            'X-API-Key': this.apiKey
        };
    }

    async createUser() {
        const formData = {
            userId: document.getElementById('userId').value,
            email: document.getElementById('userEmail').value,
            name: document.getElementById('userName').value,
            password: document.getElementById('userPassword').value,
            storageQuota: parseInt(document.getElementById('storageQuota').value)
        };

        try {
            const response = await fetch(`${this.apiBaseUrl}/users`, {
                method: 'POST',
                headers: this.getHeaders(),
                body: JSON.stringify(formData)
            });

            if (response.ok) {
                const result = await response.json();
                this.showToast(`User ${formData.userId} created successfully!`, 'success');
                document.getElementById('createUserForm').reset();
                this.loadUsers();
                this.loadAnalytics();
            } else {
                const error = await response.json();
                throw new Error(error.message || 'Failed to create user');
            }
        } catch (error) {
            this.showToast(`Error: ${error.message}`, 'error');
            console.error('Create user error:', error);
        }
    }

    async loadUsers() {
        try {
            const response = await fetch(`${this.apiBaseUrl}/users`, {
                headers: this.getHeaders()
            });

            if (response.ok) {
                this.users = await response.json();
                this.renderUsers(this.users);
            } else {
                throw new Error('Failed to load users');
            }
        } catch (error) {
            document.getElementById('usersList').innerHTML = `
                <div class="loading" style="color: var(--danger-color);">
                    Failed to load users. Please check your connection.
                </div>
            `;
            console.error('Load users error:', error);
        }
    }

    renderUsers(users) {
        const usersList = document.getElementById('usersList');

        if (users.length === 0) {
            usersList.innerHTML = '<div class="loading">No users found</div>';
            return;
        }

        usersList.innerHTML = users.map(user => `
            <div class="user-item" onclick="app.showUserDetails('${user.userId}')">
                <div class="user-info">
                    <h3>${user.name}</h3>
                    <p>${user.email} • ID: ${user.userId}</p>
                </div>
                <div class="user-stats">
                    <div class="user-stat">
                        <div class="user-stat-value">${user.workflowCount || 0}</div>
                        <div class="user-stat-label">Workflows</div>
                    </div>
                    <div class="user-stat">
                        <div class="user-stat-value">${this.formatStorage(user.storageUsed || 0)}</div>
                        <div class="user-stat-label">Storage</div>
                    </div>
                    <div class="user-stat">
                        <div class="user-stat-value">${user.executionCount || 0}</div>
                        <div class="user-stat-label">Executions</div>
                    </div>
                </div>
                <div class="user-actions" onclick="event.stopPropagation()">
                    <button class="btn btn-secondary" onclick="app.showUserDetails('${user.userId}')">
                        Details
                    </button>
                </div>
            </div>
        `).join('');
    }

    filterUsers(searchTerm) {
        const filtered = this.users.filter(user => 
            user.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
            user.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
            user.userId.toLowerCase().includes(searchTerm.toLowerCase())
        );
        this.renderUsers(filtered);
    }

    async showUserDetails(userId) {
        try {
            const response = await fetch(`${this.apiBaseUrl}/users/${userId}`, {
                headers: this.getHeaders()
            });

            if (response.ok) {
                this.currentUser = await response.json();
                this.renderUserDetails();
                document.getElementById('userModal').classList.add('show');
            } else {
                throw new Error('Failed to load user details');
            }
        } catch (error) {
            this.showToast(`Error: ${error.message}`, 'error');
            console.error('Load user details error:', error);
        }
    }

    renderUserDetails() {
        const user = this.currentUser;
        const detailsContainer = document.getElementById('userDetails');

        detailsContainer.innerHTML = `
            <div class="detail-row">
                <span class="detail-label">User ID:</span>
                <span class="detail-value">${user.userId}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Name:</span>
                <span class="detail-value">${user.name}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Email:</span>
                <span class="detail-value">${user.email}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Created:</span>
                <span class="detail-value">${this.formatDate(user.createdAt)}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Last Active:</span>
                <span class="detail-value">${this.formatDate(user.lastActive)}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Storage Used:</span>
                <span class="detail-value">${this.formatStorage(user.storageUsed)} / ${user.storageQuota} GB</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Workflows:</span>
                <span class="detail-value">${user.workflowCount || 0}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Total Executions:</span>
                <span class="detail-value">${user.executionCount || 0}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Execution Time:</span>
                <span class="detail-value">${this.formatTime(user.totalExecutionTime || 0)}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Status:</span>
                <span class="detail-value" style="color: ${user.status === 'active' ? 'var(--success-color)' : 'var(--danger-color)'}">
                    ${user.status || 'active'}
                </span>
            </div>
        `;
    }

    async resetUserPassword() {
        if (!this.currentUser) return;

        const newPassword = prompt('Enter new password for user:');
        if (!newPassword) return;

        try {
            const response = await fetch(`${this.apiBaseUrl}/users/${this.currentUser.userId}/password`, {
                method: 'PUT',
                headers: this.getHeaders(),
                body: JSON.stringify({ password: newPassword })
            });

            if (response.ok) {
                this.showToast('Password reset successfully!', 'success');
                this.closeModal();
            } else {
                throw new Error('Failed to reset password');
            }
        } catch (error) {
            this.showToast(`Error: ${error.message}`, 'error');
            console.error('Reset password error:', error);
        }
    }

    async deleteUser() {
        if (!this.currentUser) return;

        const confirmed = confirm(`Are you sure you want to delete user ${this.currentUser.userId}? This action cannot be undone.`);
        if (!confirmed) return;

        try {
            const response = await fetch(`${this.apiBaseUrl}/users/${this.currentUser.userId}`, {
                method: 'DELETE',
                headers: this.getHeaders()
            });

            if (response.ok) {
                this.showToast(`User ${this.currentUser.userId} deleted successfully!`, 'success');
                this.closeModal();
                this.loadUsers();
                this.loadAnalytics();
            } else {
                throw new Error('Failed to delete user');
            }
        } catch (error) {
            this.showToast(`Error: ${error.message}`, 'error');
            console.error('Delete user error:', error);
        }
    }

    closeModal() {
        document.getElementById('userModal').classList.remove('show');
        this.currentUser = null;
    }

    async loadAnalytics() {
        try {
            const response = await fetch(`${this.apiBaseUrl}/analytics`, {
                headers: this.getHeaders()
            });

            if (response.ok) {
                const analytics = await response.json();
                this.renderAnalytics(analytics);
            }
        } catch (error) {
            console.error('Load analytics error:', error);
        }
    }

    renderAnalytics(analytics) {
        document.getElementById('totalUsers').textContent = analytics.totalUsers || 0;
        document.getElementById('activeUsers').textContent = analytics.activeUsers || 0;
        document.getElementById('totalStorage').textContent = this.formatStorage(analytics.totalStorage || 0);
        document.getElementById('totalWorkflows').textContent = analytics.totalWorkflows || 0;
    }

    showToast(message, type = 'info') {
        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        
        const icon = type === 'success' ? '✓' : type === 'error' ? '✗' : 'ℹ';
        
        toast.innerHTML = `
            <span class="toast-icon">${icon}</span>
            <span class="toast-message">${message}</span>
        `;

        document.getElementById('toastContainer').appendChild(toast);

        setTimeout(() => {
            toast.style.animation = 'slideInRight 0.3s ease reverse';
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    }

    formatStorage(bytes) {
        if (bytes === 0) return '0 MB';
        const gb = bytes / (1024 * 1024 * 1024);
        if (gb >= 1) return `${gb.toFixed(2)} GB`;
        const mb = bytes / (1024 * 1024);
        return `${mb.toFixed(2)} MB`;
    }

    formatTime(seconds) {
        if (seconds < 60) return `${seconds}s`;
        const minutes = Math.floor(seconds / 60);
        const remainingSeconds = seconds % 60;
        if (minutes < 60) return `${minutes}m ${remainingSeconds}s`;
        const hours = Math.floor(minutes / 60);
        const remainingMinutes = minutes % 60;
        return `${hours}h ${remainingMinutes}m`;
    }

    formatDate(dateString) {
        if (!dateString) return 'N/A';
        const date = new Date(dateString);
        return date.toLocaleString();
    }
}

// Initialize app when DOM is ready
let app;
document.addEventListener('DOMContentLoaded', () => {
    app = new UserManagementApp();
});

