# Packer Variables for OpenClaw Bedrock AMI
# Copy this file to variables.pkrvars.hcl and adjust values as needed

# AWS Configuration
aws_region = "us-west-2"

# AMI Naming
ami_name_prefix    = "openclaw-bedrock"
ami_description    = "OpenClaw Enterprise AI Agent with Bedrock Integration, IP HTTPS, and LiteLLM"
ami_version        = "1.0.0"

# Instance Configuration (for building)
instance_type      = "c7g.large"
root_volume_size   = 50  # GB

# Source AMI (Ubuntu 24.04 LTS ARM64)
# This will be dynamically resolved by the script if set to "auto"
source_ami_filter_name    = "ubuntu/images/hvm-ssd/ubuntu-noble-24.04-arm64-server-*"
source_ami_filter_owner   = "099720109477"  # Canonical

# OpenClaw Configuration
openclaw_version = "2026.4.27"
node_version     = "20"

# Feature Flags
enable_litellm   = true
enable_sandbox   = true
enable_guardrails = false

# Tags
build_timestamp = timestamp()
