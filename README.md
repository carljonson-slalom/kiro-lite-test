# AWS Lean Analytics Platform

A minimal end-to-end analytics platform using native AWS services with a local web interface. Demonstrates data ingestion, cataloging, querying, and visualization using S3, Glue, Athena, and a Node.js Express frontend.

## 🏗️ Architecture

```
CSV Files → S3 → Glue Crawler → Glue Catalog → Athena → Local UI
```

### Components
- **DataStack**: S3 bucket + Glue database + Crawler + sample data
- **AthenaStack**: WorkGroup + Named queries + result configuration  
- **Local UI**: Express server + HTML dashboard + AWS SDK integration
- **CI/CD**: GitHub Actions + OIDC for automated deployment

## 🎯 Features

✅ **Data Storage**: S3 bucket with sample CSV datasets  
✅ **Data Cataloging**: Automated Glue crawler with daily scheduling  
✅ **Query Engine**: Athena WorkGroup with 3 predefined analytics queries  
✅ **Web Interface**: Local dashboard with query buttons and custom SQL  
✅ **Results Export**: CSV download functionality  
✅ **Security**: OIDC-based CI/CD without static AWS credentials  
✅ **Monitoring**: Query execution statistics and performance metrics  

## 📋 Prerequisites

### Required Software
- **Node.js 18+**: Runtime for CDK and UI server
- **AWS CLI v2**: AWS authentication and management
- **AWS CDK v2**: Infrastructure deployment (`npm install -g aws-cdk`)
- **Git**: Version control and GitHub Actions

### AWS Requirements
- **AWS Account**: 699027953523 (configured for this demo)
- **Region**: us-west-2 (hardcoded in configuration)
- **Credentials**: Local AWS credentials (SSO, profile, or environment variables)
- **Permissions**: CloudFormation, S3, Glue, Athena, IAM (see OIDC setup)

### Verification
```bash
# Check prerequisites
node --version          # Should be 18+
aws --version          # Should be 2.x
cdk --version          # Should be 2.x
aws sts get-caller-identity  # Should show valid AWS credentials
```

## 🚀 Quick Start

### 1. Clone and Setup
```bash
git clone <repository-url>
cd aws-lean-analytics

# Install CDK dependencies
cd cdk
npm install

# Install UI dependencies  
cd ../ui
npm install
cd ..
```

### 2. Deploy Infrastructure
```bash
# Option A: Manual deployment
cd cdk
cdk bootstrap aws://699027953523/us-west-2  # First time only
cdk deploy --all --require-approval never

# Option B: GitHub Actions (recommended)
# See GitHub Actions Setup section below
```

### 3. Initialize Data
```bash
# Run Glue crawler to create tables
aws glue start-crawler --name lean-analytics-crawler --region us-west-2

# Wait for crawler completion (2-3 minutes)
aws glue get-crawler --name lean-analytics-crawler --region us-west-2
```

### 4. Start Local UI
```bash
cd ui
npm start

# Open browser to http://localhost:3000
```

## 🔧 GitHub Actions Setup

### Prerequisites
1. **Fork this repository** to your GitHub account
2. **Create IAM OIDC role** with deployment permissions (see `docs/github-actions-setup.md`)
3. **Configure repository settings** for OIDC authentication

### Quick Setup
1. **Create IAM Role** in AWS Console:
   - Role name: `GitHubActionsCDKDeploy`
   - Trust policy: GitHub OIDC provider
   - Permissions: CloudFormation, S3, Glue, Athena, IAM

2. **Update workflow** in `.github/workflows/deploy.yml`:
   ```yaml
   env:
     AWS_REGION: us-west-2
     AWS_ACCOUNT: 699027953523  # Replace with your account
   ```

3. **Push to main branch** - deployment will trigger automatically

### Detailed Setup
See `docs/github-actions-setup.md` for complete IAM role configuration and trust policies.

## 🎯 Usage

### Web Dashboard
1. Open http://localhost:3000 in your browser
2. Check connection status (green = connected, yellow = checking, red = failed)
3. View quick stats (customer/order/return counts)

### Named Queries
Click any predefined query button:
- **Top Orders**: Highest value orders with customer details
- **Returns by Customer**: Customer return analysis with LEFT JOIN
- **Returned Orders**: Financial impact analysis with INNER JOIN

### Custom SQL
1. Enter SQL in the textarea
2. Available tables: `customers`, `orders`, `returns`
3. Click \"Execute Query\" to run
4. Export results as CSV

### Sample Queries
```sql
-- Customer analysis
SELECT customer_name, COUNT(*) as order_count, SUM(order_total) as total_spent
FROM customers c 
JOIN orders o ON c.customer_id = o.customer_id 
GROUP BY customer_name 
ORDER BY total_spent DESC;

-- Monthly revenue trend
SELECT DATE_FORMAT(order_date, '%Y-%m') as month, 
       SUM(order_total) as revenue,
       COUNT(*) as order_count
FROM orders 
GROUP BY month 
ORDER BY month;

-- Return analysis
SELECT return_reason, 
       COUNT(*) as return_count,
       AVG(refund_amount) as avg_refund,
       SUM(refund_amount) as total_refunds
FROM returns 
GROUP BY return_reason 
ORDER BY return_count DESC;
```

## 📊 Sample Data

The platform includes realistic sample datasets:

### Customers (50 records)
- Customer ID, Name, Email, Registration Date
- Range: CUST-001 to CUST-050
- Timespan: January 2023 to June 2023

### Orders (200 records)  
- Order ID, Customer ID, Date, Total, Status
- Range: ORD-001 to ORD-200
- Order totals: $67.25 to $1,245.50
- Timespan: February 2023 to July 2024

### Returns (30 records)
- Return ID, Order ID, Date, Reason, Refund Amount
- Range: RET-001 to RET-030
- Reasons: defective_product, wrong_size, not_as_described, customer_changed_mind, wrong_color
- 15% return rate (30 returns out of 200 orders)

## 🔍 Testing

### Automated Testing
```bash
# Test CDK deployment
cd cdk
npm run test

# Test API endpoints
cd ui
chmod +x test-api.sh
./test-api.sh

# End-to-end validation
chmod +x scripts/test-e2e.sh
./scripts/test-e2e.sh
```

### Manual Testing
```bash
# 1. Test AWS connectivity
curl http://localhost:3000/api/test-connection

# 2. Test named query
curl -X POST http://localhost:3000/api/query \\
  -H \"Content-Type: application/json\" \\
  -d '{\"queryType\": \"named\", \"namedQueryId\": \"top_orders\"}'

# 3. Test custom query
curl -X POST http://localhost:3000/api/query \\
  -H \"Content-Type: application/json\" \\
  -d '{\"sql\": \"SELECT COUNT(*) FROM customers;\"}'
```

## 🛠️ Troubleshooting

### Common Issues

#### 1. CDK Bootstrap Required
```
Error: Need to perform AWS CDK bootstrap
```
**Solution:**
```bash
cdk bootstrap aws://699027953523/us-west-2
```

#### 2. Tables Not Found
```
Error: Table 'customers' doesn't exist
```
**Solution:**
```bash
# Run Glue crawler
aws glue start-crawler --name lean-analytics-crawler --region us-west-2

# Check crawler status
aws glue get-crawler --name lean-analytics-crawler --region us-west-2

# Verify tables created
aws glue get-tables --database-name lean_demo_db --region us-west-2
```

#### 3. AWS Permissions Denied
```
Error: User/Role doesn't have permission to perform athena:StartQueryExecution
```
**Solution:**
- Ensure IAM user/role has Athena permissions
- Check S3 bucket access for query results
- Verify Glue database permissions

#### 4. UI Server Connection Failed
```
Error: AWS connection failed
```
**Solution:**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Test AWS CLI access
aws athena list-work-groups --region us-west-2

# Check server logs
cd ui && npm start
```

#### 5. GitHub Actions Deployment Failed
```
Error: OIDC role assumption failed
```
**Solution:**
- Verify IAM role exists: `GitHubActionsCDKDeploy`
- Check trust policy includes your repository
- Ensure workflow has `id-token: write` permission
- See `docs/github-actions-setup.md` for detailed setup

### Debug Mode
```bash
# Enable debug logging
export DEBUG=*
cd ui && npm start

# CDK debug
cd cdk
cdk synth --debug
cdk deploy --debug
```

### Log Locations
- **CDK Logs**: CloudFormation console → Stack events
- **Athena Logs**: CloudWatch → Log groups → `/aws/athena/`
- **UI Server Logs**: Console output when running `npm start`
- **GitHub Actions**: Repository → Actions tab

## 🧹 Cleanup

### Complete Cleanup
```bash
# Destroy CDK stacks (order matters)
cd cdk
cdk destroy LeanAnalyticsAthenaStack --force
cdk destroy LeanAnalyticsDataStack --force

# Verify S3 bucket deleted
aws s3api head-bucket --bucket lean-analytics-699027953523-us-west-2 --region us-west-2
# Should return: Not Found

# Optional: Remove CDK bootstrap stack
# cdk destroy CDKToolkit-LeanAnalytics
```

### Partial Cleanup
```bash
# Stop UI server
# Ctrl+C in terminal running npm start

# Clear query results only
aws s3 rm s3://lean-analytics-699027953523-us-west-2/athena-results/ --recursive

# Reset Glue tables (crawler will recreate)
aws glue delete-table --database-name lean_demo_db --name customers
aws glue delete-table --database-name lean_demo_db --name orders  
aws glue delete-table --database-name lean_demo_db --name returns
```

## 📈 Monitoring & Metrics

### CloudWatch Metrics
- **Athena**: Query execution time, data scanned, query failures
- **S3**: Storage usage, request metrics  
- **Glue**: Crawler success/failure, table count

### Cost Estimation
- **S3 Storage**: ~$0.01/month (sample data < 1MB)
- **Athena Queries**: ~$5.00/TB scanned (sample queries < 1MB each)
- **Glue Crawler**: ~$0.44/hour (runs daily for ~1 minute)
- **Total**: < $5/month for development usage

### Performance Baselines
- **Simple COUNT queries**: < 5 seconds
- **JOIN queries**: < 15 seconds  
- **Complex aggregations**: < 30 seconds
- **UI page load**: < 2 seconds
- **CSV export**: < 5 seconds

## 🔒 Security Considerations

### Production Hardening (Not Implemented)
This is a **prototype** with minimal security:

- ❌ **No authentication** on UI server
- ❌ **No API rate limiting** 
- ❌ **No SQL injection protection** (basic validation only)
- ❌ **No VPC isolation**
- ❌ **No encryption in transit** for UI
- ❌ **Broad IAM permissions** for prototype simplicity

### For Production Use
- Add authentication (Cognito, Auth0, etc.)
- Implement API rate limiting and WAF
- Add comprehensive SQL injection protection
- Use VPC for network isolation
- Enable SSL/TLS for UI server
- Implement least-privilege IAM policies
- Add monitoring and alerting
- Enable AWS Config and CloudTrail

## 🚀 Future Enhancements

### Planned Features
- [ ] **Authentication**: Cognito integration
- [ ] **Real-time Updates**: WebSocket for live query results
- [ ] **Query History**: Persistent storage and search
- [ ] **Data Visualization**: Charts and graphs
- [ ] **Multi-environment**: Dev/staging/prod environments
- [ ] **API Gateway**: REST API with versioning
- [ ] **Lambda Functions**: Serverless query processing
- [ ] **Data Pipeline**: Automated ETL with Step Functions

### Scaling Considerations
- **Data Volume**: Current design handles < 100MB efficiently
- **Query Concurrency**: Single-user design, add connection pooling for multi-user
- **Regional Deployment**: Currently us-west-2 only
- **High Availability**: Add multi-AZ deployment for production

## 📚 Additional Documentation

- [`cdk/README.md`](cdk/README.md) - CDK infrastructure details
- [`ui/README.md`](ui/README.md) - UI server documentation  
- [`docs/github-actions-setup.md`](docs/github-actions-setup.md) - Complete OIDC setup guide
- [`docs/architecture.md`](docs/architecture.md) - Detailed architecture documentation
- [`scripts/query-validation.md`](scripts/query-validation.md) - SQL query specifications

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: Create a GitHub issue for bug reports
- **Questions**: Use GitHub Discussions for questions
- **Documentation**: Check the `docs/` folder for detailed guides

---

**Built with ❤️ using AWS CDK, Node.js, and modern web technologies**