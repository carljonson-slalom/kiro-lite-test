#!/bin/bash

# API Endpoint Testing Script for AWS Lean Analytics UI
# Tests all endpoints to ensure proper functionality

set -e

# Configuration
SERVER_URL="http://localhost:3000"
TIMEOUT=30

echo "🧪 AWS Lean Analytics UI - API Testing"
echo "======================================"
echo "Server: $SERVER_URL"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Function to test endpoint
test_endpoint() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local description="$4"
    
    echo "🔍 Testing: $description"
    echo "   $method $endpoint"
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" --max-time $TIMEOUT "$SERVER_URL$endpoint" || echo "ERROR\n000")
    else
        response=$(curl -s -w "\n%{http_code}" --max-time $TIMEOUT \
            -X "$method" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$SERVER_URL$endpoint" || echo "ERROR\n000")
    fi
    
    # Extract body and status code
    body=$(echo "$response" | sed '$d')
    status=$(echo "$response" | tail -n1)
    
    case "$status" in
        "200"|"201")
            echo "   ✅ Success ($status)"
                    echo "   📋 Response: $(echo "$body" | head -c 100)"
            ;;
        "400"|"404"|"500"|"501")
            echo "   ⚠️  Expected error ($status)"
                    echo "   📋 Error: $(echo "$body" | head -c 100)"
            ;;
        "000")
            echo "   ❌ Connection failed (server not running?)"
            return 1
            ;;
        *)
            echo "   ❓ Unexpected status: $status"
            echo "   📋 Response: $body"
            ;;
    esac
    echo ""
}

# Check if server is running
echo "🔧 Pre-flight checks"
echo "--------------------"
if ! curl -s --max-time 5 "$SERVER_URL/health" > /dev/null; then
    echo "❌ Server is not running at $SERVER_URL"
    echo "   Please start the server first:"
    echo "   cd ui && npm start"
    echo ""
    exit 1
fi
echo "✅ Server is running"
echo ""

# Test all endpoints
echo "🎯 Testing API Endpoints"
echo "------------------------"

# Basic endpoints
test_endpoint "GET" "/health" "" "Health check"
test_endpoint "GET" "/api/status" "" "API status"
test_endpoint "GET" "/api/named-queries" "" "Named queries list"

# Connection test (may require AWS credentials)
echo "☁️  AWS Integration Tests"
echo "------------------------"
test_endpoint "GET" "/api/test-connection" "" "AWS Athena connectivity test"

# Query endpoints
echo "🔍 Query Endpoint Tests"
echo "----------------------"

# Test custom query
custom_query='{"sql": "SELECT '\''test'\'' as message, 123 as number;"}'
test_endpoint "POST" "/api/query" "$custom_query" "Custom SQL query"

# Test named query
named_query='{"queryType": "named", "namedQueryId": "top_orders"}'
test_endpoint "POST" "/api/query" "$named_query" "Named query execution"

# Test invalid query
invalid_query='{"sql": ""}'
test_endpoint "POST" "/api/query" "$invalid_query" "Invalid query (should fail)"

# Test invalid named query
invalid_named='{"queryType": "named", "namedQueryId": "nonexistent"}'
test_endpoint "POST" "/api/query" "$invalid_named" "Invalid named query (should fail)"

echo "🎉 API Testing Complete!"
echo "========================"
echo ""
echo "📊 Expected Results Summary:"
echo "  ✅ Health and status endpoints should return 200"
echo "  ✅ Named queries list should show 3 queries"
echo "  ☁️  AWS connectivity depends on credentials"
echo "  🔍 Query execution depends on deployed infrastructure"
echo "  ⚠️  Invalid queries should return 400 errors"
echo ""
echo "🔗 Manual Testing URLs:"
echo "  • Health: $SERVER_URL/health"
echo "  • Status: $SERVER_URL/api/status"
echo "  • UI: $SERVER_URL"
echo ""
echo "💡 Next Steps:"
echo "  1. Ensure AWS credentials are configured"
echo "  2. Deploy CDK infrastructure (DataStack + AthenaStack)"
echo "  3. Run Glue crawler to create tables"
echo "  4. Test queries with real data"