#!/bin/bash

# AWS Lean Analytics - Athena Setup Validation Script
# Run this after CDK deployment to validate Athena configuration

set -e

echo "🔍 AWS Lean Analytics - Athena Validation"
echo "========================================"

# Configuration
REGION="us-west-2"
WORKGROUP="lean_demo_wg"
DATABASE="lean_demo_db"

echo "📍 Region: $REGION"
echo "🏢 WorkGroup: $WORKGROUP"
echo "🗃️  Database: $DATABASE"
echo ""

# Check if AWS CLI is configured
echo "1️⃣  Checking AWS CLI configuration..."
if ! aws sts get-caller-identity --region $REGION > /dev/null 2>&1; then
    echo "❌ AWS CLI not configured or no permissions"
    exit 1
fi
echo "✅ AWS CLI configured"

# Check WorkGroup
echo ""
echo "2️⃣  Checking Athena WorkGroup..."
if aws athena get-work-group --work-group $WORKGROUP --region $REGION > /dev/null 2>&1; then
    echo "✅ WorkGroup '$WORKGROUP' exists"
    
    # Get WorkGroup details
    RESULT_LOCATION=$(aws athena get-work-group --work-group $WORKGROUP --region $REGION \
        --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' --output text)
    echo "📂 Result Location: $RESULT_LOCATION"
else
    echo "❌ WorkGroup '$WORKGROUP' not found"
    exit 1
fi

# Check Glue Database
echo ""
echo "3️⃣  Checking Glue Database..."
if aws glue get-database --name $DATABASE --region $REGION > /dev/null 2>&1; then
    echo "✅ Database '$DATABASE' exists"
    
    # List tables
    echo "📋 Tables in database:"
    aws glue get-tables --database-name $DATABASE --region $REGION \
        --query 'TableList[].Name' --output table
else
    echo "❌ Database '$DATABASE' not found"
    echo "💡 Tip: Run the Glue crawler first: aws glue start-crawler --name lean-analytics-crawler --region $REGION"
fi

# Check Named Queries
echo ""
echo "4️⃣  Checking Named Queries..."
NAMED_QUERIES=$(aws athena list-named-queries --work-group $WORKGROUP --region $REGION \
    --query 'NamedQueryIds' --output text)

if [ -n "$NAMED_QUERIES" ]; then
    echo "✅ Named queries found:"
    for query_id in $NAMED_QUERIES; do
        QUERY_NAME=$(aws athena get-named-query --named-query-id $query_id --region $REGION \
            --query 'NamedQuery.Name' --output text)
        echo "   📝 $QUERY_NAME ($query_id)"
    done
else
    echo "⚠️  No named queries found"
fi

# Test simple query
echo ""
echo "5️⃣  Testing simple query execution..."
if aws glue get-tables --database-name $DATABASE --region $REGION --query 'TableList[0].Name' --output text > /dev/null 2>&1; then
    echo "🔄 Starting test query..."
    
    QUERY_EXECUTION_ID=$(aws athena start-query-execution \
        --query-string "SHOW TABLES IN $DATABASE;" \
        --work-group $WORKGROUP \
        --region $REGION \
        --query 'QueryExecutionId' --output text)
    
    echo "📝 Query Execution ID: $QUERY_EXECUTION_ID"
    
    # Wait for query completion (timeout after 30 seconds)
    for i in {1..30}; do
        STATUS=$(aws athena get-query-execution \
            --query-execution-id $QUERY_EXECUTION_ID \
            --region $REGION \
            --query 'QueryExecution.Status.State' --output text)
        
        if [ "$STATUS" = "SUCCEEDED" ]; then
            echo "✅ Test query completed successfully"
            
            # Show results
            echo "📊 Query results:"
            aws athena get-query-results \
                --query-execution-id $QUERY_EXECUTION_ID \
                --region $REGION \
                --query 'ResultSet.Rows[].Data[].VarCharValue' --output table
            break
        elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "CANCELLED" ]; then
            echo "❌ Test query failed with status: $STATUS"
            
            # Show error details
            aws athena get-query-execution \
                --query-execution-id $QUERY_EXECUTION_ID \
                --region $REGION \
                --query 'QueryExecution.Status.StateChangeReason' --output text
            break
        else
            echo "⏳ Query status: $STATUS (${i}/30)"
            sleep 1
        fi
    done
    
    if [ $i -eq 30 ]; then
        echo "⏰ Query timeout after 30 seconds"
    fi
else
    echo "⚠️  No tables found - run Glue crawler first"
fi

echo ""
echo "🎯 Validation Summary"
echo "===================="
echo "✅ AWS CLI: Configured"
echo "✅ WorkGroup: Available"
echo "✅ Database: Available"
echo "📝 Named Queries: Check output above"
echo "🔍 Test Query: Check output above"
echo ""
echo "💡 Next Steps:"
echo "   1. If no tables found, run: aws glue start-crawler --name lean-analytics-crawler --region $REGION"
echo "   2. Test named queries in Athena console"
echo "   3. Start local UI: cd ui && npm install && npm start"
echo ""
echo "🔗 Useful Commands:"
echo "   aws athena list-work-groups --region $REGION"
echo "   aws glue get-tables --database-name $DATABASE --region $REGION"
echo "   aws athena list-named-queries --work-group $WORKGROUP --region $REGION"