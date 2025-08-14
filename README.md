# nginx-reverse-proxy

[![Docker Build, Test and Publish](https://github.com/kaczmar2/nginx-reverse-proxy/actions/workflows/docker-build.yml/badge.svg)](https://github.com/kaczmar2/nginx-reverse-proxy/actions/workflows/docker-build.yml) [![Base Image Update Check](https://github.com/kaczmar2/nginx-reverse-proxy/actions/workflows/base-image-update.yml/badge.svg)](https://github.com/kaczmar2/nginx-reverse-proxy/actions/workflows/base-image-update.yml)

An opinionated nginx reverse proxy Docker image designed for easy configuration management in homelab environments. This image provides a battle-tested nginx configuration with modern security settings, requiring users to only manage their site-specific reverse proxy configurations.

## Features

- **Based on `nginx:alpine-slim`** for minimal size and security
- **Opinionated configuration** with proven nginx.conf, SSL settings, and security headers
- **Modular includes** for SSL, proxy headers, WebSocket support, and HSTS
- **Example configurations** for common homelab services (UniFi, Pi-hole, Home Assistant, etc.)
- **Custom landing page** showing the proxy is running
- **SSL-ready** with organized certificate structure

## Quick Start

```bash
# Run with default configuration (serves landing page)
docker run -d \
  --name nginx-proxy \
  -p 80:80 \
  -p 443:443 \
  kaczmar2/nginx-reverse-proxy

# Visit http://localhost to see the landing page
```

## Getting Started Guide

This guide walks you through setting up nginx-reverse-proxy from scratch to a working reverse proxy with SSL.

### Prerequisites

- Docker and Docker Compose installed
- A domain name pointing to your server
- Basic understanding of nginx configuration

### Step 1: Initial Setup

```bash
# Create a new directory for your proxy
mkdir nginx-reverse-proxy && cd nginx-reverse-proxy

# Create the required directory structure
mkdir -p sites ssl

# Download the example docker-compose.yml
wget https://raw.githubusercontent.com/kaczmar2/nginx-reverse-proxy/main/docker-compose.yml
```

### Step 2: Start the Container and Explore Examples

```bash
# Start the container to access example configurations
docker-compose up -d

# Verify it's working - you should see the landing page
curl http://localhost

# List available example configurations
docker exec nginx-proxy ls -la /etc/nginx/sites.template/

# Copy an example that matches your service type
# For a web service (like a NAS):
docker cp nginx-proxy:/etc/nginx/sites.template/01-nas.mydomain.com.conf ./sites/my-service.conf

# For a service needing WebSocket support (like Home Assistant):
docker cp nginx-proxy:/etc/nginx/sites.template/04-ha.mydomain.com.conf ./sites/my-ha.conf
```

### Step 3: Configure Your Service

Edit your copied configuration file:

```bash
nano sites/my-service.conf
```

**Replace these values:**
- `nas.mydomain.com` → your actual domain (e.g., `jellyfin.homelab.local`)
- `10.10.10.30:5000` → your service's IP:port (e.g., `192.168.1.100:8096`)
- SSL certificate paths → match your domain name

**Example modification:**
```nginx
# Change from:
server_name nas.mydomain.com;
proxy_pass http://10.10.10.30:5000;
ssl_certificate /etc/nginx/ssl/nas.mydomain.com/fullchain.pem;

# To:
server_name jellyfin.homelab.local;
proxy_pass http://192.168.1.100:8096;
ssl_certificate /etc/nginx/ssl/jellyfin.homelab.local/fullchain.pem;
```

### Step 4: Generate SSL Certificates

We'll use acme.sh for SSL certificate generation. Install it first if you haven't already:

```bash
# Install acme.sh
curl https://get.acme.sh | sh
source ~/.bashrc
```

Generate and install certificates for your domain:

```bash
# Set up your DNS provider credentials (example uses Cloudflare)
export CF_Email="your-email@example.com"
export CF_Key="your-cloudflare-global-api-key"

# Issue the certificate using DNS challenge
acme.sh --issue --dns dns_cf -d your-domain.com --server letsencrypt

# Create the SSL directory for your domain
mkdir -p ssl/your-domain.com

# Install the certificate
acme.sh --install-cert -d your-domain.com \
  --key-file $(pwd)/ssl/your-domain.com/privkey.pem \
  --fullchain-file $(pwd)/ssl/your-domain.com/fullchain.pem \
  --reloadcmd "docker exec nginx-proxy nginx -s reload"
```

For other DNS providers or challenge methods, see the [acme.sh documentation](https://github.com/acmesh-official/acme.sh).

### Step 5: Test and Deploy

```bash
# Start the reverse proxy
docker-compose up -d

# Test the configuration
docker exec nginx-proxy nginx -t

# Check the logs for any errors
docker-compose logs nginx-proxy

# Test your service (replace with your domain)
curl -k https://your-domain.com/health

# If using a browser, navigate to https://your-domain.com
```

### Step 6: Add More Services

For additional services, repeat steps 2-5:

```bash
# Copy another example
docker cp nginx-proxy:/etc/nginx/sites.template/00-unifi.mydomain.com.conf ./sites/unifi.conf

# Edit the configuration
nano sites/unifi.conf

# Generate SSL certificate for the new domain
acme.sh --issue -d unifi.your-domain.com --standalone

# Restart to reload configuration
docker-compose restart nginx-proxy
```

### Common Issues and Solutions

**Issue: Certificate errors**
```bash
# Check certificate files exist and have correct permissions
ls -la ssl/your-domain.com/
# Should show: fullchain.pem (644) and privkey.pem (600)
```

**Issue: Service not accessible**
```bash
# Verify your backend service is reachable from the container
docker exec nginx-proxy ping 192.168.1.100
docker exec nginx-proxy curl http://192.168.1.100:8080
```

**Issue: nginx won't start**
```bash
# Check configuration syntax
docker exec nginx-proxy nginx -t

# Review the logs
docker-compose logs nginx-proxy
```

**Issue: WebSocket connections fail**
```bash
# Ensure your configuration includes WebSocket settings
grep -r "websocket_settings" sites/
# Should show: include /etc/nginx/includes/websocket_settings.conf;
```

### Testing Your Configuration

```bash
# Test SSL certificate
openssl s_client -connect your-domain.com:443 -servername your-domain.com

# Test HTTP to HTTPS redirect
curl -I http://your-domain.com

# Test health endpoint
curl https://your-domain.com/health

# Check response headers for security
curl -I https://your-domain.com
# Should include: Strict-Transport-Security header
```

### Automated Certificate Renewal

acme.sh automatically installs a cron job for certificate renewal, but let's verify it's configured correctly:

```bash
# Check if acme.sh cron job is installed
crontab -l | grep acme.sh

# List all certificates managed by acme.sh
acme.sh --list

# Test renewal (dry run) - doesn't actually renew
acme.sh --renew -d your-domain.com --dry-run

# Force renewal for testing (only use during testing)
acme.sh --renew -d your-domain.com --force

# Check renewal logs
tail -f ~/.acme.sh/acme.sh.log
```

**The automatic renewal will:**
1. Renew certificates before they expire (typically 60 days before expiration)
2. Automatically install renewed certificates to your ssl directory
3. Execute the reload command to restart your nginx container
4. Send email notifications if renewal fails (if configured)

**Manual renewal** (if needed):
```bash
# Renew a specific certificate
acme.sh --renew -d your-domain.com

# Renew all certificates
acme.sh --renew-all
```

### Production Considerations

1. **Backup your certificates and configurations**
2. **Monitor certificate expiration dates**
3. **Use strong SSL ciphers** (already configured in the image)
4. **Keep the Docker image updated**
5. **Monitor nginx logs** for suspicious activity
6. **Consider using fail2ban** for additional security

### Next Steps

- Set up monitoring for your services
- Configure log rotation
- Add additional security headers if needed
- Consider implementing rate limiting for public-facing services

## Getting Started

### 1. Set up your directory structure

```bash
# Create directories for your configurations
mkdir -p sites ssl

# Your directory structure should look like:
# ./sites/          # Your reverse proxy site configs
# ./ssl/             # SSL certificates organized by domain
```

### 2. Copy example configurations

```bash
# Start the container to access examples
docker run -d --name nginx-proxy-temp kaczmar2/nginx-reverse-proxy

# Copy an example configuration
docker cp nginx-proxy-temp:/etc/nginx/sites.template/01-nas.mydomain.com.conf ./sites/my-service.conf

# Clean up
docker stop nginx-proxy-temp && docker rm nginx-proxy-temp
```

### 3. Edit your configuration

```bash
# Edit the copied config file
nano sites/my-service.conf

# Replace:
# - 'nas.mydomain.com' with your actual domain
# - '10.10.10.30:5000' with your service IP:port
# - SSL certificate paths if needed
```

### 4. Generate SSL certificates (recommended)

```bash
# Using acme.sh (recommended method)
# Install acme.sh first: https://github.com/acmesh-official/acme.sh

# Generate certificate for your domain
acme.sh --issue -d your-domain.com --standalone

# Copy certificates to your ssl directory
mkdir -p ssl/your-domain.com
cp ~/.acme.sh/your-domain.com/fullchain.cer ssl/your-domain.com/fullchain.pem
cp ~/.acme.sh/your-domain.com/your-domain.com.key ssl/your-domain.com/privkey.pem
```

### 5. Run with Docker Compose (recommended)

```yaml
# docker-compose.yml
version: '3.8'

services:
  nginx-proxy:
    image: kaczmar2/nginx-reverse-proxy:latest
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./sites:/etc/nginx/sites
      - ./ssl:/etc/nginx/ssl
    environment:
      - TZ=America/Denver
```

```bash
# Start the proxy
docker-compose up -d
```

## Configuration Structure

This image uses an opinionated structure where most configuration is built-in:

```
Built into image (opinionated):
├── nginx.conf              # Main nginx config with WebSocket support
├── conf.d/default.conf     # Serves the landing page
└── includes/               # Reusable configuration snippets
    ├── ssl_settings.conf   # Modern TLS configuration
    ├── proxy_settings.conf # Standard proxy headers
    ├── hsts_settings.conf  # HTTP Strict Transport Security
    ├── websocket_settings.conf # WebSocket proxy support
    └── keepalive_settings.conf # Keep-alive for embedded devices

User manages:
├── sites/                  # Your reverse proxy configurations
└── ssl/                    # SSL certificates organized by domain
    ├── example.com/
    │   ├── fullchain.pem
    │   └── privkey.pem
    └── another.com/
        ├── fullchain.pem
        └── privkey.pem
```

**Site Naming Convention:** Use numbered prefixes (e.g., `00-`, `01-`, `02-`) for your site configs to control the load order.

## Example Site Configurations

Example configurations are included for common homelab services:

- **`00-unifi.mydomain.com.conf`** - UniFi Network Application (UDM-Pro, CloudKey, etc.)
  - HTTPS proxy with WebSocket support for real-time updates
  - Handles self-signed backend certificates
  
- **`01-nas.mydomain.com.conf`** - Synology NAS web interface (DSM)
  - Standard HTTPS proxy for NAS management
  
- **`02-pihole.mydomain.com.conf`** - Pi-hole DNS management interface
  - Simple HTTP-to-HTTPS reverse proxy
  
- **`03-print.mydomain.com.conf`** - HP Printer web interface
  - Includes keep-alive settings for embedded web servers
  
- **`04-ha.mydomain.com.conf`** - Home Assistant with Z-Wave JS UI sub-path
  - Main service on `/` with WebSocket support
  - Z-Wave JS UI accessible at `/zwave/` subdirectory
  - Demonstrates complex URL rewriting and multiple backend services

Each example includes:
- HTTP to HTTPS redirect
- SSL certificate configuration
- Security headers (HSTS)
- Service-specific optimizations

## Volume Mounts

The simplified approach only requires mounting what you customize:

```bash
docker run -d \
  --name nginx-proxy \
  -p 80:80 -p 443:443 \
  -v ./sites:/etc/nginx/sites \
  -v ./ssl:/etc/nginx/ssl \
  kaczmar2/nginx-reverse-proxy
```

Optional mounts:
```bash
# Override the landing page
-v ./custom-html:/usr/share/nginx/html
```

## SSL Certificate Management

### Using acme.sh

Install acme.sh and generate certificates:

```bash
# Install acme.sh
curl https://get.acme.sh | sh
source ~/.bashrc

# Set up DNS provider credentials (example uses Cloudflare)
export CF_Email="your-email@example.com"
export CF_Key="your-cloudflare-global-api-key"

# Issue certificate
acme.sh --issue --dns dns_cf -d your-domain.com --server letsencrypt

# Install certificate
mkdir -p ssl/your-domain.com
acme.sh --install-cert -d your-domain.com \
  --key-file ssl/your-domain.com/privkey.pem \
  --fullchain-file ssl/your-domain.com/fullchain.pem \
  --reloadcmd "docker exec nginx-proxy nginx -s reload"
```

For other DNS providers or challenge methods, see the [acme.sh documentation](https://github.com/acmesh-official/acme.sh).

## Building from Source

```bash
git clone https://github.com/kaczmar2/nginx-reverse-proxy.git
cd nginx-reverse-proxy
docker build -t nginx-reverse-proxy .
```

## Available Images

- **Docker Hub**: `docker pull kaczmar2/nginx-reverse-proxy`
- **GitHub Container Registry**: `docker pull ghcr.io/kaczmar2/nginx-reverse-proxy`

## License

MIT License - see [LICENSE](LICENSE) file for details.