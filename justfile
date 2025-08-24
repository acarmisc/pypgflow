# PyPgFlow Development Commands
# Just is a handy command runner: https://github.com/casey/just
#
# Environment variables:
# API_URL - PostgREST API endpoint (default: http://localhost:3000)
# 
# Examples:
# API_URL=http://prod.example.com:3000 just list-workflows
# export API_URL=http://staging.example.com:3000 && just list-instances

# Show available commands
default:
    @just --list

# Start development environment
dev:
    @echo "Starting PyPgFlow services..."
    cd deploy/docker && docker-compose up -d postgres postgrest pgadmin swagger-ui
    @echo "Waiting for services to be ready..."
    @sleep 8
    @echo "✅ Services ready!"
    @echo "API available at http://localhost:3000"
    @echo "Swagger UI available at http://localhost:8080"
    @echo "Database available at localhost:5432"
    @echo "pgAdmin available at http://localhost:5050"
    @echo "  Email: admin@pypgflow.com"
    @echo "  Password: admin123"

# Stop all services (including CLI)
down:
    @echo "Stopping all PyPgFlow services..."
    -cd deploy/docker && docker-compose down
    @echo "✅ Services stopped"

# Stop services and remove volumes
clean:
    @echo "Cleaning up all PyPgFlow resources..."
    -cd deploy/docker && docker-compose down -v
    docker system prune -f
    @echo "✅ Cleanup complete"

# Build CLI image
build:
    @echo "Building CLI image..."
    cd deploy/docker && docker-compose build cli
    @echo "✅ CLI image built"

# Run tests
test:
    cd deploy/docker && docker-compose run --rm cli python -m pytest tests/

# Run CLI tool (ensures CLI service is available)
cli *args:
    @echo "Running CLI command: {{args}}"
    cd deploy/docker && docker-compose run --rm cli {{args}}

# Show logs from all services
logs:
    cd deploy/docker && docker-compose logs -f

# Connect to PostgreSQL shell
db-shell:
    cd deploy/docker && docker-compose exec postgres psql -U pypgflow -d pypgflow

# Show API documentation info
api-docs:
    @echo "API documentation available at:"
    @echo "• PostgREST native: http://localhost:3000"
    @echo "• Swagger UI: http://localhost:8080"
    @echo ""
    @echo "Key endpoints:"
    @echo "• GET  /api/workflows - List workflows"
    @echo "• GET  /api/entity_workflows - List workflow instances"
    @echo "• POST /rpc/start_workflow - Start workflow"
    @echo "• POST /rpc/execute_transition - Execute transition"
    @echo ""
    @if command -v open >/dev/null 2>&1; then open http://localhost:8080; elif command -v xdg-open >/dev/null 2>&1; then xdg-open http://localhost:8080; fi

# Open Swagger UI interface
swagger:
    @echo "Swagger UI available at:"
    @echo "http://localhost:8080"
    @echo ""
    @echo "Features:"
    @echo "• Interactive API testing"
    @echo "• Request/response schemas"
    @echo "• Parameter documentation"
    @echo "• Try it out functionality"
    @if command -v open >/dev/null 2>&1; then open http://localhost:8080; elif command -v xdg-open >/dev/null 2>&1; then xdg-open http://localhost:8080; fi

# Show pgAdmin access info
pgadmin:
    @echo "pgAdmin available at:"
    @echo "http://localhost:5050"
    @echo "Login credentials:"
    @echo "  Email: admin@pypgflow.com"
    @echo "  Password: admin123"
    @echo ""
    @echo "Database connection settings:"
    @echo "  Host: postgres"
    @echo "  Port: 5432"
    @echo "  Database: pypgflow"
    @echo "  Username: pypgflow"
    @echo "  Password: pypgflow123"

# Initialize database with sample data (requires CLI container for file access)
init-db:
    @echo "Initializing database with sample workflows..."
    cd deploy/docker && docker-compose run --rm cli import-workflow /examples/fraud_detection.yaml
    cd deploy/docker && docker-compose run --rm cli import-workflow /examples/order_processing.yaml
    @echo "✅ Sample workflows imported"

# Import a workflow from YAML file (requires CLI container for file access)
import-workflow file:
    @echo "Importing workflow from {{file}}..."
    cd deploy/docker && docker-compose run --rm cli import-workflow {{file}}

# List all workflows
list-workflows:
    @echo "Fetching all workflows..."
    @curl -s "${API_URL:-http://localhost:3000}/api/workflows" | jq -r '.[] | "ID: \(.id) | Name: \(.name) v\(.version) | Active: \(.is_active)"' || echo "API not available. Run 'just dev' first."

# List workflow instances with optional filters  
list-instances *args:
    @echo "Fetching workflow instances..."
    @curl -s "${API_URL:-http://localhost:3000}/api/entity_workflows?order=updated_at.desc" | jq -r '.[] | "ID: \(.id) | Entity: \(.entity_table):\(.entity_id) | Workflow: \(.workflow_name) | State: \(.current_state) | Status: \(.status)"' || echo "API not available. Run 'just dev' first."

# Start a workflow for an entity by name
start-workflow entity-table entity-id workflow-name metadata="{}":
    @echo "Starting workflow '{{workflow-name}}' for {{entity-table}}:{{entity-id}}..."
    @curl -s -X POST "${API_URL:-http://localhost:3000}/rpc/start_workflow" \
        -H "Content-Type: application/json" \
        -d '{"workflow_name": "{{workflow-name}}", "entity_table": "{{entity-table}}", "entity_id": "{{entity-id}}", "metadata": {{metadata}}}' \
        | jq -r 'if type == "string" then "✅ Instance ID: " + . else "❌ Error: " + (. | tostring) end' || echo "❌ API call failed"

# Start a workflow for an entity by ID (recommended)
start-workflow-by-id entity-table entity-id workflow-id metadata="{}":
    @echo "Starting workflow {{workflow-id}} for {{entity-table}}:{{entity-id}}..."
    @curl -s -X POST "${API_URL:-http://localhost:3000}/rpc/start_workflow_by_id" \
        -H "Content-Type: application/json" \
        -d '{"workflow_definition_id": "{{workflow-id}}", "entity_table": "{{entity-table}}", "entity_id": "{{entity-id}}", "metadata": {{metadata}}}' \
        | jq -r 'if type == "string" then "✅ Instance ID: " + . else "❌ Error: " + (. | tostring) end' || echo "❌ API call failed"

# Execute a workflow transition
transition instance-id to-state executed-by="api_user" metadata="{}" context="{}" notes="":
    @echo "Transitioning instance {{instance-id}} to state '{{to-state}}'..."
    @curl -s -X POST "${API_URL:-http://localhost:3000}/rpc/execute_transition" \
        -H "Content-Type: application/json" \
        -d '{"instance_id": "{{instance-id}}", "to_state": "{{to-state}}", "executed_by": "{{executed-by}}", "metadata": {{metadata}}, "context": {{context}}, "notes": "{{notes}}"}' \
        | jq -r 'if . == true then "✅ Transition successful" else "❌ Transition failed: " + (. | tostring) end' || echo "❌ API call failed"

# Show workflow transition history
history instance-id:
    @echo "Fetching transition history for instance {{instance-id}}..."
    @curl -s "${API_URL:-http://localhost:3000}/api/workflow_history?entity_workflow_instance_id=eq.{{instance-id}}&order=executed_at.desc" \
        | jq -r '.[] | "\(.executed_at) | \(.from_state // "START") → \(.to_state) | By: \(.executed_by)" + (if .notes then " | Notes: \(.notes)" else "" end)' || echo "❌ API call failed"

# Run a specific test file
test-file file:
    @echo "Running test file: {{file}}"
    cd deploy/docker && docker-compose run --rm cli python -m pytest tests/{{file}}

# Format Python code with black
format:
    @echo "Formatting Python code with black..."
    cd deploy/docker && docker-compose run --rm cli black cli/

# Lint Python code with ruff
lint:
    @echo "Linting Python code with ruff..."
    cd deploy/docker && docker-compose run --rm cli ruff check cli/

# Type check with mypy
typecheck:
    @echo "Type checking with mypy..."
    cd deploy/docker && docker-compose run --rm cli mypy cli/

# Run all quality checks
check: lint typecheck test

# Show container status
status:
    @echo "📊 PyPgFlow service status:"
    cd deploy/docker && docker-compose ps
    @echo ""
    @echo "🔍 Quick health check:"
    @echo "Services should show 'Up' status"
    @echo "If services are not running, try: just dev"

# Follow logs for specific service
logs-service service:
    cd deploy/docker && docker-compose logs -f {{service}}

# Restart a specific service
restart service:
    cd deploy/docker && docker-compose restart {{service}}

# Execute command in running postgres container
db-exec *cmd:
    cd deploy/docker && docker-compose exec postgres {{cmd}}

# Backup database
backup:
    cd deploy/docker && docker-compose exec postgres pg_dump -U pypgflow -d pypgflow > backup.sql
    @echo "Database backed up to backup.sql"

# Restore database from backup
restore file:
    cd deploy/docker && docker-compose exec -T postgres psql -U pypgflow -d pypgflow < {{file}}
    @echo "Database restored from {{file}}"

# Show database size and statistics
db-stats:
    cd deploy/docker && docker-compose exec postgres psql -U pypgflow -d pypgflow -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size FROM pg_tables WHERE schemaname IN ('core', 'api') ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"

# Run interactive Python shell with database connection
shell:
    @echo "Starting interactive Python shell with database connection..."
    cd deploy/docker && docker-compose run --rm cli python -c "from pypgflow.database import DatabaseManager; import os; db = DatabaseManager(os.getenv('DATABASE_URL')); print('Database manager available as db'); import IPython; IPython.embed()"

# Open PostgreSQL admin interface (pgAdmin alternative)
db-admin:
    @echo "Opening pgAdmin interface..."
    @echo "Navigate to: http://localhost:5050"
    @echo "Login with: admin@pypgflow.com / admin123"
    @if command -v open >/dev/null 2>&1; then open http://localhost:5050; elif command -v xdg-open >/dev/null 2>&1; then xdg-open http://localhost:5050; fi

# Test API endpoints
test-api:
    @echo "🧪 Testing API endpoints..."
    @echo ""
    @echo "1. 📋 Available workflows:"
    just list-workflows
    @echo ""
    @echo "2. 📊 Current workflow instances:"
    just list-instances
    @echo ""
    @echo "3. 🔍 API health check:"
    @curl -s "${API_URL:-http://localhost:3000}/" | jq -r 'keys[]' | head -5 || echo "API not responding"
    @echo ""
    @echo "4. 📚 Available endpoints:"
    @echo "  • ${API_URL:-http://localhost:3000}/api/workflows"
    @echo "  • ${API_URL:-http://localhost:3000}/api/entity_workflows"  
    @echo "  • ${API_URL:-http://localhost:3000}/rpc/start_workflow"
    @echo "  • ${API_URL:-http://localhost:3000}/rpc/execute_transition"

# Get workflow ID by name (helper command)
get-workflow-id workflow-name:
    @curl -s "${API_URL:-http://localhost:3000}/api/workflows?name=eq.{{workflow-name}}&select=id" | jq -r '.[0].id // empty' || echo "Workflow not found"

# Show current API configuration
api-info:
    @echo "🔗 Current API configuration:"
    @echo "API URL: ${API_URL:-http://localhost:3000}"
    @echo ""
    @echo "🧪 Testing connection..."
    @curl -s "${API_URL:-http://localhost:3000}/" >/dev/null && echo "✅ API is responding" || echo "❌ API is not responding"

# Quick development setup
setup:
    @echo "🚀 Setting up PyPgFlow development environment..."
    just dev
    @echo "Waiting for services to initialize..."
    @sleep 12
    just init-db
    @echo ""
    @echo "✅ Setup complete!"
    @echo ""
    @echo "📚 Available interfaces:"
    @echo "• just swagger      - Interactive API documentation"
    @echo "• just pgadmin      - Database management"  
    @echo "• just list-workflows - CLI workflow listing"
    @echo "• just test-api     - Quick API test"
    @echo ""
    @echo "🔧 Try these commands:"
    @echo "• just list-workflows"
    @echo "• just list-instances"