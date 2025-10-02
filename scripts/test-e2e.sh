#!/bin/bash

# Local Development Testing Script for AWS Lean Analytics
# Tests fresh clone setup, local credentials, and UI functionality

set -e  # Exit on any error

# Configuration
REGION="us-west-2"
ACCOUNT="699027953523"
DATABASE_NAME="lean_demo_db"
WORKGROUP_NAME="lean_demo_wg"
BUCKET_NAME="lean-analytics-${ACCOUNT}-${REGION}"

echo "🧪 AWS Lean Analytics - Local Development Testing"
echo "================================================="
echo "Region: $REGION"
echo "Expected Account: $ACCOUNT"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    case $status in
        "PASS")
            echo -e "${GREEN}✅ PASS${NC}: $message"
            ;;
        "FAIL")
            echo -e "${RED}❌ FAIL${NC}: $message"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  WARN${NC}: $message"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  INFO${NC}: $message"
            ;;
    esac
}

# Function to check if command exists
check_command() {
    if command -v $1 >/dev/null 2>&1; then
        print_status "PASS" "$1 is installed"
        return 0
    else
        print_status "FAIL" "$1 is not installed"
        return 1
    fi
}

# Function to test API endpoint
test_api_endpoint() {
    local url=$1
    local description=$2
    local timeout=${3:-10}
    
    if curl -s --max-time $timeout "$url" >/dev/null 2>&1; then
        print_status "PASS" "$description"
        return 0
    else
        print_status "FAIL" "$description"
        return 1
    fi
}

# 1. Environment Setup Validation
echo "🔧 Phase 1: Local Environment Setup"
echo "-----------------------------------"

PREREQ_FAILED=0

# Check required tools
check_command "node" || PREREQ_FAILED=1
check_command "npm" || PREREQ_FAILED=1
check_command "aws" || PREREQ_FAILED=1
check_command "cdk" || PREREQ_FAILED=1
check_command "git" || PREREQ_FAILED=1
check_command "curl" || PREREQ_FAILED=1

# Check Node.js version
NODE_VERSION=$(node --version | sed 's/v//')
MAJOR_VERSION=$(echo $NODE_VERSION | cut -d. -f1)
if [ "$MAJOR_VERSION" -ge 18 ]; then
    print_status "PASS" "Node.js version $NODE_VERSION is supported"
else
    print_status "FAIL" "Node.js version $NODE_VERSION is too old (need 18+)"
    PREREQ_FAILED=1
fi

# Check NPM version
NPM_VERSION=$(npm --version)
print_status "INFO" "NPM version: $NPM_VERSION"

# Check CDK version
CDK_VERSION=$(cdk --version | head -n1)
print_status "INFO" "CDK version: $CDK_VERSION"

if [ $PREREQ_FAILED -eq 1 ]; then
    print_status "FAIL" "Prerequisites not met. Please install missing tools."
    exit 1
fi

echo ""

# 2. AWS Credentials Validation
echo "🔐 Phase 2: AWS Credentials Validation"
echo "--------------------------------------"

# Check AWS credentials
if aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
    CALLER_IDENTITY=$(aws sts get-caller-identity --region "$REGION")
    ACTUAL_ACCOUNT=$(echo "$CALLER_IDENTITY" | grep -o '"Account": *"[^"]*"' | sed 's/"Account": *"\([^"]*\)"/\1/')
    USER_ARN=$(echo "$CALLER_IDENTITY" | grep -o '"Arn": *"[^"]*"' | sed 's/"Arn": *"\([^"]*\)"/\1/')
    
    print_status "PASS" "AWS credentials configured"
    print_status "INFO" "Account: $ACTUAL_ACCOUNT"
    print_status "INFO" "User/Role: $USER_ARN"
    
    if [ "$ACTUAL_ACCOUNT" = "$ACCOUNT" ]; then
        print_status "PASS" "Account matches expected: $ACCOUNT"
    else
        print_status "WARN" "Account mismatch: expected $ACCOUNT, got $ACTUAL_ACCOUNT"
    fi
else
    print_status "FAIL" "AWS credentials not configured or invalid"
    print_status "INFO" "Please run: aws configure"
    exit 1
fi

# Check AWS CLI version
AWS_VERSION=$(aws --version 2>&1 | head -n1)
print_status "INFO" "AWS CLI: $AWS_VERSION"

echo ""

# 3. Project Structure Validation
echo "📁 Phase 3: Project Structure Validation"
echo "----------------------------------------"

# Check required directories
REQUIRED_DIRS=("cdk" "ui" "data" "scripts" ".github/workflows")
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        print_status "PASS" "Directory exists: $dir"
    else
        print_status "FAIL" "Directory missing: $dir"
        exit 1
    fi
done

# Check required files
REQUIRED_FILES=(
    "cdk/package.json"
    "cdk/lib/data-stack.ts"
    "cdk/lib/athena-stack.ts"
    "ui/package.json"
    "ui/server.js"
    "ui/public/index.html"
    "data/customers.csv"
    "data/orders.csv"
    "data/returns.csv"
    ".github/workflows/deploy.yml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_status "PASS" "File exists: $file"
    else
        print_status "FAIL" "File missing: $file"
        exit 1
    fi
done

echo ""

# 4. CDK Development Setup
echo "🏗️  Phase 4: CDK Development Setup"
echo "----------------------------------"

cd cdk

# Check if node_modules exists
if [ -d "node_modules" ]; then
    print_status "INFO" "CDK dependencies already installed"
else
    print_status "INFO" "Installing CDK dependencies..."
    if npm install --silent; then
        print_status "PASS" "CDK dependencies installed"
    else
        print_status "FAIL" "CDK dependency installation failed"
        exit 1
    fi
fi

# Test CDK synthesis
print_status "INFO" "Testing CDK synthesis..."
if npm run synth >/dev/null 2>&1; then
    print_status "PASS" "CDK synthesis successful"
else
    print_status "FAIL" "CDK synthesis failed"
    print_status "INFO" "Try: cd cdk && npm run synth"
    exit 1
fi

# Check if CDK is bootstrapped
print_status "INFO" "Checking CDK bootstrap status..."
if aws cloudformation describe-stacks \
    --stack-name "CDKToolkit" \
    --region "$REGION" >/dev/null 2>&1; then
    print_status "PASS" "CDK bootstrap stack exists"
else
    print_status "WARN" "CDK not bootstrapped for this account/region"
    print_status "INFO" "Run: cdk bootstrap aws://$ACCOUNT/$REGION"
fi

cd ..
echo ""

# 5. Data Files Validation
echo "📊 Phase 5: Data Files Validation"
echo "---------------------------------"

# Check CSV files structure and content
CSV_FILES=("customers.csv" "orders.csv" "returns.csv")
for file in "${CSV_FILES[@]}"; do
    if [ -f "data/$file" ]; then
        LINES=$(wc -l < "data/$file")
        SIZE=$(ls -lh "data/$file" | awk '{print $5}')
        print_status "PASS" "$file: $LINES lines, $SIZE"
        
        # Check for headers (first line)
        FIRST_LINE=$(head -n1 "data/$file")
        if [[ "$FIRST_LINE" == *","* ]]; then
            print_status "PASS" "$file has comma-separated headers"
        else
            print_status "WARN" "$file may not have proper CSV format"
        fi
    else
        print_status "FAIL" "$file not found"
        exit 1
    fi
done

# Validate specific headers
if grep -q "customer_id,customer_name,email,registration_date" data/customers.csv; then
    print_status "PASS" "customers.csv has correct headers"
else
    print_status "FAIL" "customers.csv has incorrect headers"
fi

if grep -q "order_id,customer_id,order_date,order_total,status" data/orders.csv; then
    print_status "PASS" "orders.csv has correct headers"
else
    print_status "FAIL" "orders.csv has incorrect headers"
fi

if grep -q "return_id,order_id,return_date,return_reason,refund_amount" data/returns.csv; then
    print_status "PASS" "returns.csv has correct headers"
else
    print_status "FAIL" "returns.csv has incorrect headers"
fi

echo ""

# 6. UI Development Setup
echo "🌐 Phase 6: UI Development Setup"
echo "--------------------------------"

cd ui

# Check if node_modules exists
if [ -d "node_modules" ]; then
    print_status "INFO" "UI dependencies already installed"
else
    print_status "INFO" "Installing UI dependencies..."
    if npm install --silent; then
        print_status "PASS" "UI dependencies installed"
    else
        print_status "FAIL" "UI dependency installation failed"
        exit 1
    fi
fi

# Validate server.js syntax
if node -c server.js; then
    print_status "PASS" "server.js syntax is valid"
else
    print_status "FAIL" "server.js has syntax errors"
    exit 1
fi

# Check package.json scripts
if grep -q '"start"' package.json; then
    print_status "PASS" "start script defined in package.json"
else
    print_status "WARN" "start script not found in package.json"
fi

# Check required frontend files
FRONTEND_FILES=("public/index.html" "public/style.css" "public/script.js")
for file in "${FRONTEND_FILES[@]}"; do
    if [ -f "$file" ]; then
        SIZE=$(ls -lh "$file" | awk '{print $5}')
        print_status "PASS" "$file exists ($SIZE)"
    else
        print_status "FAIL" "$file missing"
        exit 1
    fi
done

cd ..
echo ""

# 7. Infrastructure Readiness Check
echo "☁️  Phase 7: Infrastructure Readiness Check"
echo "-------------------------------------------"

# Check if infrastructure is deployed
print_status "INFO" "Checking deployed infrastructure..."

# Check S3 bucket
if aws s3 ls "s3://$BUCKET_NAME" --region "$REGION" >/dev/null 2>&1; then
    print_status "PASS" "S3 bucket exists and accessible"
    
    # Check for sample data
    if aws s3 ls "s3://$BUCKET_NAME/datasets/" --region "$REGION" | grep -q ".csv"; then
        print_status "PASS" "Sample data uploaded to S3"
    else
        print_status "WARN" "Sample data not found in S3"
    fi
else
    print_status "WARN" "S3 bucket not found or not accessible"
    print_status "INFO" "Deploy infrastructure first: cd cdk && cdk deploy --all"
fi

# Check Glue database
if aws glue get-database --name "$DATABASE_NAME" --region "$REGION" >/dev/null 2>&1; then
    print_status "PASS" "Glue database exists"
    
    # Check tables
    TABLES=$(aws glue get-tables --database-name "$DATABASE_NAME" --region "$REGION" --query 'TableList[].Name' --output text 2>/dev/null || echo "")
    if [ -n "$TABLES" ]; then
        print_status "PASS" "Tables found: $TABLES"
    else
        print_status "WARN" "No tables found (crawler may not have run)"
    fi
else
    print_status "WARN" "Glue database not found"
fi

# Check Athena WorkGroup
if aws athena get-work-group --work-group "$WORKGROUP_NAME" --region "$REGION" >/dev/null 2>&1; then
    print_status "PASS" "Athena WorkGroup exists"
else
    print_status "WARN" "Athena WorkGroup not found"
fi

echo ""

# 8. Local Server Test
echo "🚀 Phase 8: Local Server Test"
echo "-----------------------------"

print_status "INFO" "Testing UI server startup..."

cd ui

# Start server in background
npm start &
SERVER_PID=$!

# Give server time to start
sleep 5

# Test if server is running
if kill -0 $SERVER_PID 2>/dev/null; then
    print_status "PASS" "UI server started successfully (PID: $SERVER_PID)"
    
    # Test server endpoints
    sleep 2  # Give it a bit more time
    
    if test_api_endpoint "http://localhost:3000" "Homepage accessible" 5; then
        print_status "PASS" "Server responding on port 3000"
    else
        print_status "FAIL" "Server not responding on port 3000"
    fi
    
    if test_api_endpoint "http://localhost:3000/api/health" "Health endpoint" 5; then
        print_status "PASS" "Health endpoint working"
    else
        print_status "WARN" "Health endpoint not accessible"
    fi
    
    # Stop the server
    kill $SERVER_PID 2>/dev/null
    wait $SERVER_PID 2>/dev/null
    print_status "INFO" "Test server stopped"
else
    print_status "FAIL" "UI server failed to start"
    cd ..
    exit 1
fi

cd ..
echo ""

# 9. Documentation Check
echo "📚 Phase 9: Documentation Check"
echo "-------------------------------"

DOC_FILES=("README.md" "cdk/README.md" "ui/README.md")
for doc in "${DOC_FILES[@]}"; do
    if [ -f "$doc" ]; then
        LINES=$(wc -l < "$doc")
        print_status "PASS" "$doc exists ($LINES lines)"
    else
        print_status "WARN" "$doc not found"
    fi
done

# Check for setup instructions
if [ -f "README.md" ]; then
    if grep -qi "prerequisite\|requirement\|install\|setup" README.md; then
        print_status "PASS" "Setup instructions found in README"
    else
        print_status "WARN" "Setup instructions may be missing from README"
    fi
fi

echo ""

# 10. Git Repository Check
echo "🔄 Phase 10: Git Repository Check"
echo "---------------------------------"

if [ -d ".git" ]; then
    print_status "PASS" "Git repository initialized"
    
    # Check for .gitignore
    if [ -f ".gitignore" ]; then
        print_status "PASS" ".gitignore exists"
        
        # Check for common patterns
        if grep -q "node_modules" .gitignore; then
            print_status "PASS" "node_modules ignored"
        else
            print_status "WARN" "node_modules not in .gitignore"
        fi
        
        if grep -q "*.log" .gitignore; then
            print_status "PASS" "Log files ignored"
        else
            print_status "WARN" "Log files not in .gitignore"
        fi
    else
        print_status "WARN" ".gitignore not found"
    fi
    
    # Check remote origin
    if git remote get-url origin >/dev/null 2>&1; then
        ORIGIN=$(git remote get-url origin)
        print_status "PASS" "Git remote configured: $ORIGIN"
    else
        print_status "WARN" "Git remote not configured"
    fi
else
    print_status "WARN" "Not a Git repository"
fi

echo ""

# 11. Development Workflow Test
echo "🔧 Phase 11: Development Workflow Test"
echo "--------------------------------------"

# Test TypeScript compilation
cd cdk
if npm run build >/dev/null 2>&1; then
    print_status "PASS" "TypeScript compilation successful"
else
    print_status "WARN" "TypeScript compilation issues (may be expected without npm install)"
fi

# Test linting if available
if grep -q '"lint"' package.json; then
    if npm run lint >/dev/null 2>&1; then
        print_status "PASS" "Linting passed"
    else
        print_status "WARN" "Linting issues found"
    fi
else
    print_status "INFO" "No linting script found"
fi

cd ..

echo ""

# 12. Final Summary
echo "📋 Phase 12: Local Development Summary"
echo "-------------------------------------"

print_status "INFO" "Local Development Environment Status:"
echo ""
echo "🛠️  Development Tools:"
echo "   • Node.js: $NODE_VERSION"
echo "   • NPM: $NPM_VERSION"
echo "   • CDK: $CDK_VERSION"
echo "   • AWS CLI: $(echo "$AWS_VERSION" | cut -d' ' -f1-2)"
echo ""

echo "🔐 AWS Configuration:"
echo "   • Account: $ACTUAL_ACCOUNT"
echo "   • Region: $REGION"
echo "   • Credentials: Configured"
echo ""

echo "📁 Project Structure:"
echo "   • CDK: Ready for development"
echo "   • UI: Ready for development"
echo "   • Data: CSV files validated"
echo "   • Scripts: Available"
echo ""

echo "🚀 Next Steps for Development:"
echo "   1. Deploy infrastructure: cd cdk && cdk deploy --all"
echo "   2. Start development server: cd ui && npm start"
echo "   3. Open browser: http://localhost:3000"
echo "   4. Make changes and test locally"
echo ""

echo "🔧 Useful Commands:"
echo "   • CDK diff: cd cdk && cdk diff"
echo "   • CDK deploy: cd cdk && cdk deploy --all"
echo "   • CDK destroy: cd cdk && cdk destroy --all"
echo "   • UI dev server: cd ui && npm start"
echo "   • View logs: cd ui && npm start --verbose"
echo ""

print_status "PASS" "Local development environment validation completed!"
echo ""
echo "🎉 Ready for local development!"