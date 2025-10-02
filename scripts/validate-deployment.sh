#!/usr/bin/env bash

# =============================================================================
# Lean Analytics Platform - End-to-End Validation Script
# =============================================================================
# Purpose: Comprehensive testing of deployed AWS infrastructure and local UI
# Usage: ./scripts/validate-deployment.sh [--skip-ui] [--skip-aws] [--verbose]
# Requirements: AWS CLI, Node.js, curl, jq (optional)
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID="699027953523"
BUCKET_NAME="lean-analytics-${AWS_ACCOUNT_ID}-${AWS_REGION}"
DATABASE_NAME="lean_demo_db"
WORKGROUP_NAME="lean_demo_wg"
CRAWLER_NAME="lean-analytics-crawler"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Flags
SKIP_UI=false
SKIP_AWS=false
VERBOSE=false
ERRORS=0
WARNINGS=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-ui)
      SKIP_UI=true
      shift
      ;;
    --skip-aws)
      SKIP_AWS=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--skip-ui] [--skip-aws] [--verbose]"
      echo "  --skip-ui   Skip UI server validation"
      echo "  --skip-aws  Skip AWS infrastructure validation"
      echo "  --verbose   Enable verbose output"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Utility functions
log_info() {
  echo -e "${BLUE}ℹ️  INFO:${NC} $1"
}

log_success() {
  echo -e "${GREEN}✅ SUCCESS:${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠️  WARNING:${NC} $1"
  ((WARNINGS++))
}

log_error() {
  echo -e "${RED}❌ ERROR:${NC} $1"
  ((ERRORS++))
}

log_step() {
  echo -e "${CYAN}🔄 STEP:${NC} $1"
}

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${PURPLE}🔍 DEBUG:${NC} $1"
  fi
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
  log_step "Checking prerequisites..."
  
  local missing_tools=()
  
  if ! command_exists aws; then
    missing_tools+=("aws-cli")
  fi
  
  if ! command_exists node; then
    missing_tools+=("node.js")
  fi
  
  if ! command_exists curl; then
    missing_tools+=("curl")
  fi
  
  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing_tools[*]}"
    log_info "Install missing tools and try again"
    exit 1
  fi
  
  log_success "All prerequisites satisfied"
}

# Validate AWS authentication
check_aws_auth() {
  log_step "Validating AWS authentication..."
  
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS authentication failed"
    log_info "Run 'aws configure' or set AWS credentials"
    return 1
  fi
  
  local account_id
  account_id=$(aws sts get-caller-identity --query Account --output text)
  
  if [[ "$account_id" != "$AWS_ACCOUNT_ID" ]]; then
    log_warning "Connected to account $account_id, expected $AWS_ACCOUNT_ID"
  else
    log_success "Connected to correct AWS account: $account_id"
  fi
  
  local region
  region=$(aws configure get region || echo "")
  if [[ "$region" != "$AWS_REGION" ]]; then
    log_warning "Default region is '$region', tests use '$AWS_REGION'"
  fi
}

# Test S3 bucket and data
test_s3_resources() {
  log_step "Testing S3 bucket and sample data..."
  
  # Check bucket exists
  if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
    log_error "S3 bucket '$BUCKET_NAME' not found"
    return 1
  fi
  
  log_success "S3 bucket exists: $BUCKET_NAME"
  
  # Check sample data files
  local expected_files=("sample-orders.csv" "sample-returns.csv")
  local missing_files=()
  
  for file in "${expected_files[@]}"; do
    if ! aws s3api head-object --bucket "$BUCKET_NAME" --key "data/$file" --region "$AWS_REGION" >/dev/null 2>&1; then
      missing_files+=("$file")
    fi
  done
  
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    log_error "Missing sample data files: ${missing_files[*]}"
    return 1
  fi
  
  log_success "Sample data files uploaded successfully"
  
  # Check file sizes
  for file in "${expected_files[@]}"; do
    local size
    size=$(aws s3api head-object --bucket "$BUCKET_NAME" --key "data/$file" --region "$AWS_REGION" --query ContentLength --output text)
    log_verbose "File $file size: $size bytes"
    
    if [[ $size -lt 100 ]]; then
      log_warning "File $file seems too small ($size bytes)"
    fi
  done
}

# Test Glue database and crawler
test_glue_resources() {
  log_step "Testing Glue database and crawler..."
  
  # Check database exists
  if ! aws glue get-database --name "$DATABASE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "Glue database '$DATABASE_NAME' not found"
    return 1
  fi
  
  log_success "Glue database exists: $DATABASE_NAME"
  
  # Check crawler exists
  if ! aws glue get-crawler --name "$CRAWLER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "Glue crawler '$CRAWLER_NAME' not found"
    return 1
  fi
  
  log_success "Glue crawler exists: $CRAWLER_NAME"
  
  # Check crawler state
  local crawler_state
  crawler_state=$(aws glue get-crawler --name "$CRAWLER_NAME" --region "$AWS_REGION" --query Crawler.State --output text)
  log_verbose "Crawler state: $crawler_state"
  
  if [[ "$crawler_state" == "RUNNING" ]]; then
    log_info "Crawler is currently running..."
    log_info "Waiting for crawler to complete (max 5 minutes)..."
    
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
      sleep 10
      elapsed=$((elapsed + 10))
      
      crawler_state=$(aws glue get-crawler --name "$CRAWLER_NAME" --region "$AWS_REGION" --query Crawler.State --output text)
      
      if [[ "$crawler_state" != "RUNNING" ]]; then
        break
      fi
      
      log_verbose "Still running... ($elapsed/${timeout}s elapsed)"
    done
    
    if [[ "$crawler_state" == "RUNNING" ]]; then
      log_warning "Crawler still running after $timeout seconds"
    fi
  fi
  
  # Check tables created
  local tables
  tables=$(aws glue get-tables --database-name "$DATABASE_NAME" --region "$AWS_REGION" --query 'TableList[].Name' --output text 2>/dev/null || echo "")
  
  if [[ -z "$tables" ]]; then
    log_warning "No tables found in database (crawler may not have run yet)"
    log_info "Try running: aws glue start-crawler --name $CRAWLER_NAME --region $AWS_REGION"
  else
    log_success "Tables found: $tables"
    
    # Validate expected tables
    local expected_tables=("sample_orders" "sample_returns")
    for table in "${expected_tables[@]}"; do
      if [[ "$tables" == *"$table"* ]]; then
        log_verbose "Table '$table' exists"
      else
        log_warning "Expected table '$table' not found"
      fi
    done
  fi
}

# Test Athena WorkGroup and queries
test_athena_resources() {
  log_step "Testing Athena WorkGroup and named queries..."
  
  # Check WorkGroup exists
  if ! aws athena get-work-group --work-group "$WORKGROUP_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "Athena WorkGroup '$WORKGROUP_NAME' not found"
    return 1
  fi
  
  log_success "Athena WorkGroup exists: $WORKGROUP_NAME"
  
  # Check named queries
  local query_ids
  query_ids=$(aws athena list-named-queries --work-group "$WORKGROUP_NAME" --region "$AWS_REGION" --query NamedQueryIds --output text 2>/dev/null || echo "")
  
  if [[ -z "$query_ids" ]]; then
    log_warning "No named queries found in WorkGroup"
    return 1
  fi
  
  local query_count
  query_count=$(echo "$query_ids" | wc -w)
  log_success "Found $query_count named queries"
  
  # List query names
  if [[ "$VERBOSE" == "true" ]]; then
    for query_id in $query_ids; do
      local query_name
      query_name=$(aws athena get-named-query --named-query-id "$query_id" --region "$AWS_REGION" --query NamedQuery.Name --output text 2>/dev/null || echo "unknown")
      log_verbose "Named query: $query_name ($query_id)"
    done
  fi
  
  # Test a simple query execution
  log_step "Testing query execution..."
  
  local query_sql="SELECT 1 as test_value"
  local execution_id
  
  execution_id=$(aws athena start-query-execution \
    --query-string "$query_sql" \
    --work-group "$WORKGROUP_NAME" \
    --region "$AWS_REGION" \
    --query QueryExecutionId \
    --output text 2>/dev/null || echo "")
  
  if [[ -z "$execution_id" ]]; then
    log_error "Failed to execute test query"
    return 1
  fi
  
  log_verbose "Test query execution ID: $execution_id"
  
  # Wait for query completion
  local timeout=30
  local elapsed=0
  local query_state=""
  
  while [[ $elapsed -lt $timeout ]]; do
    sleep 2
    elapsed=$((elapsed + 2))
    
    query_state=$(aws athena get-query-execution \
      --query-execution-id "$execution_id" \
      --region "$AWS_REGION" \
      --query QueryExecution.Status.State \
      --output text 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$query_state" == "SUCCEEDED" ]]; then
      log_success "Test query executed successfully"
      break
    elif [[ "$query_state" == "FAILED" || "$query_state" == "CANCELLED" ]]; then
      log_error "Test query failed with state: $query_state"
      return 1
    fi
    
    log_verbose "Query state: $query_state ($elapsed/${timeout}s elapsed)"
  done
  
  if [[ "$query_state" != "SUCCEEDED" ]]; then
    log_warning "Test query did not complete within $timeout seconds (state: $query_state)"
  fi
}

# Test CloudFormation stacks
test_cloudformation_stacks() {
  log_step "Testing CloudFormation stacks..."
  
  local expected_stacks=("LeanAnalyticsDataStack" "LeanAnalyticsAthenaStack")
  
  for stack in "${expected_stacks[@]}"; do
    local stack_status
    stack_status=$(aws cloudformation describe-stacks \
      --stack-name "$stack" \
      --region "$AWS_REGION" \
      --query 'Stacks[0].StackStatus' \
      --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$stack_status" == "NOT_FOUND" ]]; then
      log_error "CloudFormation stack '$stack' not found"
      continue
    fi
    
    if [[ "$stack_status" == "CREATE_COMPLETE" || "$stack_status" == "UPDATE_COMPLETE" ]]; then
      log_success "Stack '$stack' status: $stack_status"
    else
      log_warning "Stack '$stack' status: $stack_status"
    fi
    
    # Show stack outputs if verbose
    if [[ "$VERBOSE" == "true" ]]; then
      local outputs
      outputs=$(aws cloudformation describe-stacks \
        --stack-name "$stack" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs' \
        --output table 2>/dev/null || echo "No outputs")
      log_verbose "Stack '$stack' outputs:\n$outputs"
    fi
  done
}

# Test UI server
test_ui_server() {
  log_step "Testing UI server..."
  
  # Check if UI dependencies are installed
  if [[ ! -f "$PROJECT_ROOT/ui/package.json" ]]; then
    log_error "UI package.json not found"
    return 1
  fi
  
  if [[ ! -d "$PROJECT_ROOT/ui/node_modules" ]]; then
    log_warning "UI dependencies not installed, installing..."
    cd "$PROJECT_ROOT/ui"
    npm install >/dev/null 2>&1 || {
      log_error "Failed to install UI dependencies"
      return 1
    }
    cd "$PROJECT_ROOT"
  fi
  
  log_success "UI dependencies ready"
  
  # Start server in background
  log_info "Starting UI server in background..."
  cd "$PROJECT_ROOT/ui"
  
  # Check if port 3000 is already in use
  if lsof -i :3000 >/dev/null 2>&1; then
    log_warning "Port 3000 already in use, skipping server start"
    local server_running=true
  else
    npm start >/dev/null 2>&1 &
    local server_pid=$!
    local server_running=false
    
    # Wait for server to start
    log_info "Waiting for server to start..."
    local timeout=30
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
      if curl -s http://localhost:3000 >/dev/null 2>&1; then
        server_running=true
        break
      fi
      
      sleep 2
      elapsed=$((elapsed + 2))
      log_verbose "Waiting for server... ($elapsed/${timeout}s elapsed)"
    done
  fi
  
  cd "$PROJECT_ROOT"
  
  if [[ "$server_running" != "true" ]]; then
    log_error "UI server failed to start within timeout"
    if [[ -n "${server_pid:-}" ]]; then
      kill "$server_pid" 2>/dev/null || true
    fi
    return 1
  fi
  
  # Test UI endpoints
  log_step "Testing UI endpoints..."
  
  # Test main page
  local response_code
  response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
  
  if [[ "$response_code" == "200" ]]; then
    log_success "UI main page accessible (HTTP $response_code)"
  else
    log_error "UI main page returned HTTP $response_code"
  fi
  
  # Test API health endpoint
  response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health)
  
  if [[ "$response_code" == "200" ]]; then
    log_success "UI API health endpoint accessible (HTTP $response_code)"
  else
    log_warning "UI API health endpoint returned HTTP $response_code"
  fi
  
  # Test named queries endpoint
  response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/named-queries)
  
  if [[ "$response_code" == "200" ]]; then
    log_success "Named queries API accessible (HTTP $response_code)"
  else
    log_warning "Named queries API returned HTTP $response_code"
  fi
  
  # Cleanup: stop server if we started it
  if [[ -n "${server_pid:-}" ]]; then
    log_info "Stopping test UI server..."
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}

# Main validation function
run_validation() {
  echo
  echo "==================================================================================="
  echo "🧪 LEAN ANALYTICS PLATFORM - END-TO-END VALIDATION"
  echo "==================================================================================="
  echo "Project: $PROJECT_ROOT"
  echo "AWS Region: $AWS_REGION"
  echo "AWS Account: $AWS_ACCOUNT_ID"
  echo "Skip UI: $SKIP_UI"
  echo "Skip AWS: $SKIP_AWS"
  echo "Verbose: $VERBOSE"
  echo "==================================================================================="
  echo
  
  check_prerequisites
  
  if [[ "$SKIP_AWS" != "true" ]]; then
    check_aws_auth
    test_cloudformation_stacks
    test_s3_resources
    test_glue_resources
    test_athena_resources
  else
    log_info "Skipping AWS infrastructure tests"
  fi
  
  if [[ "$SKIP_UI" != "true" ]]; then
    test_ui_server
  else
    log_info "Skipping UI server tests"
  fi
  
  echo
  echo "==================================================================================="
  echo "🎯 VALIDATION SUMMARY"
  echo "==================================================================================="
  
  if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo "🚀 Your Lean Analytics platform is ready to use!"
    echo
    echo "Next steps:"
    echo "1. Start the UI server: cd ui && npm start"
    echo "2. Open http://localhost:3000"
    echo "3. Run some queries and explore your data!"
  elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  VALIDATION COMPLETED WITH WARNINGS${NC}"
    echo "Errors: $ERRORS"
    echo "Warnings: $WARNINGS"
    echo
    echo "Your platform should work, but check the warnings above."
  else
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo "Errors: $ERRORS"
    echo "Warnings: $WARNINGS"
    echo
    echo "Please fix the errors above before using the platform."
  fi
  
  echo "==================================================================================="
  echo
  
  return $ERRORS
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_validation
fi