# PyPgFlow

A multi-tenant workflow engine built on PostgreSQL with REST API via PostgREST.

## Features

- **Multi-tenant**: Complete tenant isolation with Row Level Security
- **PostgreSQL-based**: Leverages PostgreSQL triggers, indexes, and functions for performance
- **YAML Workflow Definitions**: Human-readable workflow configurations
- **REST API**: Full REST interface via PostgREST
- **Complete Audit Trail**: Track all workflow transitions with metadata
- **Entity Linking**: Connect any entity to workflows via frontier tables
- **CLI Tools**: Import workflows and manage instances
- **Docker Ready**: Complete Docker setup with development playground

## Quick Start

```bash
# Clone and start the development environment
git clone <repository>
cd pypgflow
just dev

# Import example workflows
just init-db

# Access the API documentation (Swagger UI)
just swagger
# Opens http://localhost:8080 with interactive API docs

# Access pgAdmin for database management
just pgadmin
# http://localhost:5050

# Try the CLI
just list-workflows
just list-instances
```

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Client Apps   │────│   PostgREST API  │────│   PostgreSQL    │
│                 │    │   Port: 3000     │    │   + Triggers    │
└─────────────────┘    └──────────────────┘    │   Port: 5432    │
                                │               └─────────────────┘
                       ┌────────────────┐               │
                       │   Swagger UI   │───────────────┤
                       │   Port: 8080   │               │
                       └────────────────┘               │
                                                        │
                       ┌────────────────┐               │
                       │   CLI Tools    │───────────────┤
                       │   (pypgflow)   │               │
                       └────────────────┘               │
                                                        │
                       ┌────────────────┐               │
                       │    pgAdmin     │───────────────┘
                       │   Port: 5050   │
                       └────────────────┘
```

## API Endpoints

### Core Endpoints
- `GET /api/workflows` - List all workflows
- `GET /api/workflows?name=eq.fraud_detection` - Get specific workflow
- `GET /api/workflow_states?workflow_name=eq.fraud_detection` - Get workflow states
- `GET /api/workflow_transitions?workflow_name=eq.fraud_detection` - Get possible transitions

### Entity Workflow Management
- `POST /rpc/start_workflow` - Start workflow for entity
- `POST /rpc/execute_transition` - Execute state transition
- `GET /api/entity_workflows` - List workflow instances
- `GET /api/entity_workflows?entity_table=eq.orders&entity_id=eq.123` - Get entity workflow
- `GET /api/workflow_history?entity_workflow_instance_id=eq.<uuid>` - Get transition history

### Example API Calls

```bash
# Get workflow ID first
curl "http://localhost:3000/api/workflows?name=eq.fraud_detection&select=id,name"

# Start a fraud detection workflow by ID (recommended)
curl -X POST http://localhost:3000/rpc/start_workflow_by_id \
  -H "Content-Type: application/json" \
  -d '{
    "workflow_definition_id": "uuid-from-above",
    "entity_table": "transactions", 
    "entity_id": "12345",
    "metadata": {"amount": 5000, "risk_score": "medium"}
  }'

# Or start by name (compatibility)
curl -X POST http://localhost:3000/rpc/start_workflow \
  -H "Content-Type: application/json" \
  -d '{
    "workflow_name": "fraud_detection",
    "entity_table": "transactions", 
    "entity_id": "12345",
    "metadata": {"amount": 5000, "risk_score": "medium"}
  }'

# CLI examples
just list-workflows  # Get workflow ID
just start-workflow-by-id transactions 12345 <workflow-id>  # Recommended
just start-workflow transactions 12345 fraud_detection     # By name

# Execute a transition
curl -X POST http://localhost:3000/rpc/execute_transition \
  -H "Content-Type: application/json" \
  -d '{
    "instance_id": "<uuid>",
    "to_state": "investigating",
    "executed_by": "security_analyst_1",
    "notes": "Suspicious pattern detected"
  }'

# Or use the CLI with context information
just transition <instance-id> investigating --executed-by security_analyst_1 --context '{"department": "fraud_team", "alert_type": "velocity_check"}' --notes "Suspicious pattern detected"

# List all fraud detection workflows
curl "http://localhost:3000/api/entity_workflows?workflow_name=eq.fraud_detection&order=updated_at.desc"

# Or use the CLI
just list-instances --workflow-name fraud_detection
```

## CLI Usage

The CLI tool provides comprehensive workflow management capabilities:

```bash
# Import workflow from YAML
just import-workflow examples/fraud_detection.yaml

# List all workflows (shows IDs and names)
just list-workflows

# Start workflow by ID (recommended approach)
just start-workflow-by-id transactions 12345 <workflow-uuid>

# Start workflow by name (compatibility)
just start-workflow transactions 12345 fraud_detection

# List workflow instances (with filters)
just list-instances --workflow-name fraud_detection --state investigating

# Execute transition with context information
just transition <instance-id> investigating --executed-by analyst1 --context '{"user_department": "fraud_analysis", "case_priority": "high"}' --notes "Starting investigation"

# View transition history
just history <instance-id>
```

## Workflow Definition Format

Workflows are defined in YAML format with rich context validation:

```yaml
workflow:
  name: "my_workflow"
  version: "1.0"
  metadata:
    description: "Workflow description"
    category: "business_process"
    
states:
  - name: "initial_state"
    initial: true
    metadata:
      display_name: "Initial State"
      color: "#orange"
      
  - name: "processing"
    metadata:
      display_name: "Processing"
      color: "#blue"
      requires_role: "processor"
      
  - name: "completed"
    final: true
    metadata:
      display_name: "Completed"
      color: "#green"

transitions:
  - from: "initial_state"
    to: "processing"
    name: "start_processing"
    conditions:
      field_required: "approval_code"
    context:
      # Context information for the integrating application
      # This is stored but not validated by the workflow engine
      typical_user_roles: ["processor", "admin"] 
      requires_priority_field: true
      suggested_amount_range: "0-10000"
      approval_code_format: "ABC-1234"
    metadata:
      display_name: "Start Processing"
      
  - from: "processing"
    to: "completed"
    name: "complete"
    context:
      # Context for the application - informational only
      completion_requires: "user_id"
      quality_check_recommended: true
    metadata:
      display_name: "Complete"
```

### Context Field

The `context` field in transitions is a JSON field that stores application-specific information:

- **Purpose**: Store contextual information for the integrating application
- **Usage**: Configuration, business rules, UI hints, integration parameters
- **Validation**: None - the workflow engine does not validate context content
- **Access**: Available via API and CLI for application logic
- **Examples**: Default values, allowed options, business rules, UI configuration

## Database Schema

### Core Tables
- `tenants` - Multi-tenant isolation
- `workflow_definitions` - Workflow templates
- `workflow_states` - State definitions
- `workflow_transitions` - Valid transitions
- `entity_workflow_instances` - Active workflow instances (frontier table)
- `workflow_transition_history` - Complete audit trail

### Key Features
- **Row Level Security (RLS)** for multi-tenancy
- **Optimized indexes** for performance
- **Triggers** for automatic timestamp updates
- **JSONB** for flexible metadata storage
- **UUID** primary keys for distributed systems

## Development

### Prerequisites
- Docker and Docker Compose
- Just command runner (https://github.com/casey/just)

> **Note**: This project uses [uv](https://github.com/astral-sh/uv) for Python dependency management instead of pip. The CLI is packaged using `pyproject.toml` and installed via uv in the Docker container.

### Development Commands
```bash
# Start services
just dev

# Quick setup (dev + init-db)
just setup

# View logs
just logs

# Connect to database shell
just db-shell

# Open pgAdmin interface
just pgadmin

# Run tests
just test

# Clean everything
just clean
```

### Project Structure
```
pypgflow/
├── cli/                    # Python CLI package (using uv)
│   ├── pypgflow/          # Main Python package
│   │   ├── main.py        # Click-based CLI interface
│   │   ├── database.py    # Database operations
│   │   └── models.py      # Data models
│   └── pyproject.toml     # Python project configuration (uv)
├── database/
│   └── init/              # PostgreSQL initialization scripts
│       ├── 01-init.sql    # Schema and tables
│       ├── 02-functions.sql # Stored procedures
│       └── 03-api-views.sql # PostgREST views
├── deploy/
│   └── docker/            # Docker deployment files
│       ├── docker-compose.yml  # Development environment
│       ├── Dockerfile.cli      # CLI container
│       └── .env.example        # Environment variables template
├── examples/              # Example workflow definitions
├── docs/                  # Additional documentation
├── justfile              # Development automation
└── README.md             # Project documentation
```

## Testing

Run the complete test suite:

```bash
# Run all tests
just test

# Run specific test file
just test-file test_cli.py
just test-file test_models.py

# Run all quality checks (lint, typecheck, test)
just check
```

## Production Deployment

For production deployment, consider:

1. **Security**: Configure proper JWT secrets and database credentials
2. **Performance**: Optimize PostgreSQL configuration and connection pooling
3. **Monitoring**: Add logging and metrics collection
4. **Backup**: Implement database backup strategies
5. **Scaling**: Consider read replicas for heavy read workloads

### Environment Variables
- `DATABASE_URL` - PostgreSQL connection string
- `PGRST_JWT_SECRET` - JWT secret for PostgREST authentication
- `PGRST_DB_ANON_ROLE` - Anonymous role for PostgREST

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

MIT License - see LICENSE file for details.