#!/bin/bash
# Issue or re-issue a Let's Encrypt short-lived IP address certificate (HTTP-01 / webroot)
# Requires Certbot >= 5.3.0 with --ip-address and --preferred-profile shortlived support

set -euo pipefail

IP="${1:?Usage: issue-ip-cert.sh <public-ip>}"
WEBROOT="${WEBROOT:-/var/www/certbot}"
LOG_FILE="${LOG_FILE:-/var/log/certbot-ip-cert.log}"
MIN_CERTBOT_VERSION="5.3.0"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

certbot_version_ok() {
    if ! command -v certbot >/dev/null 2>&1; then
        log "ERROR: certbot not found"
        return 1
    fi
    local version
    version=$(certbot --version 2>&1 | awk '{print $2}')
    if [ "$(printf '%s\n' "$MIN_CERTBOT_VERSION" "$version" | sort -V | head -n1)" != "$MIN_CERTBOT_VERSION" ]; then
        log "ERROR: certbot $version is too old; need >= $MIN_CERTBOT_VERSION for IP certificates"
        return 1
    fi
    log "Using certbot $version"
}

issue_certificate() {
    log "Requesting Let's Encrypt short-lived IP certificate for: $IP"

    mkdir -p "$WEBROOT" /var/log/letsencrypt /var/lib/letsencrypt /etc/letsencrypt
    chown -R www-data:www-data "$WEBROOT" 2>/dev/null || chown -R ubuntu:ubuntu "$WEBROOT"

    if ! systemctl is-active --quiet nginx; then
        log "Starting nginx for HTTP-01 validation..."
        systemctl start nginx
    fi

    certbot certonly \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --preferred-profile shortlived \
        --ip-address "$IP" \
        --webroot \
        --webroot-path "$WEBROOT" \
        --logs-dir /var/log/letsencrypt \
        --work-dir /var/lib/letsencrypt \
        --config-dir /etc/letsencrypt \
        --deploy-hook "systemctl reload nginx || true"

    log "Certificate issued: /etc/letsencrypt/live/$IP/"
}

certbot_version_ok
issue_certificate
