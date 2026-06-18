# GitHub Actions Setup Guide for OpenClaw Enterprise

This guide explains how to configure GitHub Actions to automatically build OpenClaw AMIs.

## Prerequisites

1. **AWS Account** with permissions to create EC2 AMIs
2. **GitHub Repository** with admin access
3. **OIDC Identity Provider** configured in AWS (recommended) OR IAM User credentials

## Option 1: OIDC Authentication (Recommended - No Long-lived Keys)

### Step 1: Create IAM OIDC Identity Provider in AWS

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Step 2: Create IAM Role for GitHub Actions

Create a trust policy file `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<YOUR_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO>:*"
        }
      }
    }
  ]
}
```

Create the IAM role:

```bash
aws iam create-role \
  --role-name GitHubActionsOpenClawRole \
  --assume-role-policy-document file://trust-policy.json
```

### Step 3: Attach Permissions Policy

Create a permissions policy `permissions-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeImages",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:CreateImage",
        "ec2:CopyImage",
        "ec2:DeregisterImage",
        "ec2:DeleteSnapshot",
        "ec2:DescribeSnapshots",
        "ec2:DescribeInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:GetConsoleOutput",
        "iam:PassRole",
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:GetRole",
        "iam:TagRole",
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:DeleteParameter",
        "s3:CreateBucket",
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "cloudformation:CreateStack",
        "cloudformation:UpdateStack",
        "cloudformation:DeleteStack",
        "cloudformation:DescribeStacks"
      ],
      "Resource": "*"
    }
  ]
}
```

Attach the policy:

```bash
aws iam put-role-policy \
  --role-name GitHubActionsOpenClawRole \
  --policy-name OpenClawBuildPolicy \
  --policy-document file://permissions-policy.json
```

### Step 4: Add Role ARN to GitHub Secrets

In your GitHub repository, go to **Settings > Secrets and variables > Actions** and add:

- **Name**: `AWS_ROLE_ARN`
- **Value**: `arn:aws:iam::<YOUR_ACCOUNT_ID>:role/GitHubActionsOpenClawRole`

## Option 2: IAM User Credentials (Legacy - Less Secure)

If you prefer using long-lived IAM user credentials:

### Step 1: Create IAM User

```bash
aws iam create-user --user-name github-actions-openclaw
```

### Step 2: Attach Policies

Attach the following managed policies or create a custom policy with the permissions listed in Option 1:

```bash
aws iam attach-user-policy \
  --user-name github-actions-openclaw \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

### Step 3: Create Access Keys

```bash
aws iam create-access-key --user-name github-actions-openclaw
```

Save the `AccessKeyId` and `SecretAccessKey`.

### Step 4: Add to GitHub Secrets

In your GitHub repository, go to **Settings > Secrets and variables > Actions** and add:

- **Name**: `AWS_ACCESS_KEY_ID`
- **Value**: `<Your Access Key ID>`

- **Name**: `AWS_SECRET_ACCESS_KEY`
- **Value**: `<Your Secret Access Key>`

## Usage

### Automatic Trigger

The workflow automatically runs when you push to the `main` branch with changes in:
- `packer/**` directory
- `.github/workflows/build-ami.yaml`

### Manual Trigger

1. Go to **Actions** tab in your GitHub repository
2. Select **Build OpenClaw AMI** workflow
3. Click **Run workflow**
4. Choose the AWS Region (default: `us-west-2`)
5. Click **Run workflow**

## Output

After successful completion:
- AMI ID is displayed in the workflow logs
- AMI is tagged with:
  - `Name`: `openclaw-enterprise-<commit-sha>`
  - `Project`: `OpenClaw-Enterprise`
  - `Version`: `2026.4.27`
  - `BuiltBy`: `Packer`

## Next Steps

1. Copy the AMI ID from the workflow output
2. Update `cloudformation/main.yaml` with the new AMI ID
3. Deploy the CloudFormation stack

## Security Best Practices

✅ **Use OIDC** instead of long-lived credentials  
✅ **Limit permissions** to only what's needed  
✅ **Enable MFA** on AWS accounts  
✅ **Review workflow runs** regularly  
✅ **Use private repositories** for sensitive infrastructure code  
✅ **Rotate credentials** periodically (if using IAM users)  

## Troubleshooting

### Common Errors

**"Not authorized to perform sts:AssumeRoleWithWebIdentity"**
- Check that the OIDC provider is correctly configured
- Verify the trust policy matches your repository name
- Ensure the role ARN in GitHub Secrets is correct

**"Packer build failed: Access denied"**
- Verify IAM permissions include all required EC2 actions
- Check that the region in the workflow matches your AWS setup

**"AMI not found"**
- Ensure the Packer build completed successfully
- Check AWS Console > EC2 > AMIs for the new AMI
- Verify the region is correct
