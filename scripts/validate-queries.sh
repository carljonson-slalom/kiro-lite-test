#!/bin/bash

# SQL Query Validation Script for AWS Lean Analytics
# Tests the 3 named queries against deployed infrastructure

set -e  # Exit on any error

# Configuration
DATABASE_NAME="lean_demo_db"
WORKGROUP_NAME="lean_demo_wg"
REGION="us-west-2"
RESULTS_BUCKET="lean-analytics-699027953523-us-west-2"

echo "🧪 AWS Lean Analytics - SQL Query Validation"
echo "============================================"
echo "Database: $DATABASE_NAME"
echo "WorkGroup: $WORKGROUP_NAME"
echo "Region: $REGION"
echo ""

# Function to execute query and wait for results
execute_query() {
    local query="$1"
    local description="$2"
    
    echo "🔍 Testing: $description"
    echo "Query: $query"
    
    # Start query execution
    local execution_id=$(aws athena start-query-execution \
        --query-string "$query" \
        --work-group "$WORKGROUP_NAME" \
        --result-configuration OutputLocation="s3://$RESULTS_BUCKET/athena-results/" \
        --region "$REGION" \
        --query 'QueryExecutionId' \
        --output text)
    
    if [ -z "$execution_id" ]; then
        echo "❌ Failed to start query execution"
        return 1
    fi
    
    echo "📋 Execution ID: $execution_id"
    
    # Wait for query completion
    local status=""
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        status=$(aws athena get-query-execution \
            --query-execution-id "$execution_id" \
            --region "$REGION" \
            --query 'QueryExecution.Status.State' \
            --output text)
        
        case "$status" in
            "SUCCEEDED")
                echo "✅ Query completed successfully"
                
                # Get result metadata
                local result_info=$(aws athena get-query-results \
                    --query-execution-id "$execution_id" \
                    --region "$REGION" \
                    --query 'ResultSet.ResultSetMetadata.ColumnInfo[].Name' \
                    --output table)
                
                local row_count=$(aws athena get-query-results \
                    --query-execution-id "$execution_id" \
                    --region "$REGION" \
                    --query 'length(ResultSet.Rows)' \
                    --output text)
                
                echo "📊 Columns returned: $(echo "$result_info" | wc -l) columns"
                echo "📈 Rows returned: $((row_count - 1)) data rows (plus header)"
                echo ""
                return 0
                ;;
            "FAILED")
                local error_message=$(aws athena get-query-execution \
                    --query-execution-id "$execution_id" \
                    --region "$REGION" \
                    --query 'QueryExecution.Status.StateChangeReason' \
                    --output text)
                echo "❌ Query failed: $error_message"
                echo ""
                return 1
                ;;
            "CANCELLED")
                echo "⚠️  Query was cancelled"
                echo ""
                return 1
                ;;
            "RUNNING"|"QUEUED")
                echo "⏳ Query status: $status (attempt $((attempt + 1))/$max_attempts)"
                sleep 2
                ((attempt++))
                ;;
            *)
                echo "❓ Unknown status: $status"
                ((attempt++))
                ;;
        esac
    done
    
    echo "⏰ Query timed out after $max_attempts attempts"
    echo ""
    return 1
}

# Test 1: Validate tables exist
echo "🔧 Pre-flight checks"
echo "--------------------"

echo "📋 Checking if tables exist in database..."
tables=$(aws glue get-tables \
    --database-name "$DATABASE_NAME" \
    --region "$REGION" \
    --query 'TableList[].Name' \
    --output text 2>/dev/null || echo "")

if [ -z "$tables" ]; then
    echo "❌ No tables found in database $DATABASE_NAME"
    echo "   Please run the Glue crawler first:"
    echo "   aws glue start-crawler --name lean-analytics-crawler --region $REGION"
    echo ""
    exit 1
fi

echo "✅ Tables found: $tables"
echo ""

# Test 2: Query 1 - Top 10 orders by order_total
query1="SELECT 
    o.order_id,
    o.customer_id,
    c.customer_name,
    c.email,
    o.order_date,
    o.order_total,
    o.status
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_total DESC
LIMIT 10;"

execute_query "$query1" "Top 10 orders by order_total"

# Test 3: Query 2 - Returns by customer (LEFT JOIN)
query2="SELECT 
    c.customer_id,
    c.customer_name,
    c.email,
    c.registration_date,
    r.return_id,
    r.order_id,
    r.return_date,
    r.return_reason,
    r.refund_amount,
    CASE 
        WHEN r.return_id IS NOT NULL THEN 'Has Returns'
        ELSE 'No Returns'
    END AS return_status
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN returns r ON o.order_id = r.order_id
ORDER BY c.customer_name, r.return_date DESC
LIMIT 20;"

execute_query "$query2" "Returns by customer (LEFT JOIN) - Limited to 20 rows"

# Test 4: Query 3 - Orders that were returned
query3="SELECT 
    o.order_id,
    o.customer_id,
    c.customer_name,
    o.order_date,
    o.order_total,
    o.status AS order_status,
    r.return_id,
    r.return_date,
    r.return_reason,
    r.refund_amount,
    (o.order_total - r.refund_amount) AS net_revenue,
    ROUND((r.refund_amount / o.order_total) * 100, 2) AS return_percentage
FROM orders o
INNER JOIN returns r ON o.order_id = r.order_id
INNER JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_date DESC, r.return_date DESC;"

execute_query "$query3" "Orders that were returned (INNER JOIN)"

# Test 5: Basic validation queries
echo "🔍 Additional validation queries"
echo "-------------------------------"

validation_queries=(
    "SELECT COUNT(*) as customer_count FROM customers;"
    "SELECT COUNT(*) as order_count FROM orders;"
    "SELECT COUNT(*) as return_count FROM returns;"
    "SELECT MIN(order_total) as min_order, MAX(order_total) as max_order FROM orders;"
    "SELECT COUNT(DISTINCT customer_id) as unique_customers FROM orders;"
)

for vq in "${validation_queries[@]}"; do
    execute_query "$vq" "Validation: $vq"
done

echo "🎉 SQL Query Validation Complete!"
echo "================================="
echo ""
echo "📊 Expected Results Summary:"
echo "  • Customers: 50 records"
echo "  • Orders: 200 records"
echo "  • Returns: 30 records"
echo "  • Top order should be ORD-061 (\$1,245.50)"
echo "  • All customers should appear in LEFT JOIN (some with NULL returns)"
echo "  • Only orders with returns should appear in INNER JOIN (30 orders)"
echo ""
echo "🔗 Query results are stored in:"
echo "   s3://$RESULTS_BUCKET/athena-results/"
echo ""
echo "💡 To run individual queries, use the named queries in Athena console:"
echo "   • top_orders_by_total"
echo "   • returns_by_customer" 
echo "   • orders_that_were_returned"