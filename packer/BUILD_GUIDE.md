# OpenClaw Enterprise AMI Build Guide

## Prerequisites

Before building the AMI, ensure you have the following:

1. **AWS CLI** installed and configured:
   ```bash
   aws configure
   ```

2. **Packer** installed (v1.9.0 or later):
   ```bash
   # macOS
   brew install packer
   
   # Linux
   sudo apt-get install -y packer
   
   # Or download from https://www.packer.io/downloads
   ```

3. **AWS Permissions**: Your IAM user/role needs:
   - `ec2:DescribeImages`
   - `ec2:RunInstances`
   - `ec2:CreateImage`
   - `ec2:TerminateInstances`
   - `iam:PassRole` (if using instance profiles)
   - `ssm:DescribeInstanceInformation`

## Quick Start

### Option 1: Using Default Variables

```bash
cd packer
packer init openclaw-bedrock.pkr.hcl
packer build -var-file=variables.pkrvars.hcl openclaw-bedrock.pkr.hcl
```

### Option 2: Override Variables via Command Line

```bash
cd packer
packer init openclaw-bedrock.pkr.hcl
packer build \
  -var 'region=us-east-1' \
  -var 'instance_type=c7g.xlarge' \
  -var 'ami_name=openclaw-bedrock-custom' \
  -var 'openclaw_version=2026.4.27' \
  openclaw-bedrock.pkr.hcl
```

### Option 3: Validate First (Recommended)

```bash
cd packer
packer init openclaw-bedrock.pkr.hcl
packer validate -var-file=variables.pkrvars.hcl openclaw-bedrock.pkr.hcl
packer build -var-file=variables.pkrvars.hcl openclaw-bedrock.pkr.hcl
```

## Build Process

The Packer build will:

1. **Find Source AMI**: Automatically locate the latest Ubuntu 24.04 LTS ARM64 AMI
2. **Launch Builder Instance**: Start a c7g.large EC2 instance
3. **Install Dependencies**:
   - Docker CE
   - Nginx
   - Certbot (Let's Encrypt)
   - Node.js 20 LTS via NVM
   - AWS CLI v2
   - SSM Session Manager plugin
   - Fail2ban
   - Unattended upgrades
4. **Copy Configuration Files**:
   - Nginx SSL configuration
   - Certbot renewal scripts
   - Bootstrap script for UserData
   - Systemd service templates
5. **Configure Services**:
   - OpenClaw systemd service
   - LiteLLM systemd service
   - Certificate renewal timer
6. **Security Hardening**:
   - Disable SSH password authentication
   - Configure unattended security updates
   - Enable fail2ban
   - Remove SSH host keys
7. **Cleanup**: Clear logs, history, and cloud-init data
8. **Create AMI**: Generate the final AMI with tags

Build time: ~15-20 minutes

## Output

After successful build, you'll see:

```text
==> amazon-ebs.openclaw-bedrock: Creating AMI...
    amazon-ebs.openclaw-bedrock: AMI ID: ami-0xxxxxxxxxxxxxxxx
    amazon-ebs.openclaw-bedrock: AMI Name: openclaw-bedrock-20260101120000
    amazon-ebs.openclaw-bedrock: Tags: {
        "Name": "openclaw-bedrock",
        "Version": "1.0.0",
        "BaseOS": "Ubuntu24.04",
        "Architecture": "ARM64",
        "Project": "OpenClawEnterprise",
        "OpenClawVersion": "2026.4.27",
        "BuildDate": "20260101120000"
    }
Build 'amazon-ebs.openclaw-bedrock' finished after 18 minutes 32 seconds.

==> Wait completed after 18 minutes 32 seconds

==> Builds finished. The artifacts of successful builds are:
--> amazon-ebs.openclaw-bedrock: amazon-ebs: AMIs were created:
us-west-2: ami-0xxxxxxxxxxxxxxxx
```

**Important**: Note down the AMI ID (e.g., `ami-0xxxxxxxxxxxxxxxx`) - you'll need it for CloudFormation deployment.

## Post-Build Steps

### 1. Update CloudFormation Template

Edit `cloudformation/main.yaml` and replace the placeholder AMI ID:

```yaml
# Find this line:
AMIId:
  Type: String
  Default: ami-placeholder-us-west-2
  
# Replace with your actual AMI ID:
AMIId:
  Type: String
  Default: ami-0xxxxxxxxxxxxxxxx
```

Or use parameter override during stack creation:

```bash
aws cloudformation create-stack \
  --stack-name openclaw-enterprise \
  --template-body file://cloudformation/main.yaml \
  --parameters ParameterKey=AMIId,ParameterValue=ami-0xxxxxxxxxxxxxxxx \
  ...
```

### 2. Verify AMI

```bash
# List your AMIs
aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=openclaw-bedrock*" \
  --query 'Images[*].[ImageId,Name,CreationDate]' \
  --output table

# Check AMI details
aws ec2 describe-images \
  --image-ids ami-0xxxxxxxxxxxxxxxx \
  --query 'Images[0].{ID:ImageId,Name:Name,State:State,Arch:Architecture}'
```

### 3. Test Launch (Optional)

```bash
# Launch a test instance
aws ec2 run-instances \
  --image-id ami-0xxxxxxxxxxxxxxxx \
  --instance-type c7g.large \
  --key-name your-key-pair \
  --security-group-ids sg-xxxxxxxx \
  --subnet-id subnet-xxxxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=openclaw-test}]'

# Connect via SSM
aws ssm start-session --target i-xxxxxxxx
```

## Troubleshooting

### Error: "No AMI found matching criteria"

Ensure you have network connectivity and correct region:
```bash
aws ec2 describe-images \
  --region us-west-2 \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-noble-24.04-arm64-server-*"
```

### Error: "Access Denied" on SSM Plugin Download

Use the regional S3 endpoint:
```bash
# Edit packer/openclaw-bedrock.pkr.hcl
# Replace the S3 URL with regional endpoint
```

### Build Hangs at "Waiting for SSH"

Check security group rules in your AWS account. The builder needs inbound SSH (port 22) from your IP.

### Out of Disk Space

Increase the root volume size in `variables.pkrvars.hcl`:
```hcl
root_volume_size = 60  # GB
```

## Cost Estimation

Building the AMI incurs minimal costs:
- **EC2 Instance**: c7g.large @ $0.072/hour × 0.5 hours = ~$0.04 per build
- **EBS Volume**: 50GB gp3 @ $0.08/GB-month × 0.02 months = ~$0.08
- **Total per build**: ~$0.12

## Automation with GitHub Actions

See `.github/workflows/build-ami.yaml` for automated AMI building on code push.

## Next Steps

After building the AMI, proceed to deploy with CloudFormation:

```bash
cd ..
./scripts/deploy.sh
```

Or manually:
```bash
aws cloudformation create-stack \
  --stack-name openclaw-enterprise \
  --template-body file://cloudformation/main.yaml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-west-2
```

For detailed deployment instructions, see [README.md](../README.md).
