#!/bin/bash
# Certbot Certificate Renewal Script for IP-based HTTPS
# This script handles automatic renewal of Let's Encrypt certificates for IP addresses

set -e

# Configuration
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@localhost}"
NGINX_CONFIG="/etc/nginx/sites-available/openclaw.conf"
CERT_DIR="/etc/letsencrypt"
LOG_FILE="/var/log/certbot-renewal.log"
IP_ADDRESS=""

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get Elastic IP from AWS metadata (IMDSv2)
get_elastic_ip() {
    log "Retrieving Elastic IP from AWS metadata..."
    
    # Get IMDSv2 token
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    
    # Get public IP
    IP_ADDRESS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        "http://169.254.169.254/latest/meta-data/public-ipv4")
    
    if [ -z "$IP_ADDRESS" ]; then
        log "ERROR: Failed to retrieve Elastic IP from metadata"
        exit 1
    fi
    
    log "Elastic IP: $IP_ADDRESS"
    echo "$IP_ADDRESS"
}

# Check if certificate exists and is valid
check_certificate() {
    local ip=$1
    local cert_path="$CERT_DIR/live/$ip/fullchain.pem"
    
    if [ -f "$cert_path" ]; then
        # Check if certificate expires within 30 days
        if certbot certificates 2>/dev/null | grep -q "$ip"; then
            local expiry=$(certbot certificates 2>/dev/null | grep -A5 "$ip" | grep "Expiry" | awk '{print $2}')
            if [ -n "$expiry" ]; then
                log "Certificate found, expires: $expiry"
                return 0
            fi
        fi
    fi
    
    log "Certificate not found or expired for IP: $ip"
    return 1
}

# Request new certificate using standalone mode
request_certificate() {
    local ip=$1
    
    log "Requesting new Let's Encrypt certificate for IP: $ip"
    
    # Stop Nginx temporarily to free port 80
    log "Stopping Nginx for certificate validation..."
    systemctl stop nginx || true
    
    # Request certificate using standalone mode
    certbot certonly \
        --standalone \
        --agree-tos \
        --no-eff-email \
        --email "$CERTBOT_EMAIL" \
        --preferred-challenges http \
        --domains "$ip" \
        --non-interactive \
        --keep-until-expiring \
        --rsa-key-size 4096
    
    local cert_result=$?
    
    # Restart Nginx
    log "Starting Nginx..."
    systemctl start nginx
    
    if [ $cert_result -eq 0 ]; then
        log "Certificate successfully obtained for IP: $ip"
        update_nginx_config "$ip"
        return 0
    else
        log "ERROR: Failed to obtain certificate"
        return 1
    fi
}

# Update Nginx configuration with actual IP
update_nginx_config() {
    local ip=$1
    
    log "Updating Nginx configuration for IP: $ip"
    
    # Create sites-available directory if it doesn't exist
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    
    # Replace IP_ADDRESS placeholder in config
    sed -i "s|IP_ADDRESS|$ip|g" "$NGINX_CONFIG"
    
    # Create symlink if it doesn't exist
    if [ ! -L "/etc/nginx/sites-enabled/openclaw.conf" ]; then
        ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/openclaw.conf
    fi
    
    # Test Nginx configuration
    if nginx -t; then
        log "Nginx configuration test passed"
        # Reload Nginx
        systemctl reload nginx
        log "Nginx reloaded successfully"
    else
        log "ERROR: Nginx configuration test failed"
        return 1
    fi
}

# Renew existing certificate
renew_certificate() {
    log "Attempting to renew existing certificates..."
    
    # Stop Nginx temporarily
    systemctl stop nginx || true
    
    # Renew certificates
    certbot renew \
        --non-interactive \
        --quiet \
        --deploy-hook "systemctl start nginx && systemctl reload nginx"
    
    local renew_result=$?
    
    # Ensure Nginx is running
    systemctl start nginx
    
    if [ $renew_result -eq 0 ]; then
        log "Certificate renewal completed successfully"
        return 0
    else
        log "WARNING: Certificate renewal may have issues (exit code: $renew_result)"
        return $renew_result
    fi
}

# Main execution
main() {
    log "=========================================="
    log "Starting Certbot renewal process"
    log "=========================================="
    
    # Get the Elastic IP
    IP_ADDRESS=$(get_elastic_ip)
    
    # Check if certificate exists
    if check_certificate "$IP_ADDRESS"; then
        log "Existing certificate found, attempting renewal..."
        renew_certificate
    else
        log "No existing certificate, requesting new one..."
        request_certificate "$IP_ADDRESS"
    fi
    
    # Verify certificate is working
    log "Verifying HTTPS configuration..."
    if curl -k -s -o /dev/null -w "%{http_code}" "https://$IP_ADDRESS/health" | grep -q "200"; then
        log "HTTPS verification successful"
    else
        log "WARNING: HTTPS verification failed, but service may still be starting"
    fi
    
    log "=========================================="
    log "Certbot renewal process completed"
    log "=========================================="
}

# Run main function
main "$@"
