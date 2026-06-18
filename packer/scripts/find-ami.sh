#!/bin/bash
# find-ami.sh - Dynamically find the latest Ubuntu 24.04 ARM64 AMI ID
# Usage: ./find-ami.sh [region]

set -euo pipefail

REGION="${1:-us-west-2}"
FILTER_NAME="ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"
FILTER_OWNER="099720109477"  # Canonical

echo "Finding latest Ubuntu 24.04 ARM64 AMI in ${REGION}..."

AMI_ID=$(aws ec2 describe-images \
  --region "${REGION}" \
  --owners "${FILTER_OWNER}" \
  --filters "Name=name,Values=${FILTER_NAME}" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

if [[ -z "${AMI_ID}" || "${AMI_ID}" == "None" ]]; then
  echo "ERROR: No AMI found matching criteria"
  exit 1
fi

echo "Found AMI: ${AMI_ID}"
echo "${AMI_ID}"
