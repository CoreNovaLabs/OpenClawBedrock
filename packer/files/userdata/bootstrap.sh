#!/bin/bash -xe
# OpenClaw Enterprise Bootstrap Script
# Runs on EC2 instance startup via UserData

exec > >(tee /var/log/userdata.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== OpenClaw Enterprise Bootstrap Starting ==="
echo "Timestamp: $(date)"

# ============================================================================
# CONFIGURATION (passed from CloudFormation)
# ============================================================================
OPENCLAW_VERSION=${OPENCLAW_VERSION:-"v2026.4.27"}
OPENCLAW_MODEL=${OPENCLAW_MODEL:-"global.amazon.nova-2-lite-v1:0"}
SCENARIO_PRESET=${SCENARIO_PRESET:-"general"}
ENABLE_SANDBOX=${ENABLE_SANDBOX:-"true"}
GATEWAY_TOKEN=${GATEWAY_TOKEN:-""}
ENABLE_LITELLM=${ENABLE_LITELLM:-"true"}
LITELLM_CACHE_SIZE=${LITELLM_CACHE_SIZE:-"512"}
ENABLE_GUARDRAILS=${ENABLE_GUARDRAILS:-"false"}
GUARDRAIL_ID=${GUARDRAIL_ID:-""}
ENABLE_MONITORING=${ENABLE_MONITORING:-"true"}
ENABLE_BACKUP=${ENABLE_BACKUP:-"true"}
ENABLE_AUTO_UPDATE=${ENABLE_AUTO_UPDATE:-"false"}
NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL:-""}
MONTHLY_BUDGET=${MONTHLY_BUDGET:-"50"}
AWS_REGION=${AWS_REGION:-${REGION:-us-east-1}}
STACK_NAME=${STACK_NAME:-"openclaw-enterprise"}
PUBLIC_IP=${PUBLIC_IP:-""}
ASSETS_S3_BUCKET=${ASSETS_S3_BUCKET:-""}

# Nginx is installed on the AMI but must not start until TLS is configured
systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

retry() {
    local n=0
    local max=5
    local delay=30
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                log "Command failed. Attempt $n/$max:"
                sleep $delay
            else
                error_exit "Command failed after $n attempts: $*"
            fi
        }
    done
}

# ============================================================================
# GET INSTANCE METADATA AND ELASTIC IP
# ============================================================================
log "Retrieving instance metadata..."

# Get IMDSv2 token
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
    -s)

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/instance-id")

# Get Elastic IP (prefer CloudFormation-provided static IP)
if [ -n "$PUBLIC_IP" ]; then
    EIP="$PUBLIC_IP"
    log "Waiting for Elastic IP association: $EIP"
    for i in $(seq 1 30); do
        CURRENT=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
            "http://169.254.169.254/latest/meta-data/public-ipv4" || echo "")
        if [ "$CURRENT" = "$EIP" ]; then
            log "Elastic IP associated after ${i} attempt(s)"
            break
        fi
        sleep 10
    done
else
    EIP=$(aws ec2 describe-addresses \
        --filters "Name=instance-id,Values=$INSTANCE_ID" \
        --query 'Addresses[0].PublicIp' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ "$EIP" = "None" ] || [ -z "$EIP" ]; then
        EIP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
            "http://169.254.169.254/latest/meta-data/public-ipv4")
    fi
fi

log "Instance ID: $INSTANCE_ID"
log "Public IP: $EIP"

# Store IP for certificate
echo "$EIP" > /opt/openclaw/cert_ip.txt

# ============================================================================
# REQUEST LET'S ENCRYPT SHORT-LIVED IP CERTIFICATE (Certbot >= 5.3)
# ============================================================================
log "Provisioning Let's Encrypt short-lived IP certificate for: $EIP"

mkdir -p /var/www/certbot
chown -R www-data:www-data /var/www/certbot 2>/dev/null || chown -R ubuntu:ubuntu /var/www/certbot

# HTTP-only nginx for HTTP-01 challenge (443 block requires existing certs)
ln -sf /etc/nginx/sites-available/openclaw-http.conf /etc/nginx/sites-enabled/openclaw-http.conf
rm -f /etc/nginx/sites-enabled/openclaw-ssl.conf /etc/nginx/sites-enabled/default
nginx -t && systemctl start nginx

if ! /opt/certbot/issue-ip-cert.sh "$EIP"; then
    log "WARNING: IP certificate issuance failed; HTTPS may be unavailable until renewal succeeds"
fi

# Switch to full HTTPS nginx config
log "Enabling HTTPS nginx configuration for IP: $EIP"
sed -i "s|OPENCLAW_IP|$EIP|g" /etc/nginx/sites-available/openclaw-ssl.conf
ln -sf /etc/nginx/sites-available/openclaw-ssl.conf /etc/nginx/sites-enabled/openclaw-ssl.conf
rm -f /etc/nginx/sites-enabled/openclaw-http.conf
nginx -t && systemctl enable nginx && systemctl reload nginx

log "SSL certificate setup completed (short-lived profile, auto-renew via systemd timer)"

# ============================================================================
# SETUP LITELLM PROXY
# ============================================================================
if [ "$ENABLE_LITELLM" == "true" ]; then
    log "Setting up LiteLLM Proxy..."

    mkdir -p /opt/litellm
    chown -R ubuntu:ubuntu /opt/litellm

    # Create LiteLLM configuration
    cat > /opt/litellm/litellm_config.yaml <<EOF
model_list:
  - model_name: ${OPENCLAW_MODEL}
    litellm_params:
      model: bedrock/${OPENCLAW_MODEL}
      aws_region_name: ${AWS_REGION}

  # Fallback models for smart routing
  - model_name: fallback-lite
    litellm_params:
      model: bedrock/global.amazon.nova-2-lite-v1:0
      aws_region_name: ${AWS_REGION}

  - model_name: fallback-sonnet
    litellm_params:
      model: bedrock/anthropic.claude-sonnet-4-20250514-v1:0
      aws_region_name: ${AWS_REGION}

litellm_settings:
  set_verbose: False
  drop_params: True

  # Semantic caching
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    ttl: 3600  # Cache TTL in seconds

  # Cost tracking
  track_cost: true
  max_budget: ${MONTHLY_BUDGET}
  budget_duration: monthly

  fallbacks:
    - "${OPENCLAW_MODEL}":
        - fallback-sonnet
        - fallback-lite

router_settings:
  routing_strategy: simple-shuffle
  timeout: 60
EOF

    # Create LiteLLM Docker Compose
    cat > /opt/litellm/docker-compose.yaml <<EOF
version: '3.8'
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    ports:
      - "4000:4000"
    volumes:
      - ./litellm_config.yaml:/app/config.yaml
    command: --config /app/config.yaml --port 4000
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    depends_on:
      - redis
    restart: unless-stopped
    networks:
      - openclaw-net

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    restart: unless-stopped
    networks:
      - openclaw-net

volumes:
  redis-data:

networks:
  openclaw-net:
    driver: bridge
EOF

    # Create environment file
    cat > /opt/litellm/litellm.env <<EOF
LITELLM_CONFIG=/app/config.yaml
REDIS_HOST=redis
REDIS_PORT=6379
EOF

    chown -R ubuntu:ubuntu /opt/litellm

    # Start LiteLLM
    cd /opt/litellm
    sudo -u ubuntu docker compose up -d

    log "LiteLLM Proxy started on port 4000"
fi

# ============================================================================
# SETUP OPENCLAW
# ============================================================================
log "Setting up OpenClaw version $OPENCLAW_VERSION..."

cd /opt/openclaw

# Clone OpenClaw repository
if [ ! -d "/opt/openclaw/openclaw" ]; then
    retry git clone https://github.com/openclaw/openclaw.git /opt/openclaw/openclaw
fi

cd /opt/openclaw/openclaw

# Repo may be cloned as root during recovery runs; normalize ownership for git/docker.
chown -R ubuntu:ubuntu /opt/openclaw/openclaw
sudo -u ubuntu git config --global --add safe.directory /opt/openclaw/openclaw

# Checkout specific version (exact tag match; fallback to main on failure)
sudo -u ubuntu git fetch --tags
resolve_openclaw_ref() {
    local version="$1"
    if sudo -u ubuntu git rev-parse "refs/tags/${version}" >/dev/null 2>&1; then
        echo "$version"
        return 0
    fi
    if sudo -u ubuntu git rev-parse "refs/tags/v${version}" >/dev/null 2>&1; then
        echo "v${version}"
        return 0
    fi
    return 1
}

if OPENCLAW_REF=$(resolve_openclaw_ref "$OPENCLAW_VERSION"); then
    sudo -u ubuntu git checkout "$OPENCLAW_REF"
    log "Checked out OpenClaw ref $OPENCLAW_REF"
else
    log "WARNING: Version $OPENCLAW_VERSION not found, using main"
    sudo -u ubuntu git checkout main
fi

# Create OpenClaw environment file
if [ "$ENABLE_LITELLM" = "true" ]; then
    API_BASE="http://litellm:4000/v1"
else
    API_BASE=""
fi

cat > /opt/openclaw/openclaw.env <<EOF
# OpenClaw Configuration
OPENCLAW_MODEL=${OPENCLAW_MODEL}
OPENCLAW_API_BASE=${API_BASE}
OPENCLAW_API_KEY=sk-litellm-proxy

# Gateway
GATEWAY_TOKEN=${GATEWAY_TOKEN}
GATEWAY_PORT=18789

# Sandbox
ENABLE_SANDBOX=${ENABLE_SANDBOX}
SANDBOX_MODE=non-main

# Scenario Preset
SCENARIO_PRESET=${SCENARIO_PRESET}

# Guardrails
ENABLE_GUARDRAILS=${ENABLE_GUARDRAILS}
BEDROCK_GUARDRAIL_ID=${GUARDRAIL_ID}

# AWS
AWS_REGION=${AWS_REGION}

# Monitoring
ENABLE_MONITORING=${ENABLE_MONITORING}
CLOUDWATCH_LOG_GROUP=/openclaw/enterprise
EOF

# Connect OpenClaw gateway to the LiteLLM Docker network (single LiteLLM stack in /opt/litellm)
OPENCLAW_CONFIG_DIR="/var/lib/openclaw/config"
OPENCLAW_WORKSPACE_DIR="/opt/openclaw/openclaw/workspace"
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}"

mkdir -p "$OPENCLAW_CONFIG_DIR" "$OPENCLAW_WORKSPACE_DIR"
chown -R ubuntu:ubuntu "$OPENCLAW_CONFIG_DIR" "$OPENCLAW_WORKSPACE_DIR"

cat > /opt/openclaw/openclaw/.env <<EOF
OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG_DIR}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR}
OPENCLAW_IMAGE=${OPENCLAW_IMAGE}
OPENCLAW_GATEWAY_BIND=lan
LITELLM_API_KEY=sk-litellm-proxy
EOF

if [ "$ENABLE_LITELLM" = "true" ]; then
    cat > /opt/openclaw/openclaw/docker-compose.override.yaml <<EOF
services:
  openclaw-gateway:
    ports:
      - "18789:18789"
    environment:
      OPENCLAW_GATEWAY_TOKEN: ${GATEWAY_TOKEN}
      LITELLM_API_KEY: sk-litellm-proxy
    networks:
      - openclaw-net

networks:
  openclaw-net:
    external: true
    name: litellm_openclaw-net
EOF
else
    cat > /opt/openclaw/openclaw/docker-compose.override.yaml <<EOF
services:
  openclaw-gateway:
    ports:
      - "18789:18789"
    environment:
      OPENCLAW_GATEWAY_TOKEN: ${GATEWAY_TOKEN}
EOF
fi

# Apply scenario preset
if [ -d "/opt/openclaw/scenarios/${SCENARIO_PRESET}" ]; then
    log "Applying scenario preset: ${SCENARIO_PRESET}"
    cp -r /opt/openclaw/scenarios/${SCENARIO_PRESET}/* /opt/openclaw/openclaw/workspace/ 2>/dev/null || true
fi

chown -R ubuntu:ubuntu /opt/openclaw
chown ubuntu:ubuntu /opt/openclaw/openclaw/.env

# Start OpenClaw
cd /opt/openclaw/openclaw
export OPENCLAW_CONFIG_DIR OPENCLAW_WORKSPACE_DIR OPENCLAW_IMAGE

sudo -u ubuntu docker compose pull openclaw-gateway

if [ "$ENABLE_LITELLM" = "true" ]; then
    sudo -u ubuntu docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
        dist/index.js onboard --mode local --no-install-daemon --non-interactive \
        --auth-choice litellm-api-key \
        --litellm-api-key sk-litellm-proxy \
        --custom-base-url "http://litellm:4000/v1" || \
        log "WARNING: OpenClaw onboard returned non-zero; continuing if config exists"
fi

ALLOWED_ORIGINS="[\"https://${EIP}\",\"http://${EIP}\",\"http://127.0.0.1:18789\",\"http://localhost:18789\"]"
sudo -u ubuntu docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
    dist/index.js config set --batch-json "[{\"path\":\"gateway.mode\",\"value\":\"local\"},{\"path\":\"gateway.bind\",\"value\":\"lan\"},{\"path\":\"gateway.controlUi.allowedOrigins\",\"value\":${ALLOWED_ORIGINS}}]" \
    >/dev/null || log "WARNING: gateway config set failed"

sudo -u ubuntu docker compose up -d openclaw-gateway

log "OpenClaw started"

# ============================================================================
# SETUP CLOUDWATCH AGENT (if monitoring enabled)
# ============================================================================
if [ "$ENABLE_MONITORING" == "true" ]; then
    log "Configuring CloudWatch Agent..."

    cat > /opt/aws/amazon-cloudwatch-agent/bin/config.json <<EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
    },
    "metrics": {
        "append_dimensions": {
            "InstanceId": "${INSTANCE_ID}"
        },
        "metrics_collected": {
            "mem": {
                "measurement": ["mem_used_percent", "mem_available_percent"],
                "metrics_collection_interval": 60
            },
            "cpu": {
                "resources": ["cpu0", "cpu1"],
                "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "resources": ["/", "/mnt"],
                "measurement": ["used_percent"],
                "metrics_collection_interval": 300
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/openclaw/*.log",
                        "log_group_name": "/openclaw/enterprise",
                        "log_stream_name": "{instance_id}/openclaw"
                    },
                    {
                        "file_path": "/var/log/nginx/openclaw_*.log",
                        "log_group_name": "/openclaw/enterprise",
                        "log_stream_name": "{instance_id}/nginx"
                    }
                ]
            }
        }
    }
}
EOF

    # Start CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json \
        -s

    log "CloudWatch Agent configured"
fi

# ============================================================================
# CERTIFICATE RENEWAL (managed by systemd certbot-renewal.timer, twice daily)
# ============================================================================
log "Certificate auto-renewal: systemd timer certbot-renewal.timer (4x daily: 03/09/15/21 UTC)"

# ============================================================================
# FINAL STATUS
# ============================================================================
log "=== OpenClaw Enterprise Bootstrap Completed ==="
log ""
log "Access Information:"
log "  HTTPS URL: https://${EIP}"
log "  Instance ID: ${INSTANCE_ID}"
log "  Region: ${AWS_REGION}"
log ""
log "Services Status:"
log "  Nginx: $(systemctl is-active nginx)"
log "  OpenClaw: $(docker ps --filter 'name=gateway' --format '{{.Status}}')"
log "  LiteLLM: $(docker ps --filter 'name=litellm' --format '{{.Status}}')"
log ""
log "Next Steps:"
log "  1. Access https://${EIP} in your browser"
log "  2. Use SSM Session Manager for secure access: aws ssm start-session --target ${INSTANCE_ID}"
log "  3. Check logs: journalctl -u openclaw -f"
log ""

# Signal success to CloudFormation
exit 0
