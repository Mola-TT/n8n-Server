#!/bin/bash
# Comprehensive Service Status Checker

echo "=== Service Status Check ==="
echo "Timestamp: $(date)"
echo

echo "1. N8N SERVICE STATUS:"
echo "======================"
if curl -s --connect-timeout 5 "http://localhost:5678" >/dev/null 2>&1; then
    echo "✓ n8n is responding on port 5678"
else
    echo "✗ n8n is not responding on port 5678"
fi

if cd /opt/n8n/docker 2>/dev/null; then
    echo "Docker container status:"
    docker-compose ps n8n 2>/dev/null || echo "Cannot check n8n container status"
else
    echo "Cannot access Docker directory"
fi
echo

echo "2. NGINX SERVICE STATUS:"
echo "========================"
systemctl is-active nginx >/dev/null 2>&1 && echo "✓ Nginx service is active" || echo "✗ Nginx service is not active"

if curl -s --connect-timeout 5 "http://localhost" >/dev/null 2>&1; then
    echo "✓ Nginx is responding on port 80"
else
    echo "✗ Nginx is not responding on port 80"
fi

if curl -s --connect-timeout 5 -k "https://localhost" >/dev/null 2>&1; then
    echo "✓ Nginx is responding on port 443 (HTTPS)"
else
    echo "✗ Nginx is not responding on port 443 (HTTPS)"
fi

echo "Nginx configuration test:"
nginx -t 2>&1 | head -2
echo

echo "3. REDIS SERVICE STATUS:"
echo "========================"
if cd /opt/n8n/docker 2>/dev/null && docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; then
    echo "✓ Redis Docker container is responding"
elif redis-cli ping >/dev/null 2>&1; then
    echo "✓ Redis system service is responding"
else
    echo "✗ Redis is not responding (tried both Docker and system)"
fi

if cd /opt/n8n/docker 2>/dev/null; then
    echo "Redis container status:"
    docker-compose ps redis 2>/dev/null || echo "Cannot check Redis container status"
fi
echo

echo "4. NETDATA SERVICE STATUS:"
echo "=========================="
systemctl is-active netdata >/dev/null 2>&1 && echo "✓ Netdata service is active" || echo "✗ Netdata service is not active"

if curl -s --connect-timeout 5 "http://localhost:19999" >/dev/null 2>&1; then
    echo "✓ Netdata is responding on port 19999"
else
    echo "✗ Netdata is not responding on port 19999"
fi
echo

echo "5. LISTENING PORTS:"
echo "==================="
echo "Active listening ports:"
ss -tlnp | grep -E "(5678|80|443|6379|19999)" || echo "No relevant ports found listening"
echo

echo "=== End of Service Status Check ===" 