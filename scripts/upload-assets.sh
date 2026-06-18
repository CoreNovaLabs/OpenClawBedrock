#!/bin/bash
# Upload Packer-built assets to S3 for CloudFormation UserData access

set -e

S3_BUCKET=${1:-""}
AWS_REGION=${2:-"us-west-2"}

if [ -z "$S3_BUCKET" ]; then
    echo "Usage: $0 <s3-bucket> [region]"
    exit 1
fi

echo "Uploading assets to s3://${S3_BUCKET}/..."

# Create directory structure in S3
aws s3 mb "s3://${S3_BUCKET}" --region $AWS_REGION 2>/dev/null || true

# Upload bootstrap script
aws s3 cp packer/files/userdata/bootstrap.sh \
    "s3://${S3_BUCKET}/packer/files/userdata/bootstrap.sh" \
    --region $AWS_REGION \
    --acl bucket-owner-full-control

# Set correct permissions
aws s3 cp packer/files/userdata/bootstrap.sh \
    "s3://${S3_BUCKET}/packer/files/userdata/bootstrap.sh" \
    --region $AWS_REGION \
    --metadata-directive REPLACE \
    --cache-control max-age=0,no-cache,no-store,must-revalidate \
    --content-type text/x-shellscript

echo "Assets uploaded successfully!"
echo ""
echo "Update CloudFormation templates with your bucket:"
echo "  - Replace 'REPLACE-WITH-YOUR-BUCKET' with '${S3_BUCKET}'"
echo ""
