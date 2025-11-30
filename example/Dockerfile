FROM node:18-alpine

WORKDIR /app
ENV NODE_ENV=production

# Install dependencies first (leveraging Docker layer caching)
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci --only=production; else npm install --production; fi

# Copy application source
COPY . .

EXPOSE 3000
CMD ["node", "server.js"]
