#!/bin/bash
# Renew Let's Encrypt short-lived IP address certificates (6-day lifetime)
# Runs via systemd timer twice daily; re-issues if renewal fails

set -euo pipefail

NGINX_SSL_CONFIG="/etc/nginx/sites-available/openclaw-ssl.conf"
NGINX_HTTP_CONFIG="/etc/nginx/sites-available/openclaw-http.conf"
CERT_DIR="/etc/letsencrypt"
LOG_FILE="/var/log/certbot-renewal.log"
ISSUE_SCRIPT="/opt/certbot/issue-ip-cert.sh"
IP_FILE="/opt/openclaw/cert_ip.txt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_public_ip() {
    if [ -f "$IP_FILE" ]; then
        cat "$IP_FILE"
        return
    fi

    local token ip
    token=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    ip=$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
        "http://169.254.169.254/latest/meta-data/public-ipv4")
    echo "$ip"
}

enable_https_nginx() {
    local ip=$1

    if grep -q "OPENCLAW_IP" "$NGINX_SSL_CONFIG" 2>/dev/null; then
        sed -i "s|OPENCLAW_IP|$ip|g" "$NGINX_SSL_CONFIG"
    fi

    ln -sf "$NGINX_SSL_CONFIG" /etc/nginx/sites-enabled/openclaw-ssl.conf
    rm -f /etc/nginx/sites-enabled/openclaw-http.conf
    nginx -t
    systemctl enable nginx
    systemctl reload nginx
}

enable_http_nginx() {
    ln -sf "$NGINX_HTTP_CONFIG" /etc/nginx/sites-enabled/openclaw-http.conf
    rm -f /etc/nginx/sites-enabled/openclaw-ssl.conf
    nginx -t
    systemctl start nginx
}

cert_exists() {
    local ip=$1
    [ -f "$CERT_DIR/live/$ip/fullchain.pem" ]
}

renew_or_reissue() {
    local ip=$1

    log "Starting certificate renewal for IP: $ip"

    if cert_exists "$ip"; then
        log "Existing certificate found, running certbot renew..."
        if certbot renew \
            --non-interactive \
            --quiet \
            --preferred-profile shortlived \
            --deploy-hook "systemctl reload nginx || true"; then
            enable_https_nginx "$ip"
            log "Renewal completed successfully"
            return 0
        fi
        log "Renewal failed, attempting full re-issue..."
    else
        log "No certificate found, issuing new certificate..."
    fi

    enable_http_nginx
    "$ISSUE_SCRIPT" "$ip"
    enable_https_nginx "$ip"
    log "Certificate (re)issued successfully"
}

main() {
    log "=========================================="
    log "Let's Encrypt IP certificate maintenance"
    log "=========================================="

    IP=$(get_public_ip)
    if [ -z "$IP" ]; then
        log "ERROR: Could not determine public IP"
        exit 1
    fi

    renew_or_reissue "$IP"

    if curl -k -sf -o /dev/null "https://$IP/health" 2>/dev/null; then
        log "HTTPS health check passed"
    else
        log "WARNING: HTTPS health check did not return success (service may still be starting)"
    fi

    log "=========================================="
    log "Certificate maintenance completed"
    log "=========================================="
}

main "$@"
