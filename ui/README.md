# AWS Lean Analytics - UI Server

Local Node.js Express server providing a web interface for AWS Athena analytics queries.

## Features

- **Express Server**: Lightweight web server with security middleware
- **AWS SDK v3**: Modern Athena client integration
- **Named Queries**: 3 predefined analytics queries
- **Custom SQL**: Execute arbitrary SQL against Athena
- **Real-time Results**: Formatted query results with execution statistics
- **Error Handling**: Comprehensive error handling and validation

## Prerequisites

- Node.js 18+
- AWS CLI v2 configured with credentials
- Deployed CDK infrastructure (DataStack + AthenaStack)
- Glue crawler executed to create tables

## Setup

```bash
# Install dependencies
npm install

# Start development server
npm start

# Or with nodemon for auto-reload
npm run dev
```

## Environment Variables

```bash
# Optional - defaults provided
export AWS_REGION=us-west-2
export AWS_ACCOUNT=699027953523
export ATHENA_DATABASE=lean_demo_db
export ATHENA_WORKGROUP=lean_demo_wg
export PORT=3000
```

## API Endpoints

### Health & Status
- `GET /health` - Server health check
- `GET /api/status` - Service status and configuration
- `GET /api/test-connection` - Test AWS Athena connectivity

### Query Execution
- `POST /api/query` - Execute SQL queries
- `GET /api/named-queries` - List available named queries

### Query Request Format

#### Custom SQL Query
```json
{
  "sql": "SELECT COUNT(*) FROM customers;",
  "queryType": "custom"
}
```

#### Named Query
```json
{
  "queryType": "named",
  "namedQueryId": "top_orders"
}
```

### Response Format
```json
{
  "success": true,
  "data": {
    "headers": [
      {"name": "order_id", "type": "varchar"},
      {"name": "order_total", "type": "double"}
    ],
    "rows": [
      ["ORD-061", "1245.50"],
      ["ORD-064", "892.75"]
    ],
    "rowCount": 2,
    "executionStats": {
      "queryExecutionId": "abc123",
      "executionTimeMs": 1500,
      "dataScannedBytes": 1024
    }
  },
  "metadata": {
    "queryType": "named:top_orders",
    "executionTimeMs": 2500,
    "timestamp": "2025-10-02T10:30:00.000Z"
  }
}
```

## Named Queries

### 1. Top Orders (`top_orders`)
Shows the 10 highest value orders with customer information.

### 2. Returns by Customer (`returns_by_customer`)
Shows customers and their return information (customers with returns only).

### 3. Returned Orders (`returned_orders`)
Shows orders that have been returned with financial analysis.

## Testing

```bash
# Test all API endpoints
chmod +x test-api.sh
./test-api.sh

# Manual testing with curl
curl -X POST http://localhost:3000/api/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT COUNT(*) FROM customers;"}'

curl -X POST http://localhost:3000/api/query \
  -H "Content-Type: application/json" \
  -d '{"queryType": "named", "namedQueryId": "top_orders"}'
```

## Security Features

- **Helmet.js**: Security headers and CSP
- **CORS**: Configured for localhost development
- **Query Validation**: Basic SQL injection protection
- **Input Limits**: Query size and timeout restrictions
- **Error Sanitization**: Production vs development error details

## Troubleshooting

### Common Issues

1. **AWS Credentials Not Found**
   ```bash
   aws configure list
   aws sts get-caller-identity
   ```

2. **Athena Permissions Denied**
   - Ensure IAM user/role has Athena permissions
   - Check S3 bucket access for query results

3. **Tables Not Found**
   ```bash
   aws glue get-tables --database-name lean_demo_db --region us-west-2
   aws glue start-crawler --name lean-analytics-crawler --region us-west-2
   ```

4. **Query Timeout**
   - Check Athena query execution in AWS console
   - Verify data exists in S3 datasets folder

### Development

```bash
# Watch for changes
npm run dev

# Debug mode
DEBUG=* npm start

# Check server logs
tail -f server.log
```

## File Structure

```
ui/
├── package.json       # Dependencies and scripts
├── server.js         # Express server with Athena integration
├── test-api.sh       # API testing script
├── .gitignore        # Node.js ignore patterns
└── public/
    └── index.html    # Frontend interface (UI-3)
```

## Next Steps

1. **Deploy Infrastructure**: Ensure CDK stacks are deployed
2. **Run Crawler**: Execute Glue crawler to create tables
3. **Test Connectivity**: Use `/api/test-connection` endpoint
4. **Frontend Interface**: Implement UI-3 for web interface