#!/bin/bash
# Upload Packer-built assets to S3 for CloudFormation UserData access

set -e

S3_BUCKET=${1:-""}
AWS_REGION=${2:-"us-east-1"}

if [ -z "$S3_BUCKET" ]; then
    echo "Usage: $0 <s3-bucket> [region]"
    exit 1
fi

echo "Uploading assets to s3://${S3_BUCKET}/..."

# Create bucket if it doesn't exist
aws s3 mb "s3://${S3_BUCKET}" --region "$AWS_REGION" 2>/dev/null || true

# Upload bootstrap script
aws s3 cp packer/files/userdata/bootstrap.sh \
    "s3://${S3_BUCKET}/packer/files/userdata/bootstrap.sh" \
    --region "$AWS_REGION" \
    --content-type text/x-shellscript

# Upload CloudFormation nested templates (required for nested stacks)
aws s3 sync cloudformation/ \
    "s3://${S3_BUCKET}/cloudformation/" \
    --region "$AWS_REGION" \
    --exclude ".*" \
    --exclude "*.md"

echo "Assets uploaded successfully!"
echo ""
echo "Update CloudFormation templates with your bucket:"
echo "Update CloudFormation parameter AssetsS3Bucket (or default) to: '${S3_BUCKET}'"
echo ""
