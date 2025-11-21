#!/bin/bash

# User Monitoring Configuration Script
# Implements per-user execution time tracking, storage monitoring, and analytics

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/utilities.sh"

# Load environment variables
load_environment() {
    if [[ -f "$PROJECT_ROOT/conf/default.env" ]]; then
        source "$PROJECT_ROOT/conf/default.env"
    fi
    if [[ -f "$PROJECT_ROOT/conf/user.env" ]]; then
        source "$PROJECT_ROOT/conf/user.env"
    fi
}

# Create monitoring directory structure
create_monitoring_directories() {
    log_info "Creating monitoring directory structure..."
    
    # Monitoring directories
    execute_silently "sudo mkdir -p /opt/n8n/monitoring/metrics"
    execute_silently "sudo mkdir -p /opt/n8n/monitoring/reports"
    execute_silently "sudo mkdir -p /opt/n8n/monitoring/analytics"
    execute_silently "sudo mkdir -p /opt/n8n/monitoring/alerts"
    execute_silently "sudo mkdir -p /opt/n8n/monitoring/logs"
    
    # Set proper permissions
    execute_silently "sudo chown -R $USER:docker /opt/n8n/monitoring"
    execute_silently "sudo chmod -R 755 /opt/n8n/monitoring"
    
    log_pass "Monitoring directories created"
}

# Configure execution time tracking
configure_execution_tracking() {
    log_info "Configuring execution time tracking..."
    
    # Create execution tracker script
    cat > /opt/n8n/scripts/execution-tracker.js << 'EOF'
// Execution Time Tracker for n8n workflows

class ExecutionTracker {
    constructor() {
        this.executions = new Map();
        this.metricsPath = '/opt/n8n/monitoring/metrics';
        this.init();
    }

    init() {
        this.setupExecutionHooks();
        this.startMetricsCollection();
    }

    setupExecutionHooks() {
        // Hook into n8n execution events
        if (window.n8n && window.n8n.hooks) {
            window.n8n.hooks.on('workflow.preExecute', this.onPreExecute.bind(this));
            window.n8n.hooks.on('workflow.postExecute', this.onPostExecute.bind(this));
            window.n8n.hooks.on('workflow.failed', this.onExecutionFailed.bind(this));
        }
    }

    onPreExecute(data) {
        const executionId = data.executionId;
        const userId = this.getCurrentUserId();
        
        this.executions.set(executionId, {
            userId,
            workflowId: data.workflowId,
            startTime: Date.now(),
            status: 'running'
        });

        this.logExecution(executionId, 'started', {
            userId,
            workflowId: data.workflowId,
            timestamp: new Date().toISOString()
        });
    }

    onPostExecute(data) {
        const executionId = data.executionId;
        const execution = this.executions.get(executionId);
        
        if (execution) {
            const endTime = Date.now();
            const duration = endTime - execution.startTime;
            
            execution.endTime = endTime;
            execution.duration = duration;
            execution.status = 'completed';
            
            this.recordMetrics(execution);
            this.logExecution(executionId, 'completed', {
                duration,
                status: 'success'
            });
            
            this.executions.delete(executionId);
        }
    }

    onExecutionFailed(data) {
        const executionId = data.executionId;
        const execution = this.executions.get(executionId);
        
        if (execution) {
            const endTime = Date.now();
            const duration = endTime - execution.startTime;
            
            execution.endTime = endTime;
            execution.duration = duration;
            execution.status = 'failed';
            execution.error = data.error;
            
            this.recordMetrics(execution);
            this.logExecution(executionId, 'failed', {
                duration,
                status: 'error',
                error: data.error
            });
            
            this.executions.delete(executionId);
        }
    }

    recordMetrics(execution) {
        const userId = execution.userId;
        const timestamp = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
        
        // Update user metrics
        this.updateUserMetrics(userId, execution);
        
        // Store daily metrics
        this.storeDailyMetrics(userId, timestamp, execution);
    }

    updateUserMetrics(userId, execution) {
        const metricsFile = `${this.metricsPath}/${userId}_current.json`;
        
        // Read existing metrics or create new
        let metrics = {};
        try {
            const data = require('fs').readFileSync(metricsFile, 'utf8');
            metrics = JSON.parse(data);
        } catch (error) {
            metrics = {
                userId,
                totalExecutions: 0,
                totalDuration: 0,
                successfulExecutions: 0,
                failedExecutions: 0,
                averageDuration: 0,
                lastActivity: null
            };
        }

        // Update metrics
        metrics.totalExecutions++;
        metrics.totalDuration += execution.duration;
        metrics.lastActivity = new Date().toISOString();
        
        if (execution.status === 'completed') {
            metrics.successfulExecutions++;
        } else if (execution.status === 'failed') {
            metrics.failedExecutions++;
        }
        
        metrics.averageDuration = metrics.totalDuration / metrics.totalExecutions;
        
        // Write updated metrics
        require('fs').writeFileSync(metricsFile, JSON.stringify(metrics, null, 2));
    }

    storeDailyMetrics(userId, date, execution) {
        const dailyFile = `${this.metricsPath}/${userId}_${date}.json`;
        
        let dailyMetrics = {};
        try {
            const data = require('fs').readFileSync(dailyFile, 'utf8');
            dailyMetrics = JSON.parse(data);
        } catch (error) {
            dailyMetrics = {
                userId,
                date,
                executions: [],
                summary: {
                    count: 0,
                    totalDuration: 0,
                    successful: 0,
                    failed: 0
                }
            };
        }

        // Add execution to daily log
        dailyMetrics.executions.push({
            executionId: execution.executionId || 'unknown',
            workflowId: execution.workflowId,
            duration: execution.duration,
            status: execution.status,
            timestamp: new Date().toISOString()
        });

        // Update summary
        dailyMetrics.summary.count++;
        dailyMetrics.summary.totalDuration += execution.duration;
        if (execution.status === 'completed') {
            dailyMetrics.summary.successful++;
        } else if (execution.status === 'failed') {
            dailyMetrics.summary.failed++;
        }

        // Write daily metrics
        require('fs').writeFileSync(dailyFile, JSON.stringify(dailyMetrics, null, 2));
    }

    logExecution(executionId, event, data) {
        const logFile = '/opt/n8n/monitoring/logs/executions.log';
        const logEntry = {
            timestamp: new Date().toISOString(),
            executionId,
            event,
            data
        };
        
        const logLine = JSON.stringify(logEntry) + '\n';
        require('fs').appendFileSync(logFile, logLine);
    }

    getCurrentUserId() {
        // Get current user ID from session storage
        if (typeof window !== 'undefined' && window.sessionStorage) {
            return window.sessionStorage.getItem('n8n_user_id') || 'anonymous';
        }
        return 'anonymous';
    }

    startMetricsCollection() {
        // Collect metrics every 5 minutes
        setInterval(() => {
            this.collectSystemMetrics();
        }, 5 * 60 * 1000);
    }

    collectSystemMetrics() {
        const metrics = {
            timestamp: new Date().toISOString(),
            activeExecutions: this.executions.size,
            memoryUsage: process.memoryUsage ? process.memoryUsage() : null,
            uptime: process.uptime ? process.uptime() : null
        };

        const metricsFile = '/opt/n8n/monitoring/metrics/system_metrics.json';
        require('fs').appendFileSync(metricsFile, JSON.stringify(metrics) + '\n');
    }
}

// Initialize tracker
if (typeof window !== 'undefined') {
    document.addEventListener('DOMContentLoaded', () => {
        window.executionTracker = new ExecutionTracker();
    });
} else if (typeof module !== 'undefined') {
    module.exports = ExecutionTracker;
}
EOF

    log_pass "Execution time tracking configured"
}

# Configure storage monitoring
configure_storage_monitoring() {
    log_info "Configuring storage monitoring..."
    
    # Create storage monitor script
    cat > /opt/n8n/scripts/storage-monitor.sh << 'EOF'
#!/bin/bash

# Storage Monitor Script
# Monitors per-user storage usage and enforces quotas

USER_BASE_DIR="/opt/n8n/users"
METRICS_DIR="/opt/n8n/monitoring/metrics"
ALERTS_DIR="/opt/n8n/monitoring/alerts"

# Function to get directory size in bytes
get_directory_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        du -sb "$dir" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Function to convert bytes to human readable format
bytes_to_human() {
    local bytes="$1"
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt $((1024*1024)) ]]; then
        echo "$((bytes/1024))KB"
    elif [[ $bytes -lt $((1024*1024*1024)) ]]; then
        echo "$((bytes/(1024*1024)))MB"
    else
        echo "$((bytes/(1024*1024*1024)))GB"
    fi
}

# Function to monitor user storage
monitor_user_storage() {
    local user_id="$1"
    local user_dir="$USER_BASE_DIR/$user_id"
    
    if [[ ! -d "$user_dir" ]]; then
        return
    fi
    
    # Get current storage usage
    local total_size=$(get_directory_size "$user_dir")
    local workflows_size=$(get_directory_size "$user_dir/workflows")
    local files_size=$(get_directory_size "$user_dir/files")
    local logs_size=$(get_directory_size "$user_dir/logs")
    local temp_size=$(get_directory_size "$user_dir/temp")
    
    # Get user quota from config
    local quota_bytes=1073741824  # Default 1GB
    if [[ -f "$user_dir/user-config.json" ]]; then
        local quota_str=$(jq -r '.quotas.storage' "$user_dir/user-config.json" 2>/dev/null)
        if [[ "$quota_str" =~ ^([0-9]+)GB$ ]]; then
            quota_bytes=$((${BASH_REMATCH[1]} * 1024 * 1024 * 1024))
        fi
    fi
    
    # Calculate usage percentage
    local usage_percent=$((total_size * 100 / quota_bytes))
    
    # Create storage metrics
    local timestamp=$(date -Iseconds)
    local metrics_file="$METRICS_DIR/${user_id}_storage.json"
    
    cat > "$metrics_file" << EOL
{
  "userId": "$user_id",
  "timestamp": "$timestamp",
  "storage": {
    "totalBytes": $total_size,
    "totalHuman": "$(bytes_to_human $total_size)",
    "quotaBytes": $quota_bytes,
    "quotaHuman": "$(bytes_to_human $quota_bytes)",
    "usagePercent": $usage_percent,
    "breakdown": {
      "workflows": {
        "bytes": $workflows_size,
        "human": "$(bytes_to_human $workflows_size)"
      },
      "files": {
        "bytes": $files_size,
        "human": "$(bytes_to_human $files_size)"
      },
      "logs": {
        "bytes": $logs_size,
        "human": "$(bytes_to_human $logs_size)"
      },
      "temp": {
        "bytes": $temp_size,
        "human": "$(bytes_to_human $temp_size)"
      }
    }
  }
}
EOL

    # Check for quota violations
    if [[ $usage_percent -ge 95 ]]; then
        create_storage_alert "$user_id" "critical" "$usage_percent" "$total_size" "$quota_bytes"
    elif [[ $usage_percent -ge 80 ]]; then
        create_storage_alert "$user_id" "warning" "$usage_percent" "$total_size" "$quota_bytes"
    fi
    
    # Log storage info
    echo "$(date -Iseconds) [INFO] User $user_id: $(bytes_to_human $total_size)/$(bytes_to_human $quota_bytes) (${usage_percent}%)" >> /opt/n8n/monitoring/logs/storage.log
}

# Function to create storage alerts
create_storage_alert() {
    local user_id="$1"
    local level="$2"
    local usage_percent="$3"
    local total_size="$4"
    local quota_bytes="$5"
    
    local alert_file="$ALERTS_DIR/${user_id}_storage_${level}_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$alert_file" << EOL
{
  "alertId": "$(uuidgen 2>/dev/null || echo "alert_$(date +%s)")",
  "userId": "$user_id",
  "type": "storage_quota",
  "level": "$level",
  "timestamp": "$(date -Iseconds)",
  "message": "User storage usage is at ${usage_percent}%",
  "details": {
    "usagePercent": $usage_percent,
    "totalBytes": $total_size,
    "totalHuman": "$(bytes_to_human $total_size)",
    "quotaBytes": $quota_bytes,
    "quotaHuman": "$(bytes_to_human $quota_bytes)"
  },
  "actions": {
    "cleanup": "/opt/n8n/scripts/cleanup-user-data.sh $user_id",
    "increaseQuota": "/opt/n8n/scripts/increase-user-quota.sh $user_id"
  }
}
EOL

    # Log alert
    echo "$(date -Iseconds) [ALERT] Storage $level for user $user_id: ${usage_percent}%" >> /opt/n8n/monitoring/logs/alerts.log
}

# Main monitoring function
main() {
    echo "Starting storage monitoring at $(date)"
    
    # Monitor all users
    for user_dir in "$USER_BASE_DIR"/*; do
        if [[ -d "$user_dir" ]]; then
            user_id=$(basename "$user_dir")
            monitor_user_storage "$user_id"
        fi
    done
    
    echo "Storage monitoring completed at $(date)"
}

# Run main function
main "$@"
EOF

    chmod +x /opt/n8n/scripts/storage-monitor.sh
    
    log_pass "Storage monitoring configured"
}

# Configure workflow statistics tracking
configure_workflow_statistics() {
    log_info "Configuring workflow statistics tracking..."
    
    # Create workflow stats collector
    cat > /opt/n8n/scripts/workflow-stats.js << 'EOF'
// Workflow Statistics Collector

class WorkflowStats {
    constructor() {
        this.statsPath = '/opt/n8n/monitoring/analytics';
        this.init();
    }

    init() {
        this.setupWorkflowHooks();
        this.startStatsCollection();
    }

    setupWorkflowHooks() {
        if (window.n8n && window.n8n.hooks) {
            window.n8n.hooks.on('workflow.created', this.onWorkflowCreated.bind(this));
            window.n8n.hooks.on('workflow.updated', this.onWorkflowUpdated.bind(this));
            window.n8n.hooks.on('workflow.deleted', this.onWorkflowDeleted.bind(this));
            window.n8n.hooks.on('workflow.activated', this.onWorkflowActivated.bind(this));
            window.n8n.hooks.on('workflow.deactivated', this.onWorkflowDeactivated.bind(this));
        }
    }

    onWorkflowCreated(data) {
        this.recordWorkflowEvent('created', data);
    }

    onWorkflowUpdated(data) {
        this.recordWorkflowEvent('updated', data);
    }

    onWorkflowDeleted(data) {
        this.recordWorkflowEvent('deleted', data);
    }

    onWorkflowActivated(data) {
        this.recordWorkflowEvent('activated', data);
    }

    onWorkflowDeactivated(data) {
        this.recordWorkflowEvent('deactivated', data);
    }

    recordWorkflowEvent(event, data) {
        const userId = this.getCurrentUserId();
        const timestamp = new Date().toISOString();
        
        const eventRecord = {
            timestamp,
            userId,
            event,
            workflowId: data.workflowId,
            workflowName: data.name || 'Unknown',
            nodeCount: data.nodes ? data.nodes.length : 0
        };

        // Log to workflow events file
        this.appendToFile(`${this.statsPath}/workflow_events.log`, JSON.stringify(eventRecord));
        
        // Update user workflow statistics
        this.updateUserWorkflowStats(userId, event, data);
    }

    updateUserWorkflowStats(userId, event, data) {
        const statsFile = `${this.statsPath}/${userId}_workflow_stats.json`;
        
        let stats = {};
        try {
            const fileData = require('fs').readFileSync(statsFile, 'utf8');
            stats = JSON.parse(fileData);
        } catch (error) {
            stats = {
                userId,
                totalWorkflows: 0,
                activeWorkflows: 0,
                totalNodes: 0,
                events: {
                    created: 0,
                    updated: 0,
                    deleted: 0,
                    activated: 0,
                    deactivated: 0
                },
                lastActivity: null
            };
        }

        // Update event counters
        if (stats.events[event] !== undefined) {
            stats.events[event]++;
        }

        // Update workflow counts
        if (event === 'created') {
            stats.totalWorkflows++;
            stats.totalNodes += data.nodes ? data.nodes.length : 0;
        } else if (event === 'deleted') {
            stats.totalWorkflows = Math.max(0, stats.totalWorkflows - 1);
        } else if (event === 'activated') {
            stats.activeWorkflows++;
        } else if (event === 'deactivated') {
            stats.activeWorkflows = Math.max(0, stats.activeWorkflows - 1);
        }

        stats.lastActivity = new Date().toISOString();

        // Write updated stats
        require('fs').writeFileSync(statsFile, JSON.stringify(stats, null, 2));
    }

    getCurrentUserId() {
        if (typeof window !== 'undefined' && window.sessionStorage) {
            return window.sessionStorage.getItem('n8n_user_id') || 'anonymous';
        }
        return 'anonymous';
    }

    appendToFile(filepath, content) {
        try {
            require('fs').appendFileSync(filepath, content + '\n');
        } catch (error) {
            console.error('Failed to write to file:', filepath, error);
        }
    }

    startStatsCollection() {
        // Collect workflow statistics every hour
        setInterval(() => {
            this.collectWorkflowStats();
        }, 60 * 60 * 1000);
    }

    collectWorkflowStats() {
        const userId = this.getCurrentUserId();
        if (userId === 'anonymous') return;

        // Collect current workflow statistics
        this.generateHourlyReport(userId);
    }

    generateHourlyReport(userId) {
        const timestamp = new Date().toISOString();
        const hour = new Date().getHours();
        
        const report = {
            timestamp,
            userId,
            hour,
            activeExecutions: 0,  // Would need to get from execution tracker
            systemLoad: process.loadavg ? process.loadavg() : [0, 0, 0]
        };

        this.appendToFile(`${this.statsPath}/hourly_reports.log`, JSON.stringify(report));
    }
}

// Initialize stats collector
if (typeof window !== 'undefined') {
    document.addEventListener('DOMContentLoaded', () => {
        window.workflowStats = new WorkflowStats();
    });
} else if (typeof module !== 'undefined') {
    module.exports = WorkflowStats;
}
EOF

    log_pass "Workflow statistics tracking configured"
}

# Configure user analytics
configure_user_analytics() {
    log_info "Configuring user analytics..."
    
    # Create analytics processor
    cat > /opt/n8n/scripts/analytics-processor.sh << 'EOF'
#!/bin/bash

# Analytics Processor Script
# Processes user data and generates analytics reports

METRICS_DIR="/opt/n8n/monitoring/metrics"
ANALYTICS_DIR="/opt/n8n/monitoring/analytics"
REPORTS_DIR="/opt/n8n/monitoring/reports"

# Generate daily user report
generate_daily_report() {
    local user_id="$1"
    local date="${2:-$(date +%Y-%m-%d)}"
    
    echo "Generating daily report for user $user_id on $date"
    
    local report_file="$REPORTS_DIR/${user_id}_daily_${date}.json"
    
    # Collect metrics for the day
    local execution_metrics=""
    local storage_metrics=""
    local workflow_stats=""
    
    if [[ -f "$METRICS_DIR/${user_id}_${date}.json" ]]; then
        execution_metrics=$(cat "$METRICS_DIR/${user_id}_${date}.json")
    fi
    
    if [[ -f "$METRICS_DIR/${user_id}_storage.json" ]]; then
        storage_metrics=$(cat "$METRICS_DIR/${user_id}_storage.json")
    fi
    
    if [[ -f "$ANALYTICS_DIR/${user_id}_workflow_stats.json" ]]; then
        workflow_stats=$(cat "$ANALYTICS_DIR/${user_id}_workflow_stats.json")
    fi
    
    # Generate report
    cat > "$report_file" << EOL
{
  "reportType": "daily",
  "userId": "$user_id",
  "date": "$date",
  "generatedAt": "$(date -Iseconds)",
  "executionMetrics": $execution_metrics,
  "storageMetrics": $storage_metrics,
  "workflowStats": $workflow_stats,
  "summary": {
    "totalExecutions": $(echo "$execution_metrics" | jq -r '.summary.count // 0' 2>/dev/null),
    "successRate": $(echo "$execution_metrics" | jq -r '(.summary.successful // 0) / (.summary.count // 1) * 100' 2>/dev/null),
    "averageExecutionTime": $(echo "$execution_metrics" | jq -r '(.summary.totalDuration // 0) / (.summary.count // 1)' 2>/dev/null),
    "storageUsagePercent": $(echo "$storage_metrics" | jq -r '.storage.usagePercent // 0' 2>/dev/null)
  }
}
EOL
    
    echo "Daily report generated: $report_file"
}

# Generate weekly user report
generate_weekly_report() {
    local user_id="$1"
    local week_start="${2:-$(date -d 'last monday' +%Y-%m-%d)}"
    
    echo "Generating weekly report for user $user_id starting $week_start"
    
    local report_file="$REPORTS_DIR/${user_id}_weekly_${week_start}.json"
    
    # Collect data for the week
    local total_executions=0
    local total_duration=0
    local successful_executions=0
    
    # Aggregate daily reports for the week
    for i in {0..6}; do
        local date=$(date -d "$week_start + $i days" +%Y-%m-%d)
        local daily_file="$METRICS_DIR/${user_id}_${date}.json"
        
        if [[ -f "$daily_file" ]]; then
            local day_executions=$(jq -r '.summary.count // 0' "$daily_file" 2>/dev/null)
            local day_duration=$(jq -r '.summary.totalDuration // 0' "$daily_file" 2>/dev/null)
            local day_successful=$(jq -r '.summary.successful // 0' "$daily_file" 2>/dev/null)
            
            total_executions=$((total_executions + day_executions))
            total_duration=$((total_duration + day_duration))
            successful_executions=$((successful_executions + day_successful))
        fi
    done
    
    # Calculate averages
    local avg_duration=0
    local success_rate=0
    if [[ $total_executions -gt 0 ]]; then
        avg_duration=$((total_duration / total_executions))
        success_rate=$((successful_executions * 100 / total_executions))
    fi
    
    # Generate weekly report
    cat > "$report_file" << EOL
{
  "reportType": "weekly",
  "userId": "$user_id",
  "weekStart": "$week_start",
  "weekEnd": "$(date -d "$week_start + 6 days" +%Y-%m-%d)",
  "generatedAt": "$(date -Iseconds)",
  "summary": {
    "totalExecutions": $total_executions,
    "successfulExecutions": $successful_executions,
    "totalDuration": $total_duration,
    "averageDuration": $avg_duration,
    "successRate": $success_rate,
    "dailyAverage": $((total_executions / 7))
  }
}
EOL
    
    echo "Weekly report generated: $report_file"
}

# Generate monthly report
generate_monthly_report() {
    local user_id="$1"
    local month="${2:-$(date +%Y-%m)}"
    
    echo "Generating monthly report for user $user_id for $month"
    
    local report_file="$REPORTS_DIR/${user_id}_monthly_${month}.json"
    
    # Find all daily reports for the month
    local monthly_data=""
    for daily_file in "$METRICS_DIR"/${user_id}_${month}-*.json; do
        if [[ -f "$daily_file" ]]; then
            if [[ -z "$monthly_data" ]]; then
                monthly_data="[$(<"$daily_file")]"
            else
                monthly_data=$(echo "$monthly_data" | jq ". + [$(<"$daily_file")]")
            fi
        fi
    done
    
    if [[ -z "$monthly_data" ]]; then
        monthly_data="[]"
    fi
    
    # Calculate monthly aggregates
    local total_executions=$(echo "$monthly_data" | jq '[.[].summary.count // 0] | add')
    local total_duration=$(echo "$monthly_data" | jq '[.[].summary.totalDuration // 0] | add')
    local successful_executions=$(echo "$monthly_data" | jq '[.[].summary.successful // 0] | add')
    
    cat > "$report_file" << EOL
{
  "reportType": "monthly",
  "userId": "$user_id",
  "month": "$month",
  "generatedAt": "$(date -Iseconds)",
  "summary": {
    "totalExecutions": $total_executions,
    "successfulExecutions": $successful_executions,
    "totalDuration": $total_duration,
    "averageDuration": $((total_duration / (total_executions > 0 ? total_executions : 1))),
    "successRate": $((successful_executions * 100 / (total_executions > 0 ? total_executions : 1)))
  },
  "dailyData": $monthly_data
}
EOL
    
    echo "Monthly report generated: $report_file"
}

# Main function
main() {
    local command="$1"
    local user_id="$2"
    local date_param="$3"
    
    case "$command" in
        "daily")
            if [[ -z "$user_id" ]]; then
                echo "Error: User ID required for daily report"
                exit 1
            fi
            generate_daily_report "$user_id" "$date_param"
            ;;
        "weekly")
            if [[ -z "$user_id" ]]; then
                echo "Error: User ID required for weekly report"
                exit 1
            fi
            generate_weekly_report "$user_id" "$date_param"
            ;;
        "monthly")
            if [[ -z "$user_id" ]]; then
                echo "Error: User ID required for monthly report"
                exit 1
            fi
            generate_monthly_report "$user_id" "$date_param"
            ;;
        "all")
            # Generate reports for all users
            for user_dir in /opt/n8n/users/*; do
                if [[ -d "$user_dir" ]]; then
                    local uid=$(basename "$user_dir")
                    generate_daily_report "$uid"
                fi
            done
            ;;
        *)
            echo "Usage: $0 {daily|weekly|monthly|all} <user_id> [date]"
            echo "Examples:"
            echo "  $0 daily user123"
            echo "  $0 weekly user123 2024-01-01"
            echo "  $0 monthly user123 2024-01"
            echo "  $0 all"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
EOF

    chmod +x /opt/n8n/scripts/analytics-processor.sh
    
    log_pass "User analytics configured"
}

# Configure automated cleanup
configure_automated_cleanup() {
    log_info "Configuring automated cleanup for inactive users..."
    
    # Create cleanup script
    cat > /opt/n8n/scripts/cleanup-inactive-users.sh << 'EOF'
#!/bin/bash

# Cleanup Inactive Users Script
# Removes data for users inactive for specified period

USERS_DIR="/opt/n8n/users"
METRICS_DIR="/opt/n8n/monitoring/metrics"
BACKUP_DIR="/opt/n8n/backups"
INACTIVE_DAYS="${INACTIVE_DAYS:-90}"

# Function to check user last activity
get_last_activity() {
    local user_id="$1"
    local user_config="$USERS_DIR/$user_id/user-config.json"
    local metrics_file="$METRICS_DIR/${user_id}_current.json"
    
    local last_activity="1970-01-01T00:00:00Z"
    
    # Check user config
    if [[ -f "$user_config" ]]; then
        local config_activity=$(jq -r '.lastActivity // empty' "$user_config" 2>/dev/null)
        if [[ -n "$config_activity" ]]; then
            last_activity="$config_activity"
        fi
    fi
    
    # Check metrics file
    if [[ -f "$metrics_file" ]]; then
        local metrics_activity=$(jq -r '.lastActivity // empty' "$metrics_file" 2>/dev/null)
        if [[ -n "$metrics_activity" ]]; then
            # Use the more recent date
            if [[ "$metrics_activity" > "$last_activity" ]]; then
                last_activity="$metrics_activity"
            fi
        fi
    fi
    
    echo "$last_activity"
}

# Function to calculate days since last activity
days_since_activity() {
    local last_activity="$1"
    local current_date=$(date +%s)
    local activity_date=$(date -d "$last_activity" +%s 2>/dev/null || echo "0")
    local diff_seconds=$((current_date - activity_date))
    local diff_days=$((diff_seconds / 86400))
    echo "$diff_days"
}

# Function to cleanup user data
cleanup_user() {
    local user_id="$1"
    local backup_created="$2"
    
    echo "Cleaning up inactive user: $user_id"
    
    # Remove user directory
    if [[ -d "$USERS_DIR/$user_id" ]]; then
        rm -rf "$USERS_DIR/$user_id"
        echo "Removed user directory: $USERS_DIR/$user_id"
    fi
    
    # Remove user metrics
    rm -f "$METRICS_DIR/${user_id}"*
    echo "Removed user metrics"
    
    # Remove user sessions
    rm -f "/opt/n8n/user-sessions/${user_id}"*
    echo "Removed user sessions"
    
    # Remove user logs
    rm -f "/opt/n8n/user-logs/${user_id}"*
    echo "Removed user logs"
    
    # Log cleanup action
    echo "$(date -Iseconds) [CLEANUP] User $user_id cleaned up (backup: $backup_created)" >> /opt/n8n/monitoring/logs/cleanup.log
}

# Main cleanup function
main() {
    echo "Starting cleanup of inactive users (inactive for $INACTIVE_DAYS days)"
    
    local cleaned_count=0
    local backed_up_count=0
    
    for user_dir in "$USERS_DIR"/*; do
        if [[ -d "$user_dir" ]]; then
            local user_id=$(basename "$user_dir")
            local last_activity=$(get_last_activity "$user_id")
            local days_inactive=$(days_since_activity "$last_activity")
            
            echo "User $user_id: last activity $last_activity ($days_inactive days ago)"
            
            if [[ $days_inactive -ge $INACTIVE_DAYS ]]; then
                echo "User $user_id is inactive for $days_inactive days, cleaning up..."
                
                # Create backup before cleanup
                local backup_file="$BACKUP_DIR/inactive_user_${user_id}_$(date +%Y%m%d_%H%M%S).tar.gz"
                if tar -czf "$backup_file" -C "$USERS_DIR" "$user_id" 2>/dev/null; then
                    echo "Backup created: $backup_file"
                    backed_up_count=$((backed_up_count + 1))
                    cleanup_user "$user_id" "yes"
                else
                    echo "Failed to create backup for $user_id, skipping cleanup"
                    cleanup_user "$user_id" "no"
                fi
                
                cleaned_count=$((cleaned_count + 1))
            fi
        fi
    done
    
    echo "Cleanup completed: $cleaned_count users cleaned up, $backed_up_count backups created"
}

# Run main function
main "$@"
EOF

    chmod +x /opt/n8n/scripts/cleanup-inactive-users.sh
    
    # Add to crontab for daily execution
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/n8n/scripts/cleanup-inactive-users.sh >> /opt/n8n/monitoring/logs/cleanup.log 2>&1") | crontab -
    
    log_pass "Automated cleanup configured"
}

# Setup monitoring cron jobs
setup_monitoring_cron() {
    log_info "Setting up monitoring cron jobs..."
    
    # Add storage monitoring every 15 minutes
    (crontab -l 2>/dev/null; echo "*/15 * * * * /opt/n8n/scripts/storage-monitor.sh >> /opt/n8n/monitoring/logs/storage-monitor.log 2>&1") | crontab -
    
    # Add daily reports generation
    (crontab -l 2>/dev/null; echo "0 1 * * * /opt/n8n/scripts/analytics-processor.sh all >> /opt/n8n/monitoring/logs/analytics.log 2>&1") | crontab -
    
    log_pass "Monitoring cron jobs configured"
}

# Main execution function
main() {
    log_info "Starting user monitoring configuration..."
    
    load_environment
    create_monitoring_directories
    configure_execution_tracking
    configure_storage_monitoring
    configure_workflow_statistics
    configure_user_analytics
    configure_automated_cleanup
    setup_monitoring_cron
    
    log_pass "User monitoring configuration completed successfully"
    log_info "Monitoring data will be stored in: /opt/n8n/monitoring/"
    log_info "Scripts available in: /opt/n8n/scripts/"
    log_info "Storage monitoring runs every 15 minutes"
    log_info "Daily reports generated at 1 AM"
    log_info "Inactive user cleanup runs daily at 2 AM"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
