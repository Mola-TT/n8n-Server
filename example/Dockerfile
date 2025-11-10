# n8n User Management Web Application
# Lightweight Python-based container for serving the static web app

FROM python:3.11-alpine

# Set working directory
WORKDIR /app

# Copy application files
COPY index.html /app/
COPY styles.css /app/
COPY app.js /app/
COPY env-config.js /app/
COPY serve.py /app/
COPY README.md /app/

# Expose port 8080
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/ || exit 1

# Run the Python server
CMD ["python", "serve.py"]

