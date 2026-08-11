FROM nginx:alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752

# These labels are the only metadata a plain `docker build` produces. In CI,
# metadata-action overwrites description, licenses and source with the same or
# better values, and adds created, revision and version. Keep build-time facts
# out of here: they belong to the workflow, not the Dockerfile.
LABEL org.opencontainers.image.title="nginx-reverse-proxy" \
      org.opencontainers.image.authors="Christian Kaczmarek" \
      org.opencontainers.image.description="Opinionated nginx reverse proxy Docker image for homelabs, with modern TLS and security headers" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/kaczmar2/nginx-reverse-proxy"

# Create directory structure to match expected volume mounts
RUN mkdir -p /etc/nginx/includes \
    && mkdir -p /etc/nginx/sites \
    && mkdir -p /etc/nginx/ssl

# Copy nginx configuration
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/conf.d/ /etc/nginx/conf.d/
COPY config/includes/ /etc/nginx/includes/

# Copy example site configurations as templates for reference
COPY config/sites/ /etc/nginx/sites.template/

# Copy the default blackhole config to active sites directory
COPY config/sites/00-default-blackhole.conf /etc/nginx/sites/00-default-blackhole.conf

# Copy custom HTML files
COPY html/ /usr/share/nginx/html/

# Set proper permissions
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chmod -R 755 /usr/share/nginx/html

# Expose standard HTTP and HTTPS ports
EXPOSE 80 443

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1/healthz || exit 1

# Use the default nginx command
CMD ["nginx", "-g", "daemon off;"]