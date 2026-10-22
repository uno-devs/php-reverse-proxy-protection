FROM nginxinc/nginx-unprivileged:1.28-alpine

COPY templates/default.conf.template /etc/nginx/templates/default.conf.template
COPY --chmod=0755 scripts/15-php2shell-allowlist.sh /docker-entrypoint.d/15-php2shell-allowlist.sh

# Base image already runs as uid 101 (nginx) and listens on unprivileged ports.
USER 101

ENV UPSTREAM=http://php-app:80 \
    CLIENT_MAX_BODY_SIZE=8m \
    UPLOAD_PATHS=""

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/__proxy_health || exit 1
