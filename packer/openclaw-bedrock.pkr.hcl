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

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "openclaw-bedrock" {
  ami_name      = var.ami_name
  instance_type = var.instance_type
  region        = var.region

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  ssh_username = "ubuntu"
  ssh_timeout  = "10m"

  run_tags = {
    Name        = "openclaw-ami-builder"
    Project     = "OpenClawEnterprise"
    Environment = "Build"
  }

  tags = {
    Name            = "openclaw-bedrock"
    Version         = "1.0.0"
    BaseOS          = "Ubuntu24.04"
    Architecture    = "ARM64"
    Project         = "OpenClawEnterprise"
    OpenClawVersion = var.openclaw_version
    BuildDate       = local.timestamp
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
    iops                  = 3000
    throughput            = 125
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  ena_support = true
}

build {
  sources = ["source.amazon-ebs.openclaw-bedrock"]

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
    ]
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get dist-upgrade -y",
      "sudo apt-get install -y unzip git ca-certificates curl gnupg",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
    ]
    inline = [
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker ubuntu",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
    ]
    inline = [
      "sudo apt-get install -y nginx python3-pip python3-venv fail2ban unattended-upgrades",
      "sudo python3 -m venv /opt/certbot/venv",
      "sudo /opt/certbot/venv/bin/pip install --upgrade pip",
      "sudo /opt/certbot/venv/bin/pip install 'certbot>=5.3'",
      "sudo ln -sf /opt/certbot/venv/bin/certbot /usr/local/bin/certbot",
      "certbot --version",
      "sudo mkdir -p /etc/letsencrypt /var/www/certbot /opt/certbot",
      "sudo systemctl enable fail2ban",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "NVM_DIR=/home/ubuntu/.nvm",
      "NODE_VERSION=${var.node_version}",
    ]
    inline = [
      "export NVM_DIR=\"/home/ubuntu/.nvm\"",
      "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash",
      "[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"",
      ". \"$NVM_DIR/nvm.sh\"",
      "nvm install ${var.node_version}",
      "nvm use ${var.node_version}",
      "nvm alias default ${var.node_version}",
      ". \"$NVM_DIR/nvm.sh\"",
      "node --version",
      "npm --version",
    ]
  }

  provisioner "shell" {
    inline = [
      "curl -fsSL \"https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip\" -o \"/tmp/awscliv2.zip\"",
      "cd /tmp && unzip -q awscliv2.zip",
      "sudo /tmp/aws/install",
      "rm -rf /tmp/aws /tmp/awscliv2.zip",
      "aws --version",
    ]
  }

  provisioner "shell" {
    inline = [
      "curl -fsSL \"https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb\" -o \"/tmp/session-manager-plugin.deb\"",
      "sudo dpkg -i /tmp/session-manager-plugin.deb",
      "rm /tmp/session-manager-plugin.deb",
    ]
  }

  provisioner "shell" {
    inline = [
      "curl -fsSL \"https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb\" -o \"/tmp/amazon-cloudwatch-agent.deb\"",
      "sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb",
      "rm /tmp/amazon-cloudwatch-agent.deb",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config",
    ]
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/nginx-configs /tmp/certbot-scripts /tmp/userdata-scripts /tmp/systemd-services",
    ]
  }

  provisioner "file" {
    source      = "files/nginx/openclaw-ssl.conf"
    destination = "/tmp/nginx-configs/openclaw-ssl.conf"
  }

  provisioner "file" {
    source      = "files/nginx/openclaw-http.conf"
    destination = "/tmp/nginx-configs/openclaw-http.conf"
  }

  provisioner "file" {
    source      = "files/certbot/renew-cert.sh"
    destination = "/tmp/certbot-scripts/renew-cert.sh"
  }

  provisioner "file" {
    source      = "files/certbot/issue-ip-cert.sh"
    destination = "/tmp/certbot-scripts/issue-ip-cert.sh"
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

  provisioner "file" {
    source      = "files/scenarios"
    destination = "/tmp/scenarios"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled",
      "sudo mkdir -p /opt/certbot /opt/openclaw /opt/litellm /etc/systemd/system",
      "sudo cp /tmp/nginx-configs/openclaw-ssl.conf /etc/nginx/sites-available/openclaw-ssl.conf",
      "sudo cp /tmp/nginx-configs/openclaw-http.conf /etc/nginx/sites-available/openclaw-http.conf",
      "sudo ln -sf /etc/nginx/sites-available/openclaw-http.conf /etc/nginx/sites-enabled/openclaw-http.conf",
      "sudo rm -f /etc/nginx/sites-enabled/openclaw-ssl.conf /etc/nginx/sites-enabled/default",
      "sudo cp /tmp/certbot-scripts/renew-cert.sh /opt/certbot/renew-cert.sh",
      "sudo cp /tmp/certbot-scripts/issue-ip-cert.sh /opt/certbot/issue-ip-cert.sh",
      "sudo chmod +x /opt/certbot/renew-cert.sh /opt/certbot/issue-ip-cert.sh",
      "sudo cp /tmp/userdata-scripts/bootstrap.sh /opt/openclaw/bootstrap.sh",
      "sudo chmod +x /opt/openclaw/bootstrap.sh",
      "sudo cp -r /tmp/scenarios /opt/openclaw/scenarios",
      "sudo cp /tmp/systemd-services/openclaw.service /etc/systemd/system/openclaw.service",
      "sudo cp /tmp/systemd-services/litellm.service /etc/systemd/system/litellm.service",
      "sudo mkdir -p /etc/litellm /var/lib/openclaw",
      "sudo rm -rf /tmp/nginx-configs /tmp/certbot-scripts /tmp/userdata-scripts /tmp/systemd-services /tmp/scenarios",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo tee /etc/systemd/system/certbot-renewal.timer > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Renew Let's Encrypt short-lived IP certificate",
      "",
      "[Timer]",
      "OnCalendar=*-*-* 03,09,15,21:00:00",
      "RandomizedDelaySec=30m",
      "Persistent=true",
      "",
      "[Install]",
      "WantedBy=timers.target",
      "EOF",
      "sudo tee /etc/systemd/system/certbot-renewal.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Renew Let's Encrypt short-lived IP certificate",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/opt/certbot/renew-cert.sh",
      "EOF",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable certbot-renewal.timer",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /var/cache/apt/archives/*",
      "sudo rm -f /var/log/packer-*.log",
      "sudo rm -f /home/ubuntu/.bash_history",
      "sudo truncate -s 0 /home/ubuntu/.bash_history",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo cloud-init clean --logs",
    ]
  }

  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
