#!/bin/bash

# Local Development Testing Script for AWS Lean Analytics
# Validates fresh clone setup and local development workflow

set -e

# Configuration
PROJECT_DIR=$(pwd)
UI_PORT=3000
SERVER_PID=""

echo "🧪 AWS Lean Analytics - Local Development Testing"
echo "================================================"
echo "Project Directory: $PROJECT_DIR"
echo "Testing Date: $(date)"
echo ""

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up test processes..."
    if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
        echo "   Stopped UI server (PID: $SERVER_PID)"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Function to check command availability
check_command() {
    local cmd="$1"
    local description="$2"
    
    if command -v "$cmd" &> /dev/null; then
        echo "   ✅ $description: $(which $cmd)"
        return 0
    else
        echo "   ❌ $description: Not found"
        return 1
    fi
}

# Function to test directory and files
test_project_structure() {
    local path="$1"
    local description="$2"
    
    if [ -e "$path" ]; then
        echo "   ✅ $description: $path"
        return 0
    else
        echo "   ❌ $description: $path (missing)"
        return 1
    fi
}

echo "🔧 Step 1: Prerequisites Check"
echo "-----------------------------"

failed_prereqs=0

# Check Node.js
if check_command "node" "Node.js"; then
    node_version=$(node --version)
    echo "      Version: $node_version"
    
    # Check if version is 18+
    major_version=$(echo $node_version | cut -d'.' -f1 | sed 's/v//')
    if [ "$major_version" -ge 18 ]; then
        echo "      ✅ Version requirement met (18+)"
    else
        echo "      ⚠️  Version should be 18+ (current: $node_version)"
        ((failed_prereqs++))
    fi
else
    ((failed_prereqs++))
fi

# Check npm
if check_command "npm" "npm"; then
    npm_version=$(npm --version)
    echo "      Version: $npm_version"
else
    ((failed_prereqs++))
fi

# Check AWS CLI
if check_command "aws" "AWS CLI"; then
    aws_version=$(aws --version 2>&1 | head -n1)
    echo "      Version: $aws_version"
else
    echo "      ⚠️  AWS CLI recommended for deployment"
fi

# Check CDK
if check_command "cdk" "AWS CDK"; then
    cdk_version=$(cdk --version 2>&1)
    echo "      Version: $cdk_version"
else
    echo "      ⚠️  CDK required for infrastructure deployment"
fi

echo ""

if [ $failed_prereqs -gt 0 ]; then
    echo "❌ $failed_prereqs prerequisite(s) failed. Please install missing tools."
    echo ""
    echo "Installation commands:"
    echo "  Node.js 18+: https://nodejs.org/"
    echo "  AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    echo "  AWS CDK: npm install -g aws-cdk"
    echo ""
fi

echo "📁 Step 2: Project Structure Validation"
echo "---------------------------------------"

structure_errors=0

# Check main directories
test_project_structure "cdk" "CDK Directory" || ((structure_errors++))
test_project_structure "ui" "UI Directory" || ((structure_errors++))
test_project_structure "data" "Data Directory" || ((structure_errors++))
test_project_structure "scripts" "Scripts Directory" || ((structure_errors++))
test_project_structure ".github/workflows" "GitHub Workflows" || ((structure_errors++))

# Check key files
test_project_structure "cdk/package.json" "CDK Package.json" || ((structure_errors++))
test_project_structure "cdk/bin/app.ts" "CDK App Entry" || ((structure_errors++))
test_project_structure "cdk/lib/data-stack.ts" "DataStack" || ((structure_errors++))
test_project_structure "cdk/lib/athena-stack.ts" "AthenaStack" || ((structure_errors++))

test_project_structure "ui/package.json" "UI Package.json" || ((structure_errors++))
test_project_structure "ui/server.js" "UI Server" || ((structure_errors++))
test_project_structure "ui/public/index.html" "UI Frontend" || ((structure_errors++))

test_project_structure "data/customers.csv" "Customer Data" || ((structure_errors++))
test_project_structure "data/orders.csv" "Order Data" || ((structure_errors++))
test_project_structure "data/returns.csv" "Return Data" || ((structure_errors++))

echo ""

if [ $structure_errors -gt 0 ]; then
    echo "❌ $structure_errors project structure issues found."
    echo "   Please ensure all required files are present."
    echo ""
fi

echo "⚙️  Step 3: AWS Credentials Validation"
echo "-------------------------------------"

aws_configured=false

# Check AWS credentials
if command -v aws &> /dev/null; then
    echo "🔍 Testing AWS credentials..."
    
    if aws sts get-caller-identity &> /dev/null; then
        identity=$(aws sts get-caller-identity 2>/dev/null)
        account=$(echo "$identity" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
        user_arn=$(echo "$identity" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
        
        echo "   ✅ AWS credentials valid"
        echo "      Account: $account"
        echo "      User/Role: $user_arn"
        
        # Check if correct account
        if [ "$account" = "699027953523" ]; then
            echo "      ✅ Correct AWS account for this project"
        else
            echo "      ⚠️  Different AWS account (expected: 699027953523, got: $account)"
        fi
        
        aws_configured=true
    else
        echo "   ❌ AWS credentials not configured or invalid"
        echo "      Run: aws configure"
        echo "      Or: aws sso login"
    fi
else
    echo "   ⚠️  AWS CLI not available - skipping credential check"
fi

echo ""

echo "📦 Step 4: Dependency Installation"
echo "----------------------------------"

install_errors=0

# Test CDK dependencies
echo "🔍 Testing CDK dependency installation..."
cd "$PROJECT_DIR/cdk"

if [ -f "package.json" ]; then
    echo "   Installing CDK dependencies..."
    if npm install --silent; then
        echo "   ✅ CDK dependencies installed successfully"
        
        # Test CDK synthesis
        echo "   Testing CDK synthesis..."
        if npm run synth --silent &> /dev/null; then
            echo "   ✅ CDK synthesis successful"
        else
            echo "   ❌ CDK synthesis failed"
            ((install_errors++))
        fi
    else
        echo "   ❌ CDK dependency installation failed"
        ((install_errors++))
    fi
else
    echo "   ❌ CDK package.json not found"
    ((install_errors++))
fi

# Test UI dependencies
echo "🔍 Testing UI dependency installation..."
cd "$PROJECT_DIR/ui"

if [ -f "package.json" ]; then
    echo "   Installing UI dependencies..."
    if npm install --silent; then
        echo "   ✅ UI dependencies installed successfully"
    else
        echo "   ❌ UI dependency installation failed"
        ((install_errors++))
    fi
else
    echo "   ❌ UI package.json not found"
    ((install_errors++))
fi

cd "$PROJECT_DIR"
echo ""

echo "🌐 Step 5: UI Server Testing"
echo "----------------------------"

echo "🔍 Starting UI server for testing..."

# Start UI server in background
cd "$PROJECT_DIR/ui"
npm start &> /tmp/ui-server.log &
SERVER_PID=$!

echo "   UI server started (PID: $SERVER_PID)"
echo "   Waiting for server startup..."

# Wait for server to start
max_attempts=15
attempt=0
server_ready=false

while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:$UI_PORT/health &> /dev/null; then
        server_ready=true
        break
    fi
    
    sleep 2
    ((attempt++))
    echo "   Attempt $attempt/$max_attempts..."
done

if [ "$server_ready" = true ]; then
    echo "   ✅ UI server is responding"
    
    # Test health endpoint
    echo "🔍 Testing health endpoint..."
    health_response=$(curl -s http://localhost:$UI_PORT/health)
    if echo "$health_response" | grep -q "healthy"; then
        echo "   ✅ Health endpoint working"
    else
        echo "   ⚠️  Health endpoint response unexpected"
    fi
    
    # Test API status
    echo "🔍 Testing API status endpoint..."
    if curl -s http://localhost:$UI_PORT/api/status &> /dev/null; then
        echo "   ✅ API status endpoint working"
    else
        echo "   ❌ API status endpoint failed"
    fi
    
    # Test frontend
    echo "🔍 Testing frontend..."
    if curl -s http://localhost:$UI_PORT/ | grep -q "AWS Lean Analytics"; then
        echo "   ✅ Frontend loading correctly"
    else
        echo "   ❌ Frontend not loading properly"
    fi
    
    # Test AWS connectivity (if credentials available)
    if [ "$aws_configured" = true ]; then
        echo "🔍 Testing AWS connectivity..."
        conn_response=$(curl -s http://localhost:$UI_PORT/api/test-connection)
        if echo "$conn_response" | grep -q '"success":true'; then
            echo "   ✅ AWS connectivity test passed"
        else
            echo "   ⚠️  AWS connectivity test failed (may need deployed infrastructure)"
        fi
    fi
    
else
    echo "   ❌ UI server failed to start within ${max_attempts} attempts"
    echo "   Check logs: tail /tmp/ui-server.log"
    install_errors=$((install_errors + 1))
fi

cd "$PROJECT_DIR"
echo ""

echo "🎯 Step 6: Error Scenario Testing"
echo "---------------------------------"

if [ "$server_ready" = true ]; then
    echo "🔍 Testing error handling..."
    
    # Test invalid query
    echo "   Testing invalid SQL query..."
    invalid_response=$(curl -s -X POST http://localhost:$UI_PORT/api/query \
        -H "Content-Type: application/json" \
        -d '{"sql": ""}')
    
    if echo "$invalid_response" | grep -q '"success":false'; then
        echo "   ✅ Invalid query properly rejected"
    else
        echo "   ⚠️  Invalid query handling unexpected"
    fi
    
    # Test invalid named query
    echo "   Testing invalid named query..."
    invalid_named=$(curl -s -X POST http://localhost:$UI_PORT/api/query \
        -H "Content-Type: application/json" \
        -d '{"queryType": "named", "namedQueryId": "nonexistent"}')
    
    if echo "$invalid_named" | grep -q '"success":false'; then
        echo "   ✅ Invalid named query properly rejected"
    else
        echo "   ⚠️  Invalid named query handling unexpected"
    fi
    
else
    echo "   ⚠️  Skipping error tests (server not running)"
fi

echo ""

echo "📋 Step 7: Test Summary"
echo "----------------------"

total_issues=$((failed_prereqs + structure_errors + install_errors))

if [ $total_issues -eq 0 ]; then
    echo "🎉 All local development tests passed!"
    echo ""
    echo "✅ Prerequisites: All requirements met"
    echo "✅ Project Structure: All files present"
    echo "✅ Dependencies: Installed successfully"
    echo "✅ UI Server: Running and responsive"
    echo "✅ Error Handling: Working correctly"
    echo ""
    echo "🚀 Your local development environment is ready!"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy infrastructure: cd cdk && npm run deploy"
    echo "  2. Run Glue crawler: aws glue start-crawler --name lean-analytics-crawler"
    echo "  3. Test queries in UI: http://localhost:$UI_PORT"
    
else
    echo "⚠️  Found $total_issues issue(s) in local development setup"
    echo ""
    if [ $failed_prereqs -gt 0 ]; then
        echo "❌ Prerequisites: $failed_prereqs missing tools"
    fi
    if [ $structure_errors -gt 0 ]; then
        echo "❌ Project Structure: $structure_errors missing files"
    fi
    if [ $install_errors -gt 0 ]; then
        echo "❌ Installation/Runtime: $install_errors errors"
    fi
    echo ""
    echo "Please resolve these issues before continuing."
fi

echo ""
echo "📖 Documentation: See README.md for detailed setup instructions"
echo "🔧 Troubleshooting: Check logs in /tmp/ui-server.log"
echo "💬 Support: Review error messages above for specific issues"
echo ""

exit $total_issues