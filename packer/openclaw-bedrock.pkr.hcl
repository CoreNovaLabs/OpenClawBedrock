# OpenClaw Enterprise AMI Build with Packer
# Supports ARM64 (Graviton) instances for cost efficiency

packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# Variables
variable "region" {
  type    = string
  default = "us-west-2"
}

variable "instance_type" {
  type    = string
  default = "c7g.large"
}

variable "ami_name" {
  type    = string
  default = "openclaw-bedrock-{{timestamp}}"
}

variable "aws_profile" {
  type    = string
  default = ""
}

variable "root_volume_size" {
  type    = number
  default = 50
}

variable "openclaw_version" {
  type    = string
  default = "2026.4.27"
}

variable "node_version" {
  type    = string
  default = "20"
}

# Local values
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

# Source definition
source "amazon-ebs" "openclaw-bedrock" {
  ami_name      = var.ami_name
  instance_type = var.instance_type
  region        = var.region
  
  # Ubuntu 24.04 LTS ARM64 (Graviton) - Noble Numbat
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-noble-24.04-arm64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }
  
  # IAM instance profile for Bedrock access (created by CloudFormation)
  # Note: This is only needed during build if accessing AWS APIs
  # For production, the EC2 instance will have its own role
  
  # SSH configuration
  ssh_username = "ubuntu"
  ssh_timeout  = "10m"
  
  # Run tags for cost tracking
  run_tags = {
    Name        = "openclaw-ami-builder"
    Project     = "OpenClawEnterprise"
    Environment = "Build"
  }
  
  # Tags for the resulting AMI
  tags = {
    Name        = "openclaw-bedrock"
    Version     = "1.0.0"
    BaseOS      = "Ubuntu24.04"
    Architecture = "ARM64"
    Project     = "OpenClawEnterprise"
    OpenClawVersion = var.openclaw_version
    BuildDate   = local.timestamp
  }
  
  # Launch block device mappings
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
    iops                  = 3000
    throughput            = 125
  }
  
  # Use IMDSv2 only
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  
  # Enable enhanced networking
  ena_support = true
}

# Build configuration
build {
  sources = ["source.amazon-ebs.openclaw-bedrock"]
  
  # Provisioner: Update system packages
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get dist-upgrade -y",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean"
    ]
  }
  
  # Provisioner: Install essential dependencies
  provisioner "shell" {
    inline = [
      "# Install Docker",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io",
      "sudo systemctl enable docker",
      "",
      "# Add ubuntu user to docker group",
      "sudo usermod -aG docker ubuntu"
    ]
  }
  
  # Provisioner: Install Nginx
  provisioner "shell" {
    inline = [
      "sudo apt-get install -y nginx",
      "sudo systemctl enable nginx"
    ]
  }
  
  # Provisioner: Install Certbot for Let's Encrypt
  provisioner "shell" {
    inline = [
      "sudo apt-get install -y certbot python3-certbot-nginx",
      "sudo mkdir -p /etc/letsencrypt",
      "sudo mkdir -p /var/www/certbot"
    ]
  }
  
  # Provisioner: Install Node.js via NVM
  provisioner "shell" {
    environment_vars = [
      "NVM_DIR=/home/ubuntu/.nvm",
      "NODE_VERSION=${var.node_version}"
    ]
    inline = [
      "# Install NVM",
      "export NVM_DIR=\"/home/ubuntu/.nvm\"",
      "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash",
      "[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"",
      "",
      "# Install Node.js",
      ". \"$NVM_DIR/nvm.sh\"",
      "nvm install ${var.node_version}",
      "nvm use ${var.node_version}",
      "nvm alias default ${var.node_version}",
      "",
      "# Verify installation",
      ". \"$NVM_DIR/nvm.sh\"",
      "node --version",
      "npm --version"
    ]
  }
  
  # Provisioner: Install AWS CLI v2
  provisioner "shell" {
    inline = [
      "curl \"https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip\" -o \"/tmp/awscliv2.zip\"",
      "cd /tmp && unzip -q awscliv2.zip",
      "sudo /tmp/aws/install",
      "rm -rf /tmp/aws /tmp/awscliv2.zip",
      "aws --version"
    ]
  }
  
  # Provisioner: Install SSM Session Manager plugin
  provisioner "shell" {
    inline = [
      "curl \"https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb\" -o \"/tmp/session-manager-plugin.deb\"",
      "sudo dpkg -i /tmp/session-manager-plugin.deb",
      "rm /tmp/session-manager-plugin.deb",
      "session-manager-plugin --version || echo 'SSM plugin installed'"
    ]
  }
  
  # Provisioner: Configure security hardening
  provisioner "shell" {
    inline = [
      "# Disable password authentication",
      "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config",
      "",
      "# Configure unattended upgrades",
      "sudo apt-get install -y unattended-upgrades",
      "sudo dpkg-reconfigure -plow unattended-upgrades",
      "",
      "# Configure fail2ban",
      "sudo apt-get install -y fail2ban",
      "sudo systemctl enable fail2ban"
    ]
  }
  
  # Provisioner: Copy configuration files
  provisioner "file" {
    source      = "files/nginx/openclaw-ssl.conf"
    destination = "/tmp/nginx-configs/openclaw-ssl.conf"
  }
  
  provisioner "file" {
    source      = "files/certbot/renew-cert.sh"
    destination = "/tmp/certbot-scripts/renew-cert.sh"
  }
  
  provisioner "file" {
    source      = "files/userdata/bootstrap.sh"
    destination = "/tmp/userdata-scripts/bootstrap.sh"
  }
  
  provisioner "file" {
    source      = "files/systemd/openclaw.service"
    destination = "/tmp/systemd-services/openclaw.service"
  }
  
  provisioner "file" {
    source      = "files/systemd/litellm.service"
    destination = "/tmp/systemd-services/litellm.service"
  }
  
  # Provisioner: Install and configure configurations
  provisioner "shell" {
    inline = [
      "# Create directories",
      "sudo mkdir -p /etc/nginx/sites-available",
      "sudo mkdir -p /etc/nginx/sites-enabled",
      "sudo mkdir -p /opt/certbot",
      "sudo mkdir -p /opt/openclaw",
      "sudo mkdir -p /opt/litellm",
      "sudo mkdir -p /etc/systemd/system",
      "",
      "# Move Nginx configuration",
      "sudo cp /tmp/nginx-configs/openclaw-ssl.conf /etc/nginx/sites-available/openclaw-ssl.conf",
      "sudo ln -sf /etc/nginx/sites-available/openclaw-ssl.conf /etc/nginx/sites-enabled/openclaw-ssl.conf",
      "sudo rm -f /etc/nginx/sites-enabled/default",
      "",
      "# Move Certbot scripts",
      "sudo cp /tmp/certbot-scripts/renew-cert.sh /opt/certbot/renew-cert.sh",
      "sudo chmod +x /opt/certbot/renew-cert.sh",
      "",
      "# Move UserData scripts",
      "sudo cp /tmp/userdata-scripts/bootstrap.sh /opt/openclaw/bootstrap.sh",
      "sudo chmod +x /opt/openclaw/bootstrap.sh",
      "",
      "# Cleanup temp files",
      "sudo rm -rf /tmp/nginx-configs /tmp/certbot-scripts /tmp/userdata-scripts /tmp/systemd-services"
    ]
  }
  
  # Provisioner: Configure systemd services
  provisioner "shell" {
    inline = [
      "# Create OpenClaw systemd service template",
      "sudo tee /etc/systemd/system/openclaw.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=OpenClaw AI Agent Service",
      "After=network.target docker.service",
      "Requires=docker.service",
      "",
      "[Service]",
      "Type=simple",
      "Restart=always",
      "RestartSec=10",
      "ExecStartPre=/usr/bin/docker pull ghcr.io/openclaw/openclaw:latest",
      "ExecStart=/usr/bin/docker run --rm --name openclaw \\",
      "  -p 18789:18789 \\",
      "  -v /var/lib/openclaw:/app/workspace \\",
      "  -e OPENCLAW_MODEL=${OPENCLAW_MODEL:-global.amazon.nova-2-lite-v1:0} \\",
      "  -e OPENCLAW_SANDBOX_MODE=non-main \\",
      "  ghcr.io/openclaw/openclaw:latest",
      "ExecStop=/usr/bin/docker stop openclaw",
      "",
      "# Memory-based restart trigger",
      "MemoryHigh=80%",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "",
      "# Create LiteLLM systemd service template",
      "sudo tee /etc/systemd/system/litellm.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=LiteLLM Proxy Service",
      "After=network.target docker.service",
      "Requires=docker.service",
      "",
      "[Service]",
      "Type=simple",
      "Restart=always",
      "RestartSec=10",
      "ExecStartPre=/usr/bin/docker pull ghcr.io/berriai/litellm:main-latest",
      "ExecStart=/usr/bin/docker run --rm --name litellm \\",
      "  -p 4000:4000 \\",
      "  -v /etc/litellm:/app/config \\",
      "  ghcr.io/berriai/litellm:main-latest \\",
      "  --config /app/config/config.yaml",
      "ExecStop=/usr/bin/docker stop litellm",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "",
      "# Create certificate renewal timer",
      "sudo tee /etc/systemd/system/certbot-renewal.timer > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Run certbot renewal twice daily",
      "",
      "[Timer]",
      "OnCalendar=*-*-* 03:00:00",
      "OnCalendar=*-*-* 15:00:00",
      "RandomizedDelaySec=1h",
      "Persistent=true",
      "",
      "[Install]",
      "WantedBy=timers.target",
      "EOF",
      "",
      "# Create certificate renewal service",
      "sudo tee /etc/systemd/system/certbot-renewal.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Renew Let's Encrypt certificate",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/opt/certbot/renew-cert.sh",
      "EOF",
      "",
      "# Enable services (but don't start yet - will be started by UserData)",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable certbot-renewal.timer"
    ]
  }
  
  # Provisioner: Create LiteLLM config directory
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/litellm",
      "sudo mkdir -p /var/lib/openclaw"
    ]
  }
  
  # Provisioner: Final cleanup
  provisioner "shell" {
    inline = [
      "# Clean up apt cache",
      "sudo apt-get clean",
      "sudo rm -rf /var/cache/apt/archives/*",
      "",
      "# Remove Packer logs",
      "sudo rm -f /var/log/packer-*.log",
      "",
      "# Remove shell history",
      "sudo rm -f /home/ubuntu/.bash_history",
      "sudo truncate -s 0 /home/ubuntu/.bash_history",
      "",
      "# Remove SSH host keys (will be regenerated on first boot)",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "",
      "# Clear cloud-init data",
      "sudo cloud-init clean --logs"
    ]
  }
}
