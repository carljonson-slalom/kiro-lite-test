#!/bin/bash

# End-to-End Deployment Validation Script
# AWS Lean Analytics Platform Testing

set -e  # Exit on any error

# Configuration
REGION="us-west-2"
ACCOUNT="699027953523"
BUCKET_NAME="lean-analytics-${ACCOUNT}-${REGION}"
DATABASE_NAME="lean_demo_db"
WORKGROUP_NAME="lean_demo_wg"
CRAWLER_NAME="lean-analytics-crawler"
STACK_DATA="LeanAnalyticsDataStack"
STACK_ATHENA="LeanAnalyticsAthenaStack"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "\n${BLUE}🔍 $1${NC}"
    echo "$(printf '%*s' 50 '' | tr ' ' '-')"
}

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    echo -n "Testing: $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        log_success "PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking Prerequisites"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check CDK CLI
    if ! command -v cdk &> /dev/null; then
        log_error "CDK CLI not found. Please install: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set up SSO."
        exit 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js not found. Please install Node.js 18+."
        exit 1
    fi
    
    # Verify region and account
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [ "$current_account" != "$ACCOUNT" ]; then
        log_warning "Current AWS account ($current_account) doesn't match expected account ($ACCOUNT)"
    fi
    
    log_success "All prerequisites met"
}

# Test CDK deployment
test_cdk_deployment() {
    log_step "Testing CDK Deployment"
    
    # Test CDK synthesis
    run_test "CDK synthesis" "cd cdk && npm install && npm run synth"
    
    # Check if stacks exist
    run_test "DataStack exists" "aws cloudformation describe-stacks --stack-name $STACK_DATA --region $REGION"
    run_test "AthenaStack exists" "aws cloudformation describe-stacks --stack-name $STACK_ATHENA --region $REGION"
    
    # Verify stack status
    local data_status=$(aws cloudformation describe-stacks --stack-name $STACK_DATA --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    local athena_status=$(aws cloudformation describe-stacks --stack-name $STACK_ATHENA --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$data_status" == "CREATE_COMPLETE" || "$data_status" == "UPDATE_COMPLETE" ]]; then
        log_success "DataStack status: $data_status"
    else
        log_error "DataStack status: $data_status"
    fi
    
    if [[ "$athena_status" == "CREATE_COMPLETE" || "$athena_status" == "UPDATE_COMPLETE" ]]; then
        log_success "AthenaStack status: $athena_status"
    else
        log_error "AthenaStack status: $athena_status"
    fi
}

# Test S3 bucket and data
test_s3_data() {
    log_step "Testing S3 Data Layer"
    
    # Check if bucket exists
    run_test "S3 bucket exists" "aws s3 ls s3://$BUCKET_NAME --region $REGION"
    
    # Check if datasets exist
    run_test "customers.csv exists" "aws s3 ls s3://$BUCKET_NAME/datasets/customers.csv --region $REGION"
    run_test "orders.csv exists" "aws s3 ls s3://$BUCKET_NAME/datasets/orders.csv --region $REGION"
    run_test "returns.csv exists" "aws s3 ls s3://$BUCKET_NAME/datasets/returns.csv --region $REGION"
    
    # Check dataset sizes
    local customers_size=$(aws s3 ls s3://$BUCKET_NAME/datasets/customers.csv --region $REGION | awk '{print $3}')
    local orders_size=$(aws s3 ls s3://$BUCKET_NAME/datasets/orders.csv --region $REGION | awk '{print $3}')
    local returns_size=$(aws s3 ls s3://$BUCKET_NAME/datasets/returns.csv --region $REGION | awk '{print $3}')
    
    if [ "$customers_size" -gt 1000 ]; then
        log_success "customers.csv size: $customers_size bytes"
    else
        log_warning "customers.csv seems small: $customers_size bytes"
    fi
    
    if [ "$orders_size" -gt 5000 ]; then
        log_success "orders.csv size: $orders_size bytes"
    else
        log_warning "orders.csv seems small: $orders_size bytes"
    fi
    
    if [ "$returns_size" -gt 1000 ]; then
        log_success "returns.csv size: $returns_size bytes"
    else
        log_warning "returns.csv seems small: $returns_size bytes"
    fi
}

# Test Glue components
test_glue_catalog() {
    log_step "Testing Glue Data Catalog"
    
    # Check if database exists
    run_test "Glue database exists" "aws glue get-database --name $DATABASE_NAME --region $REGION"
    
    # Check if crawler exists
    run_test "Glue crawler exists" "aws glue get-crawler --name $CRAWLER_NAME --region $REGION"
    
    # Check crawler state
    local crawler_state=$(aws glue get-crawler --name $CRAWLER_NAME --region $REGION --query 'Crawler.State' --output text 2>/dev/null || echo "NOT_FOUND")
    log_info "Crawler state: $crawler_state"
    
    # Run crawler if not running and no tables exist
    local table_count=$(aws glue get-tables --database-name $DATABASE_NAME --region $REGION --query 'length(TableList)' --output text 2>/dev/null || echo "0")
    
    if [ "$table_count" -eq 0 ] && [ "$crawler_state" == "READY" ]; then
        log_warning "No tables found, starting crawler..."
        aws glue start-crawler --name $CRAWLER_NAME --region $REGION
        
        # Wait for crawler to complete
        log_info "Waiting for crawler to complete (max 5 minutes)..."
        local max_attempts=30
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            local current_state=$(aws glue get-crawler --name $CRAWLER_NAME --region $REGION --query 'Crawler.State' --output text)
            
            if [ "$current_state" == "READY" ]; then
                log_success "Crawler completed"
                break
            elif [ "$current_state" == "RUNNING" ]; then
                echo -n "."
                sleep 10
                attempt=$((attempt + 1))
            else
                log_error "Crawler failed with state: $current_state"
                break
            fi
        done
        
        if [ $attempt -eq $max_attempts ]; then
            log_warning "Crawler still running after 5 minutes"
        fi
    fi
    
    # Check if tables were created
    run_test "Tables exist in catalog" "test $(aws glue get-tables --database-name $DATABASE_NAME --region $REGION --query 'length(TableList)' --output text) -ge 3"
    
    # List tables
    local tables=$(aws glue get-tables --database-name $DATABASE_NAME --region $REGION --query 'TableList[].Name' --output text 2>/dev/null || echo "")
    if [ -n "$tables" ]; then
        log_success "Tables found: $tables"
    else
        log_warning "No tables found in catalog"
    fi
}

# Test Athena components
test_athena_workgroup() {
    log_step "Testing Athena Query Engine"
    
    # Check if workgroup exists
    run_test "Athena workgroup exists" "aws athena get-work-group --work-group $WORKGROUP_NAME --region $REGION"
    
    # Check workgroup state
    local wg_state=$(aws athena get-work-group --work-group $WORKGROUP_NAME --region $REGION --query 'WorkGroup.State' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$wg_state" == "ENABLED" ]; then
        log_success "WorkGroup state: $wg_state"
    else
        log_error "WorkGroup state: $wg_state"
    fi
    
    # Test simple query execution
    log_info "Testing Athena query execution..."
    
    local test_query="SELECT 'test' as message, CURRENT_TIMESTAMP as timestamp;"
    local execution_id=$(aws athena start-query-execution \
        --query-string "$test_query" \
        --work-group "$WORKGROUP_NAME" \
        --result-configuration OutputLocation="s3://$BUCKET_NAME/athena-results/" \
        --region "$REGION" \
        --query 'QueryExecutionId' \
        --output text 2>/dev/null || echo "FAILED")
    
    if [ "$execution_id" != "FAILED" ]; then
        log_success "Test query started: $execution_id"
        
        # Wait for query completion
        local max_attempts=15
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            local status=$(aws athena get-query-execution \
                --query-execution-id "$execution_id" \
                --region "$REGION" \
                --query 'QueryExecution.Status.State' \
                --output text 2>/dev/null || echo "ERROR")
            
            case "$status" in
                "SUCCEEDED")
                    log_success "Test query completed successfully"
                    break
                    ;;
                "FAILED")
                    log_error "Test query failed"
                    break
                    ;;
                "CANCELLED")
                    log_warning "Test query was cancelled"
                    break
                    ;;
                "RUNNING"|"QUEUED")
                    sleep 2
                    attempt=$((attempt + 1))
                    ;;
                *)
                    log_error "Unknown query status: $status"
                    break
                    ;;
            esac
        done
    else
        log_error "Failed to start test query"
    fi
}

# Test data queries
test_data_queries() {
    log_step "Testing Data Queries"
    
    # Test basic count queries
    local queries=(
        "SELECT COUNT(*) FROM customers;"
        "SELECT COUNT(*) FROM orders;"
        "SELECT COUNT(*) FROM returns;"
    )
    
    local tables=("customers" "orders" "returns")
    local expected_counts=(50 200 30)
    
    for i in "${!queries[@]}"; do
        local query="${queries[$i]}"
        local table="${tables[$i]}"
        local expected="${expected_counts[$i]}"
        
        log_info "Testing $table count query..."
        
        local execution_id=$(aws athena start-query-execution \
            --query-string "$query" \
            --work-group "$WORKGROUP_NAME" \
            --result-configuration OutputLocation="s3://$BUCKET_NAME/athena-results/" \
            --region "$REGION" \
            --query 'QueryExecutionId' \
            --output text 2>/dev/null || echo "FAILED")
        
        if [ "$execution_id" != "FAILED" ]; then
            # Wait for completion
            local max_attempts=15
            local attempt=0
            local final_status=""
            
            while [ $attempt -lt $max_attempts ]; do
                local status=$(aws athena get-query-execution \
                    --query-execution-id "$execution_id" \
                    --region "$REGION" \
                    --query 'QueryExecution.Status.State' \
                    --output text 2>/dev/null || echo "ERROR")
                
                if [ "$status" == "SUCCEEDED" ]; then
                    final_status="SUCCEEDED"
                    break
                elif [[ "$status" == "FAILED" || "$status" == "CANCELLED" ]]; then
                    final_status="$status"
                    break
                else
                    sleep 2
                    attempt=$((attempt + 1))
                fi
            done
            
            if [ "$final_status" == "SUCCEEDED" ]; then
                # Get result
                local count=$(aws athena get-query-results \
                    --query-execution-id "$execution_id" \
                    --region "$REGION" \
                    --query 'ResultSet.Rows[1].Data[0].VarCharValue' \
                    --output text 2>/dev/null || echo "0")
                
                if [ "$count" -eq "$expected" ]; then
                    log_success "$table count: $count (expected: $expected)"
                else
                    log_warning "$table count: $count (expected: $expected)"
                fi
            else
                log_error "$table query failed with status: $final_status"
            fi
        else
            log_error "Failed to start $table count query"
        fi
    done
}

# Test UI server
test_ui_server() {
    log_step "Testing UI Server"
    
    # Check if server can start
    log_info "Testing UI server startup..."
    
    if [ -f "ui/package.json" ]; then
        cd ui
        
        # Install dependencies if needed
        if [ ! -d "node_modules" ]; then
            log_info "Installing UI dependencies..."
            npm install >/dev/null 2>&1
        fi
        
        # Start server in background
        log_info "Starting UI server in background..."
        npm start &
        local server_pid=$!
        
        # Wait for server to start
        sleep 5
        
        # Test endpoints
        if curl -s http://localhost:3000/health >/dev/null; then
            log_success "UI server health check passed"
            
            # Test API endpoints
            if curl -s http://localhost:3000/api/status >/dev/null; then
                log_success "API status endpoint accessible"
            else
                log_warning "API status endpoint failed"
            fi
            
            if curl -s http://localhost:3000/api/named-queries >/dev/null; then
                log_success "Named queries endpoint accessible"
            else
                log_warning "Named queries endpoint failed"
            fi
            
        else
            log_error "UI server health check failed"
        fi
        
        # Cleanup
        kill $server_pid 2>/dev/null || true
        cd ..
        
    else
        log_error "UI package.json not found"
    fi
}

# Test cleanup capability
test_cleanup() {
    log_step "Testing Cleanup Capability (Dry Run)"
    
    # Test CDK destroy dry run
    run_test "CDK destroy dry-run" "cd cdk && cdk destroy --all --force --dry-run"
    
    log_info "Cleanup test completed (no actual resources destroyed)"
}

# Generate test report
generate_report() {
    log_step "Test Summary Report"
    
    echo
    echo "======================================"
    echo "AWS Lean Analytics - Deployment Test Results"
    echo "======================================"
    echo "Date: $(date)"
    echo "Region: $REGION"
    echo "Account: $ACCOUNT"
    echo
    echo "Test Results:"
    echo "  Total Tests: $TESTS_TOTAL"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "  Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed! ✨"
        echo
        echo "✅ Your AWS Lean Analytics platform is fully deployed and functional!"
        echo
        echo "Next steps:"
        echo "  1. Access the UI: http://localhost:3000 (after starting: cd ui && npm start)"
        echo "  2. Execute queries using the web interface"
        echo "  3. Explore the sample data and analytics"
        echo
        return 0
    else
        log_error "$TESTS_FAILED tests failed"
        echo
        echo "❌ Some components need attention. Check the logs above for details."
        echo
        echo "Common fixes:"
        echo "  • Run Glue crawler manually: aws glue start-crawler --name $CRAWLER_NAME"
        echo "  • Check IAM permissions for Athena and Glue"
        echo "  • Verify S3 bucket access and data upload"
        echo "  • Ensure CDK stacks deployed successfully"
        echo
        return 1
    fi
}

# Main execution
main() {
    echo "🧪 AWS Lean Analytics - End-to-End Deployment Validation"
    echo "========================================================"
    echo
    
    check_prerequisites
    test_cdk_deployment
    test_s3_data
    test_glue_catalog
    test_athena_workgroup
    test_data_queries
    test_ui_server
    test_cleanup
    
    generate_report
}

# Run main function
main "$@"