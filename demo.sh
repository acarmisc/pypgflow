#!/bin/bash
# PyPgFlow Demo Script for Asciinema Recording
# Run this script to demonstrate PyPgFlow functionality

set -e

echo "🚀 PyPgFlow Demo - Multi-tenant Workflow Engine"
echo "==============================================="
echo ""

echo "📋 Step 1: Check if services are running"
just status
echo ""

echo "🛠️ Step 2: Quick setup (start services + import workflows)"
echo "This will start PostgreSQL, PostgREST, Swagger UI, and pgAdmin"
just setup
echo ""

echo "📂 Step 3: List available workflows"
just list-workflows
echo ""

echo "📊 Step 4: Show current workflow instances"  
just list-instances
echo ""

echo "🚀 Step 5: Start a fraud detection workflow for transaction tx123"
echo "Using workflow name (simpler approach)..."
echo ""

echo "📋 Step 6: Start workflow by name"
just start-workflow transactions tx123 fraud_detection '{"amount": 5000, "risk_score": "medium"}'
echo ""

echo "📊 Step 7: List instances again (should show our new instance)"
just list-instances
echo ""

echo "🔍 Step 8: Get workflow ID for demonstration"
WORKFLOW_ID=$(just get-workflow-id fraud_detection)
echo "Fraud detection workflow ID: $WORKFLOW_ID"
echo ""

echo "🔄 Step 9: Example of starting by ID (faster method)"
echo "Command: just start-workflow-by-id transactions tx456 $WORKFLOW_ID '{\"amount\": 3000}'"
if [ ! -z "$WORKFLOW_ID" ] && [ "$WORKFLOW_ID" != "Workflow not found" ]; then
    just start-workflow-by-id transactions tx456 "$WORKFLOW_ID" '{"amount": 3000}'
fi
echo ""

echo "📊 Step 10: List instances again"
just list-instances
echo ""

echo "💡 Step 11: Transition examples (replace <INSTANCE_ID> with actual ID from above)"
echo "Command examples:"
echo "just transition <INSTANCE_ID> investigating security_analyst '{}' '{\"department\": \"fraud_team\"}' 'Suspicious pattern detected'"
echo "just history <INSTANCE_ID>"
echo ""

echo "🌐 Step 12: Test API endpoints"
just test-api
echo ""

echo "✅ Demo completed!"
echo ""
echo "🔗 Available interfaces:"
echo "• Swagger UI: http://localhost:8080"
echo "• API: http://localhost:3000"
echo "• pgAdmin: http://localhost:5050"
echo ""
echo "🧹 To clean up: just clean"