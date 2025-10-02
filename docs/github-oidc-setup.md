# GitHub Actions OIDC Setup for AWS CDK Deployment

## Overview
This document provides the IAM role and trust policy configuration required for GitHub Actions to deploy AWS CDK infrastructure using OpenID Connect (OIDC) authentication.

## Prerequisites
- AWS Account: `699027953523`
- GitHub Repository: Your repository with the lean analytics CDK code
- AWS CLI with administrative permissions

## IAM Role Creation

### 1. Create IAM OIDC Identity Provider

```bash
# Create OIDC provider for GitHub Actions (one-time setup)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --thumbprint-list 1c58a3a8518e8759bf075b76b750d4f2df264fcd \
  --client-id-list sts.amazonaws.com
```

### 2. Create IAM Role

Create the IAM role with the following trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::699027953523:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:*"
        }
      }
    }
  ]
}
```

**Important**: Replace `YOUR_GITHUB_USERNAME/YOUR_REPO_NAME` with your actual GitHub repository path (e.g., `carl-jonson/kiro-lite-test`).

### 3. Create IAM Policy

The role needs comprehensive permissions for CDK deployment:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CDKBootstrapPermissions",
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "iam:*",
        "s3:*",
        "ssm:*",
        "lambda:*",
        "logs:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "GluePermissions",
      "Effect": "Allow",
      "Action": [
        "glue:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AthenaPermissions",
      "Effect": "Allow",
      "Action": [
        "athena:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EventBridgePermissions",
      "Effect": "Allow",
      "Action": [
        "events:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSPermissions",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Setup Commands

### Option A: AWS CLI Commands

```bash
# 1. Create trust policy file
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::699027953523:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:*"
        }
      }
    }
  ]
}
EOF

# 2. Create IAM role
aws iam create-role \
  --role-name GitHubActionsCDKDeploy \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role for GitHub Actions to deploy CDK infrastructure"

# 3. Attach AWS managed policies
aws iam attach-role-policy \
  --role-name GitHubActionsCDKDeploy \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

# 4. Attach additional IAM policy for role management
aws iam attach-role-policy \
  --role-name GitHubActionsCDKDeploy \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

# 5. Verify role creation
aws iam get-role --role-name GitHubActionsCDKDeploy
```

### Option B: AWS Console Steps

1. **Create OIDC Provider** (if not exists):
   - Go to IAM → Identity providers → Add provider
   - Provider type: OpenID Connect
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. **Create IAM Role**:
   - Go to IAM → Roles → Create role
   - Trusted entity type: Web identity
   - Identity provider: `token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
   - GitHub organization: Your username
   - GitHub repository: Your repo name
   - GitHub branch: `main` (or `*` for all branches)

3. **Attach Policies**:
   - `PowerUserAccess` (for AWS resource management)
   - `IAMFullAccess` (for role and policy management)

## Security Considerations

### Principle of Least Privilege
The current policy provides broad permissions for rapid prototyping. For production use:

1. **Scope down permissions** to only required services:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:CreateBucket",
           "s3:DeleteBucket",
           "glue:CreateDatabase",
           "glue:CreateCrawler",
           "glue:StartCrawler",
           "athena:CreateWorkGroup",
           "athena:CreateNamedQuery"
         ],
         "Resource": "arn:aws:*:us-west-2:699027953523:*"
       }
     ]
   }
   ```

2. **Add resource constraints**:
   ```json
   {
     "StringLike": {
       "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main"
     }
   }
   ```

### Branch Protection
The current trust policy allows all branches (`*`). For production:
- Restrict to specific branches: `repo:owner/repo:ref:refs/heads/main`
- Use environment protection rules in GitHub
- Require manual approval for production deployments

## Validation

After setting up the role, validate the configuration:

```bash
# Test role assumption (from local AWS CLI)
aws sts assume-role \
  --role-arn arn:aws:iam::699027953523:role/GitHubActionsCDKDeploy \
  --role-session-name test-session

# Check role policies
aws iam list-attached-role-policies --role-name GitHubActionsCDKDeploy
```

## Troubleshooting

### Common Issues

1. **"No OpenID Connect provider found"**
   - Ensure OIDC provider is created in the correct AWS account
   - Verify the thumbprints are current

2. **"AssumeRoleWithWebIdentity failed"**
   - Check the repository path in trust policy
   - Verify the subject condition matches your repo
   - Ensure the role has correct permissions

3. **"Access Denied during deployment"**
   - Add missing service permissions to the role
   - Check resource-level constraints
   - Verify CDK bootstrap permissions

### Debug Commands

```bash
# Check OIDC provider
aws iam list-open-id-connect-providers

# Get role details
aws iam get-role --role-name GitHubActionsCDKDeploy

# List attached policies
aws iam list-attached-role-policies --role-name GitHubActionsCDKDeploy

# Test CDK permissions
aws cloudformation list-stacks --region us-west-2
```

## Next Steps

1. ✅ Complete OIDC provider setup
2. ✅ Create and configure IAM role
3. ✅ Update trust policy with your repository
4. 🔄 Test GitHub Actions workflow
5. 🔄 Deploy infrastructure via GitHub Actions
6. 🔄 Validate end-to-end automation

## Resources

- [AWS OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [CDK IAM Permissions](https://docs.aws.amazon.com/cdk/v2/guide/permissions.html)

---

**⚠️ Security Note**: This setup provides broad AWS permissions suitable for development and prototyping. Review and restrict permissions for production environments.