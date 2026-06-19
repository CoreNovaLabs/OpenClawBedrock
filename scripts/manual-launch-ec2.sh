#!/bin/bash
# Launch OpenClaw Enterprise EC2 manually (without full CloudFormation stack).
# Ensures UserData runs bootstrap.sh with required network and IAM settings.
#
# Prerequisites:
#   - AWS CLI configured
#   - IAM instance profile with Bedrock + SSM (see README_zh.md "手动启动 AMI")
#
# Usage:
#   ./scripts/manual-launch-ec2.sh \
#     --gateway-token "your-secret-token" \
#     [--region us-east-1] \
#     [--ami ami-020fc67a29ad1eca3] \
#     [--instance-type c7g.large] \
#     [--subnet-id subnet-xxx] \
#     [--iam-instance-profile OpenClawInstanceProfile] \
#     [--allocate-eip true]

set -euo pipefail

REGION="us-east-1"
AMI="ami-020fc67a29ad1eca3"
INSTANCE_TYPE="c7g.large"
SUBNET_ID=""
IAM_PROFILE=""
GATEWAY_TOKEN=""
ALLOCATE_EIP="true"
SG_NAME="openclaw-manual-sg"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    --ami) AMI="$2"; shift 2 ;;
    --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
    --subnet-id) SUBNET_ID="$2"; shift 2 ;;
    --iam-instance-profile) IAM_PROFILE="$2"; shift 2 ;;
    --gateway-token) GATEWAY_TOKEN="$2"; shift 2 ;;
    --allocate-eip) ALLOCATE_EIP="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$GATEWAY_TOKEN" ]]; then
  GATEWAY_TOKEN="oc-$(openssl rand -hex 16 2>/dev/null || date +%s)"
  echo "Generated GatewayToken: $GATEWAY_TOKEN"
  echo "Save this token — you need it to access the OpenClaw gateway."
fi

if [[ -z "$IAM_PROFILE" ]]; then
  echo "ERROR: --iam-instance-profile is required." >&2
  echo "Create an EC2 instance profile with Bedrock invoke + AmazonSSMManagedInstanceCore." >&2
  echo "Easiest: deploy cloudformation/nested/iam.yaml first, then use profile name from stack output." >&2
  exit 1
fi

if [[ -z "$SUBNET_ID" ]]; then
  echo "Finding a public subnet in default VPC (Graviton-capable AZ)..."
  for az in us-east-1a us-east-1b us-east-1c us-east-1d us-east-1f; do
    candidate=$(aws ec2 describe-subnets \
      --region "$REGION" \
      --filters "Name=default-for-az,Values=true" "Name=availability-zone,Values=$az" \
      --query 'Subnets[0].SubnetId' \
      --output text 2>/dev/null || echo "None")
    if [[ -n "$candidate" && "$candidate" != "None" ]]; then
      SUBNET_ID="$candidate"
      echo "Using subnet $SUBNET_ID in $az"
      break
    fi
  done
  if [[ -z "$SUBNET_ID" ]]; then
    echo "ERROR: No suitable subnet found. Pass --subnet-id for a public subnet with c7g support." >&2
    exit 1
  fi
fi

VPC_ID=$(aws ec2 describe-subnets \
  --region "$REGION" \
  --subnet-ids "$SUBNET_ID" \
  --query 'Subnets[0].VpcId' \
  --output text)

echo "Creating security group (TCP 80 + 443)..."
SG_ID=$(aws ec2 create-security-group \
  --region "$REGION" \
  --group-name "${SG_NAME}-$(date +%s)" \
  --description "OpenClaw manual launch HTTPS" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
  --ip-permissions \
  "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP-ACME}]" \
  "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTPS}]"

PUBLIC_IP=""
EIP_ALLOC=""
if [[ "$ALLOCATE_EIP" == "true" ]]; then
  echo "Allocating Elastic IP..."
  EIP_ALLOC=$(aws ec2 allocate-address --region "$REGION" --domain vpc --query 'AllocationId' --output text)
  PUBLIC_IP=$(aws ec2 describe-addresses --region "$REGION" --allocation-ids "$EIP_ALLOC" \
    --query 'Addresses[0].PublicIp' --output text)
  echo "Elastic IP: $PUBLIC_IP"
fi

USERDATA=$(cat <<EOF
#!/bin/bash -xe
export AWS_REGION=${REGION}
export GATEWAY_TOKEN=${GATEWAY_TOKEN}
export PUBLIC_IP=${PUBLIC_IP}
export OPENCLAW_VERSION=v2026.4.27
export ENABLE_LITELLM=true
export ENABLE_MONITORING=true
export OPENCLAW_MODEL=global.amazon.nova-2-lite-v1:0
export SCENARIO_PRESET=general
export ENABLE_SANDBOX=true
exec /opt/openclaw/bootstrap.sh
EOF
)

echo "Launching instance (ARM64 AMI, bootstrap via UserData)..."
INSTANCE_ID=$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile "Name=${IAM_PROFILE}" \
  --user-data "$USERDATA" \
  --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2" \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3","Encrypted":true}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=openclaw-manual},{Key=Project,Value=OpenClawEnterprise}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"

if [[ -n "$EIP_ALLOC" ]]; then
  echo "Waiting for instance to enter running state..."
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
  aws ec2 associate-address --region "$REGION" \
    --instance-id "$INSTANCE_ID" \
    --allocation-id "$EIP_ALLOC"
  echo "Elastic IP associated."
fi

echo ""
echo "=== Launch complete ==="
echo "Region:        $REGION"
echo "Instance ID:   $INSTANCE_ID"
echo "Gateway Token: $GATEWAY_TOKEN"
if [[ -n "$PUBLIC_IP" ]]; then
  echo "Access URL:    https://${PUBLIC_IP}/"
else
  EPHEMERAL=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  echo "Access URL:    https://${EPHEMERAL}/"
fi
echo ""
echo "Bootstrap takes 10–20 minutes. Monitor progress:"
echo "  aws ssm start-session --target $INSTANCE_ID --region $REGION"
echo "  sudo tail -f /var/log/userdata.log"
