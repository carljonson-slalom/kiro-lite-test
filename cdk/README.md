# AWS Lean Analytics - CDK Infrastructure

This CDK application deploys the infrastructure for the AWS Lean Analytics platform.

## Architecture

### DataStack
- **S3 Bucket**: Stores CSV datasets and Athena query results
- **Glue Database**: Data catalog for schema discovery  
- **Glue Crawler**: Automated schema discovery and table creation
- **Deploy Status**: Ready for GitHub Actions deployment (Dependencies Fixed)
- **IAM Role**: Permissions for Glue crawler operations
- **EventBridge Rule**: Daily crawler scheduling

### AthenaStack (Depends on DataStack)
- **Athena WorkGroup**: Query execution environment
- **Named Queries**: Predefined analytics queries
- **Result Configuration**: S3 location for query outputs

## Prerequisites

- Node.js 18+ 
- AWS CLI v2 configured
- AWS CDK v2 globally installed: `npm install -g aws-cdk`
- Local AWS credentials (SSO, profile, or environment variables)

## Setup

```bash
# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap aws://699027953523/us-west-2

# Synthesize CloudFormation templates
npm run synth

# Deploy all stacks
npm run deploy

# Or deploy individual stacks
cdk deploy LeanAnalyticsDataStack
cdk deploy LeanAnalyticsAthenaStack
```

## Post-Deployment

1. **Run Glue Crawler manually** (first time):
   ```bash
   aws glue start-crawler --name lean-analytics-crawler --region us-west-2
   ```

2. **Verify tables created**:
   ```bash
   aws glue get-tables --database-name lean_demo_db --region us-west-2
   ```

3. **Check Athena WorkGroup**:
   ```bash
   aws athena get-work-group --work-group lean_demo_wg --region us-west-2
   ```

## Sample Data

The following CSV files are automatically uploaded to S3:
- `datasets/customers.csv` - 50 sample customers
- `datasets/orders.csv` - 200 sample orders
- `datasets/returns.csv` - 30 sample returns

## Outputs

After deployment, the following resources are available:

- **S3 Bucket**: `lean-analytics-699027953523-us-west-2`
- **Glue Database**: `lean_demo_db`
- **Glue Crawler**: `lean-analytics-crawler`
- **Dataset Location**: `s3://lean-analytics-699027953523-us-west-2/datasets/`
- **Results Location**: `s3://lean-analytics-699027953523-us-west-2/athena-results/`

## Cleanup

```bash
# Destroy all stacks
npm run destroy

# Or destroy individual stacks (order matters)
cdk destroy LeanAnalyticsAthenaStack
cdk destroy LeanAnalyticsDataStack
```

## Development

```bash
# Watch for changes
npm run watch

# Run tests
npm test

# Check for CDK issues
cdk doctor
```

## Troubleshooting

### Common Issues

1. **Bootstrap required**: Run `cdk bootstrap` for the target account/region
2. **Permission denied**: Ensure AWS credentials have necessary permissions
3. **Bucket already exists**: Bucket names must be globally unique
4. **Crawler fails**: Check IAM role permissions and S3 path

### Useful Commands

```bash
# List all stacks
cdk list

# Show stack differences
cdk diff

# View synthesized CloudFormation
cdk synth LeanAnalyticsDataStack

# Get stack outputs
aws cloudformation describe-stacks --stack-name LeanAnalyticsDataStack --region us-west-2 --query 'Stacks[0].Outputs'
```