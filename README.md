# nginx-reverse-proxy

[![Docker Build, Test and Publish](https://github.com/kaczmar2/nginx-reverse-proxy/actions/workflows/docker-build.yml/badge.svg)](https://github.com/kaczmar2/nginx-reverse-proxy/actions/workflows/docker-build.yml)

An opinionated nginx reverse proxy image for homelab use. The image contains a
complete nginx configuration with modern TLS settings, security headers, and
reusable include files. You only write the configuration for your own services.

- **Source:** <https://github.com/kaczmar2/nginx-reverse-proxy>
- **Docker Hub:** `kaczmar2/nginx-reverse-proxy`
- **GitHub Container Registry:** `ghcr.io/kaczmar2/nginx-reverse-proxy`
- **License:** MIT

## Contents

- [What the image provides](#what-the-image-provides)
- [Images, tags, and platforms](#images-tags-and-platforms)
- [Quick start](#quick-start)
- [Default behavior](#default-behavior)
- [Important: mounting your own sites directory](#important-mounting-your-own-sites-directory)
- [Directory layout](#directory-layout)
- [Volume mounts](#volume-mounts)
- [Step-by-step setup](#step-by-step-setup)
- [Example site configurations](#example-site-configurations)
- [Include file reference](#include-file-reference)
- [TLS certificates with acme.sh](#tls-certificates-with-acmesh)
- [Access logs](#access-logs)
- [Health check](#health-check)
- [Customizing the HTML pages](#customizing-the-html-pages)
- [Troubleshooting](#troubleshooting)
- [Building from source](#building-from-source)

## What the image provides

The image is based on `nginx:alpine`. The base image is pinned to a digest and
updated automatically by Renovate.

Built into the image:

| Path | Purpose |
| --- | --- |
| `/etc/nginx/nginx.conf` | Main configuration. Loads `conf.d/*.conf` and `sites/*.conf`. |
| `/etc/nginx/conf.d/default.conf` | Intentionally empty. See the note below. |
| `/etc/nginx/includes/` | Seven reusable configuration snippets. |
| `/etc/nginx/sites/00-default-blackhole.conf` | The active default server. |
| `/etc/nginx/sites.template/` | Read-only copies of all example configurations. |
| `/usr/share/nginx/html/index.html` | Landing page. |
| `/usr/share/nginx/html/errors/` | Custom 404 and 50x pages. |

`conf.d/default.conf` is empty on purpose. The default server lives in
`sites/00-default-blackhole.conf` instead, so that the load order of all virtual
hosts is controlled in one directory.

You manage two directories:

- `sites/` — one configuration file per service you proxy.
- `ssl/` — TLS certificates, in one subdirectory per domain.

## Images, tags, and platforms

Both registries receive the same image.

```bash
docker pull kaczmar2/nginx-reverse-proxy
docker pull ghcr.io/kaczmar2/nginx-reverse-proxy
```

Available tags:

- `latest` — the most recent release.
- Version tags such as `1.6.3` — a fixed release.

For a stable system, pin a version tag. The `latest` tag moves whenever the
nginx base image receives a security update, which happens often.

Supported platforms: `linux/amd64`, `linux/arm64`, `linux/arm/v7`.

## Quick start

You need Docker installed. For a real deployment you also need a domain name
that points to the machine running the proxy, and a TLS certificate for each
hostname you serve.

Run the image with no configuration to confirm that it works:

```bash
docker run -d --name nginx-proxy -p 80:80 -p 443:443 \
  kaczmar2/nginx-reverse-proxy
```

Open `http://localhost`. You should see the landing page.

## Default behavior

Before you add any configuration, the image responds like this:

| Request | Response |
| --- | --- |
| HTTP request to any hostname | The landing page. |
| `GET /healthz` over HTTP | `200` with the body `ok`. |
| HTTP request for a missing page | The custom 404 page. |
| HTTPS request to any hostname | The TLS handshake is rejected. |

The HTTPS default server uses `ssl_reject_handshake on`. Any client that asks
for a hostname you have not configured receives no certificate and no response.
This prevents the proxy from presenting a certificate for the wrong service.

After you add your own site configurations, requests that match a `server_name`
go to that service. Requests that match nothing still reach the default server.

## Important: mounting your own sites directory

**Read this before you mount a volume at `/etc/nginx/sites`.**

The image ships `00-default-blackhole.conf` inside `/etc/nginx/sites/`. A bind
mount replaces the whole directory, so mounting your own `sites/` directory
hides that file.

If you mount an empty `sites/` directory, nginx starts but listens on no port at
all. Every connection is refused, and the container becomes `unhealthy` after
about 90 seconds. This is confusing, because the logs show a normal startup and
report no error.

**The fix:** copy the default server configuration into your own `sites/`
directory before you start the container.

```bash
# Create your directories
mkdir -p sites ssl

# Copy the default server out of the image
docker run --rm --entrypoint cat kaczmar2/nginx-reverse-proxy \
  /etc/nginx/sites.template/00-default-blackhole.conf > sites/00-default-blackhole.conf
```

Keep the `00-` prefix. The file must load first, because nginx assigns
`default_server` to the first matching block it reads.

If you do not want a landing page, you can still keep this file. It also
provides the `/healthz` endpoint that the container health check uses.

## Directory layout

```text
Built into the image (you do not change these):
/etc/nginx/
├── nginx.conf                  # Main config; includes conf.d/ and sites/
├── conf.d/
│   └── default.conf            # Intentionally empty
├── includes/                   # Reusable snippets
│   ├── error_pages.conf
│   ├── hsts_settings.conf
│   ├── http_common.conf
│   ├── proxy_settings.conf
│   ├── security_headers.conf
│   ├── ssl_settings.conf
│   └── websocket_settings.conf
└── sites.template/             # Example configs, for reference only

You manage these (mounted from the host):
./sites/                        # Your service configurations
│   ├── 00-default-blackhole.conf
│   ├── 01-myservice.conf
│   └── 02-another.conf
└── ./ssl/                      # Certificates, one directory per domain
    ├── service.example.com/
    │   ├── fullchain.pem
    │   └── privkey.pem
    └── another.example.com/
        ├── fullchain.pem
        └── privkey.pem
```

Use a numeric prefix on each file in `sites/` to control the load order.

## Volume mounts

| Container path | Required | Purpose |
| --- | --- | --- |
| `/etc/nginx/sites` | Yes, for real use | Your service configurations. |
| `/etc/nginx/ssl` | Yes, for HTTPS | Your certificates. |
| `/usr/share/nginx/html` | No | Replaces all HTML pages. |
| `/usr/share/nginx/html/index.html` | No | Replaces only the landing page. |
| `/usr/share/nginx/html/errors` | No | Replaces only the error pages. |

Compose file:

```yaml
services:
  nginx-proxy:
    image: kaczmar2/nginx-reverse-proxy
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./sites:/etc/nginx/sites   # Must contain 00-default-blackhole.conf
      - ./ssl:/etc/nginx/ssl
    environment:
      - TZ=America/Denver
```

## Step-by-step setup

### Step 1: Create the directories

```bash
mkdir -p nginx-reverse-proxy/{sites,ssl}
cd nginx-reverse-proxy
```

### Step 2: Copy the default server

```bash
docker run --rm --entrypoint cat kaczmar2/nginx-reverse-proxy \
  /etc/nginx/sites.template/00-default-blackhole.conf > sites/00-default-blackhole.conf
```

### Step 3: Copy an example that matches your service

List the available examples:

```bash
docker run --rm kaczmar2/nginx-reverse-proxy ls /etc/nginx/sites.template/
```

Copy the one you want. This example uses the Home Assistant configuration:

```bash
docker run --rm --entrypoint cat kaczmar2/nginx-reverse-proxy \
  /etc/nginx/sites.template/05-ha.mydomain.com.conf > sites/01-ha.conf
```

### Step 4: Edit the configuration

Open `sites/01-ha.conf` and change three things:

1. `server_name` — your domain name.
2. `proxy_pass` — the address and port of your service.
3. The two `ssl_certificate` paths — they must match your domain name.

Example change:

```nginx
# From:
server_name ha.mydomain.com;
proxy_pass http://10.10.20.50:8123;
ssl_certificate     /etc/nginx/ssl/ha.mydomain.com/fullchain.pem;
ssl_certificate_key /etc/nginx/ssl/ha.mydomain.com/privkey.pem;

# To:
server_name home.example.com;
proxy_pass http://192.168.1.100:8123;
ssl_certificate     /etc/nginx/ssl/home.example.com/fullchain.pem;
ssl_certificate_key /etc/nginx/ssl/home.example.com/privkey.pem;
```

Remember to change `server_name` in **both** server blocks. The first block
redirects HTTP to HTTPS. The second block serves the site.

### Step 5: Install a certificate

See [TLS certificates with acme.sh](#tls-certificates-with-acmesh) below. The
files must be at `ssl/<your-domain>/fullchain.pem` and
`ssl/<your-domain>/privkey.pem`.

### Step 6: Start the container

```bash
docker compose up -d
docker exec nginx-proxy nginx -t
docker compose logs nginx-proxy
```

### Step 7: Test

```bash
# Health endpoint
curl http://localhost/healthz

# HTTP redirects to HTTPS
curl -I http://home.example.com

# The service responds over HTTPS
curl -I https://home.example.com
```

### Step 8: Add more services

Repeat steps 3 to 5 for each service. Use a new number prefix for each file.
After you add a file, reload nginx without stopping it:

```bash
docker exec nginx-proxy nginx -t && docker exec nginx-proxy nginx -s reload
```

## Example site configurations

These files are in `/etc/nginx/sites.template/` inside the image. They use the
placeholder domain `mydomain.com` and private IP addresses. Change both.

| File | Service | What it demonstrates |
| --- | --- | --- |
| `00-default-blackhole.conf` | Default server | Landing page, `/healthz`, and rejection of unknown HTTPS hostnames. |
| `01-unifi.mydomain.com.conf` | UniFi Network Application | Proxy to an HTTPS backend that uses a self-signed certificate. WebSocket support. |
| `02-nas.mydomain.com.conf` | Synology DSM | Unlimited upload size and long timeouts for File Station. |
| `03-pihole.mydomain.com.conf` | Pi-hole | The simplest case: plain HTTP backend, no WebSocket. |
| `04-print.mydomain.com.conf` | Printer web interface | A `Connection: keep-alive` header for embedded web servers. |
| `05-ha.mydomain.com.conf` | Home Assistant | Two backends in one server block. Z-Wave JS UI is served under `/zwave/` using a rewrite. |
| `06-plex.mydomain.com.conf` | Plex Media Server | An `upstream` block with keepalive, long timeouts, and buffering disabled for media streams. |

Every example includes an HTTP to HTTPS redirect, TLS settings, and security
headers.

Two details to note when you read the examples:

- `03-pihole.mydomain.com.conf` uses the hostname `ns1.mydomain.com` inside the
  file, not `pihole.mydomain.com`. The file name and the hostname do not match.
- In `05-ha.mydomain.com.conf`, the `/zwave/` block must come before the `/`
  block. nginx matches prefix locations by length, but keeping the specific
  block first makes the intent clear.

## Include file reference

Include files reduce repetition. Each one belongs in a specific place in the
configuration. Putting an include in the wrong scope causes a startup error.

| File | Where to include it | What it does |
| --- | --- | --- |
| `ssl_settings.conf` | Inside `server { }` | TLS 1.2 and 1.3 only, a modern cipher list, and X25519 curve preference. |
| `hsts_settings.conf` | Inside `server { }` | Adds `Strict-Transport-Security` with a one-year lifetime. |
| `security_headers.conf` | Inside `server { }` | Adds `X-Content-Type-Options`, `Referrer-Policy`, and `X-Frame-Options`. |
| `error_pages.conf` | Inside `server { }` | Serves the custom 404 and 50x pages. |
| `proxy_settings.conf` | Inside `location { }` | Sets HTTP/1.1 and the `Host`, `X-Real-IP`, `X-Forwarded-For`, and `X-Forwarded-Proto` headers. |
| `websocket_settings.conf` | Inside `location { }` | Sets the `Upgrade` and `Connection` headers. Requires `proxy_settings.conf` in the same block. |
| `http_common.conf` | Already loaded | TLS session cache, gzip compression, and the `$connection_upgrade` map. |

Do not include `http_common.conf` yourself. `nginx.conf` already loads it at the
`http` level. Including it inside a `server` block fails to start with this
error:

```text
nginx: [emerg] "map" directive is not allowed here in /etc/nginx/includes/http_common.conf:9
```

A minimal service configuration looks like this:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name service.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name service.example.com;

    ssl_certificate     /etc/nginx/ssl/service.example.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/service.example.com/privkey.pem;

    include /etc/nginx/includes/ssl_settings.conf;
    include /etc/nginx/includes/hsts_settings.conf;
    include /etc/nginx/includes/security_headers.conf;
    include /etc/nginx/includes/error_pages.conf;

    location / {
        include /etc/nginx/includes/proxy_settings.conf;
        include /etc/nginx/includes/websocket_settings.conf;

        proxy_pass http://192.168.1.100:8080;
    }
}
```

## TLS certificates with acme.sh

The proxy does not request certificates. Use a separate tool. These steps use
`acme.sh` with a DNS challenge, which works for services that are not reachable
from the internet.

Install acme.sh:

```bash
curl https://get.acme.sh | sh
source ~/.bashrc
```

Request a certificate. This example uses Cloudflare DNS:

```bash
export CF_Email="you@example.com"
export CF_Key="your-cloudflare-global-api-key"

acme.sh --issue --dns dns_cf -d service.example.com --server letsencrypt
```

Install the certificate into the proxy directory:

```bash
mkdir -p ssl/service.example.com

acme.sh --install-cert -d service.example.com \
  --key-file       "$(pwd)/ssl/service.example.com/privkey.pem" \
  --fullchain-file "$(pwd)/ssl/service.example.com/fullchain.pem" \
  --reloadcmd      "docker exec nginx-proxy nginx -s reload"
```

The `--reloadcmd` option matters. acme.sh renews certificates automatically
through a cron job, but nginx keeps the old certificate in memory until you
reload it.

Check the renewal configuration:

```bash
acme.sh --list
acme.sh --renew -d service.example.com --dry-run
```

For other DNS providers, see the
[acme.sh documentation](https://github.com/acmesh-official/acme.sh).

## Access logs

The image uses nginx's standard `main` log format with one extra field at the
end: the requested hostname, from `$host`. This was added in v1.6.0.

```text
$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent
"$http_referer" "$http_user_agent" "$http_x_forwarded_for" "$host"
```

One proxy serves many hostnames, and all of them write to the same log file.
The trailing field lets you separate the traffic for one service:

```bash
# All requests for one hostname
docker logs nginx-proxy 2>/dev/null | grep '"home.example.com"$'

# Request count per hostname
docker exec nginx-proxy sh -c 'awk -F\" "{print \$(NF-1)}" /var/log/nginx/access.log' \
  | sort | uniq -c | sort -rn
```

The field is last, so tools that parse the standard `main` format still work.
Health check requests are not logged, because `00-default-blackhole.conf` sets
`access_log off` on the `/healthz` location.

## Health check

The image defines a Docker health check. It runs every 30 seconds and requests
`http://127.0.0.1/healthz`.

You can also call the endpoint directly:

```bash
curl http://localhost/healthz
# ok
```

Two limits to know:

1. The endpoint is served **only over HTTP**, on the default server. It is not
   available over HTTPS, and it is not available on your own virtual hosts.
2. The endpoint is defined in `00-default-blackhole.conf`. If that file is
   missing from your `sites/` directory, the endpoint disappears and the health
   check fails.

Check the current status:

```bash
docker inspect -f '{{.State.Health.Status}}' nginx-proxy
```

## Customizing the HTML pages

Choose one of these mounts. Do not use more than one at the same time.

Replace only the landing page:

```yaml
- ./html/index.html:/usr/share/nginx/html/index.html
```

Replace only the error pages. The directory must contain `404.html` and
`50x.html`:

```yaml
- ./html/errors:/usr/share/nginx/html/errors
```

Replace everything. The directory must contain `index.html` and an `errors`
subdirectory, or the pages return 404:

```yaml
- ./html:/usr/share/nginx/html
```

## Troubleshooting

### The container is running, but every connection is refused

Your `sites/` directory has no server block listening on port 80 or 443. This
almost always means `00-default-blackhole.conf` is missing. See
[Important: mounting your own sites directory](#important-mounting-your-own-sites-directory).

Confirm what nginx is listening on:

```bash
docker exec nginx-proxy netstat -ltn
```

An empty list confirms the problem.

### nginx does not start

Check the configuration syntax first:

```bash
docker exec nginx-proxy nginx -t
docker logs nginx-proxy
```

A common cause is an include in the wrong scope. See the
[include file reference](#include-file-reference).

### The browser shows a certificate warning

The requested hostname does not match any `server_name`, so the default HTTPS
server handled the request and rejected the handshake. Check for a typo in
`server_name`, and confirm that the file is in `sites/` and ends in `.conf`.

Verify which certificate is served:

```bash
openssl s_client -connect service.example.com:443 -servername service.example.com
```

### The service is not reachable

Test from inside the container. The proxy must be able to reach the backend:

```bash
docker exec nginx-proxy curl -I http://192.168.1.100:8080
```

### WebSocket connections fail

The location block needs both include files, in this order:

```bash
grep -A3 "location /" sites/your-service.conf
```

You should see `proxy_settings.conf` and then `websocket_settings.conf`.

### File uploads fail on large files

nginx limits the request body size. Add this inside the `server` block:

```nginx
client_max_body_size 100M;   # or 0 for no limit
```

## Building from source

```bash
git clone https://github.com/kaczmar2/nginx-reverse-proxy.git
cd nginx-reverse-proxy
docker build -t nginx-reverse-proxy .
```

## License

MIT. See the [LICENSE](LICENSE) file.
