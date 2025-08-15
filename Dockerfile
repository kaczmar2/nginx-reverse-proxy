FROM nginx:alpine-slim

# Labels following OCI standard (similar to Zabbix approach)
LABEL org.opencontainers.image.authors="Christian Kaczmarek <kacmar2@mail.org>" \
      org.opencontainers.image.description="Opinionated nginx reverse proxy Docker image for homelab use" \
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

# Copy custom HTML files
COPY html/ /usr/share/nginx/html/

# Set proper permissions
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chmod -R 755 /usr/share/nginx/html

# Expose standard HTTP and HTTPS ports
EXPOSE 80 443

# Use the default nginx command
CMD ["nginx", "-g", "daemon off;"]