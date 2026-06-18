#!/bin/bash -xe
# OpenClaw Enterprise Bootstrap Script
# Runs on EC2 instance startup via UserData

exec > >(tee /var/log/userdata.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== OpenClaw Enterprise Bootstrap Starting ==="
echo "Timestamp: $(date)"

# ============================================================================
# CONFIGURATION (passed from CloudFormation)
# ============================================================================
OPENCLAW_VERSION=${OPENCLAW_VERSION:-"2026.4.27"}
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
AWS_REGION=${AWS_REGION:-"us-west-2"}
STACK_NAME=${STACK_NAME:-"openclaw-enterprise"}

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

# Get Elastic IP (if assigned)
EIP=$(aws ec2 describe-addresses \
    --filters "Name=instance-id,Values=$INSTANCE_ID" \
    --query 'Addresses[0].PublicIp' \
    --output text \
    --region $AWS_REGION 2>/dev/null || echo "")

if [ "$EIP" == "None" ] || [ -z "$EIP" ]; then
    # Fallback to instance public IP
    EIP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        "http://169.254.169.254/latest/meta-data/public-ipv4")
fi

log "Instance ID: $INSTANCE_ID"
log "Public IP: $EIP"

# Store IP for certificate
echo "$EIP" > /opt/openclaw/cert_ip.txt

# ============================================================================
# CREATE CERTBOT DIRECTORY
# ============================================================================
log "Setting up Certbot directory..."
mkdir -p /var/www/certbot
chown -R ubuntu:ubuntu /var/www/certbot

# ============================================================================
# REQUEST LET'S ENCRYPT CERTIFICATE FOR IP
# ============================================================================
log "Requesting Let's Encrypt certificate for IP: $EIP"

# Standalone mode - temporarily stop Nginx port 80
systemctl stop nginx || true

# Request certificate using HTTP-01 challenge
certbot certonly \
    --standalone \
    --preferred-challenges http \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    -d "$EIP" \
    --logs-dir /var/log/letsencrypt \
    --work-dir /var/lib/letsencrypt \
    --config-dir /etc/letsencrypt || {
    log "WARNING: Certificate request failed. May need manual intervention."
}

# Restart Nginx
systemctl start nginx

# Update Nginx config with actual IP
log "Updating Nginx configuration with IP: $EIP"
sed -i "s|OPENCLAW_IP|$EIP|g" /etc/nginx/sites-available/openclaw-ssl.conf

# Test and reload Nginx
nginx -t && systemctl reload nginx

log "SSL certificate setup completed"

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
    host: localhost
    port: 6379
    ttl: 3600  # Cache TTL in seconds
  
  # Cost tracking
  track_cost: true
  max_budget: ${MONTHLY_BUDGET}
  budget_duration: monthly

router_settings:
  routing_strategy: simple-shuffle-highest-priority-bucket
  fallbacks: [{${OPENCLAW_MODEL}}: ["fallback-sonnet", "fallback-lite"]}]
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
    sudo -u ubuntu docker-compose up -d
    
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

# Checkout specific version
git fetch --tags
if git tag | grep -q "$OPENCLAW_VERSION"; then
    git checkout "$OPENCLAW_VERSION"
    log "Checked out OpenClaw version $OPENCLAW_VERSION"
else
    log "WARNING: Version $OPENCLAW_VERSION not found, using latest"
fi

# Create OpenClaw environment file
cat > /opt/openclaw/openclaw.env <<EOF
# OpenClaw Configuration
OPENCLAW_MODEL=${OPENCLAW_MODEL}
OPENCLAW_API_BASE=http://litellm:4000/v1
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

# Create Docker Compose override for enterprise setup
cat > /opt/openclaw/openclaw/docker-compose.override.yaml <<EOF
version: '3.8'
services:
  gateway:
    ports:
      - "18789:18789"
    environment:
      - GATEWAY_TOKEN=${GATEWAY_TOKEN}
      - ENABLE_SANDBOX=${ENABLE_SANDBOX}
    networks:
      - openclaw-net
    depends_on:
      - litellm-proxy

  litellm-proxy:
    image: ghcr.io/berriai/litellm:main-latest
    ports:
      - "4000:4000"
    environment:
      - AWS_REGION=${AWS_REGION}
    networks:
      - openclaw-net
    restart: unless-stopped

networks:
  openclaw-net:
    external: true
    name: litellm_openclaw-net
EOF

# Apply scenario preset
if [ -d "/opt/openclaw/scenarios/${SCENARIO_PRESET}" ]; then
    log "Applying scenario preset: ${SCENARIO_PRESET}"
    cp -r /opt/openclaw/scenarios/${SCENARIO_PRESET}/* /opt/openclaw/openclaw/workspace/ 2>/dev/null || true
fi

chown -R ubuntu:ubuntu /opt/openclaw

# Start OpenClaw
cd /opt/openclaw/openclaw
sudo -u ubuntu docker-compose pull
sudo -u ubuntu docker-compose up -d

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
# SETUP CERTIFICATE RENEWAL CRON JOB
# ============================================================================
log "Setting up automatic certificate renewal..."

(crontab -l 2>/dev/null; echo "0 3 * * * /opt/openclaw/renew-cert.sh") | crontab -

log "Certificate renewal cron job added (daily at 3 AM)"

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
