# Packer variables for OpenClaw Bedrock AMI
# Usage: packer build -var-file=variables.pkrvars.hcl openclaw-bedrock.pkr.hcl

region           = "us-west-2"
instance_type    = "c7g.large"
root_volume_size = 50
openclaw_version = "2026.4.27"
node_version     = "20"
