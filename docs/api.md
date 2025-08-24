# PyPgFlow API Reference

## Interactive Documentation

PyPgFlow automatically generates interactive API documentation via PostgREST's OpenAPI support.

**Access Swagger UI:**
- URL: http://localhost:3000
- Command: `just api-docs`

The Swagger interface provides:
- Interactive endpoint testing
- Request/response schemas
- Authentication examples
- Parameter documentation

## Authentication

PyPgFlow uses PostgreSQL Row Level Security (RLS) for multi-tenant access control. In production, implement JWT-based authentication with PostgREST.

## REST Endpoints

### Workflows

#### GET /api/workflows
List all workflow definitions.

**Query Parameters:**
- `name=eq.workflow_name` - Filter by workflow name
- `is_active=eq.true` - Filter by active status
- `order=created_at.desc` - Order results

**Response:**
```json
[
  {
    "id": "uuid",
    "name": "fraud_detection",
    "version": "1.0",
    "is_active": true,
    "created_at": "2024-01-01T10:00:00Z",
    "updated_at": "2024-01-01T10:00:00Z",
    "metadata": {},
    "states": [
      {
        "id": "uuid",
        "name": "new",
        "is_initial": true,
        "is_final": false,
        "metadata": {
          "display_name": "Nuovo",
          "color": "#orange"
        }
      }
    ]
  }
]
```

#### GET /api/workflow_states
List workflow states.

**Query Parameters:**
- `workflow_name=eq.fraud_detection` - Filter by workflow name

#### GET /api/workflow_transitions
List possible transitions between states.

**Query Parameters:**
- `workflow_name=eq.fraud_detection` - Filter by workflow name

### Entity Workflows

#### POST /rpc/start_workflow_by_id (Recommended)
Start a workflow for an entity using workflow definition ID.

**Request:**
```json
{
  "workflow_definition_id": "uuid-of-workflow-definition",
  "entity_table": "transactions",
  "entity_id": "12345",
  "metadata": {
    "amount": 5000,
    "risk_score": "medium"
  }
}
```

#### POST /rpc/start_workflow (Compatibility)
Start a workflow for an entity using workflow name.

**Request:**
```json
{
  "workflow_name": "fraud_detection",
  "entity_table": "transactions",
  "entity_id": "12345",
  "metadata": {
    "amount": 5000,
    "risk_score": "medium"
  }
}
```

**Response:**
```json
"uuid-of-workflow-instance"
```

#### POST /rpc/execute_transition
Execute a state transition with context information.

**Request:**
```json
{
  "instance_id": "uuid",
  "to_state": "investigating",
  "executed_by": "security_analyst_1",
  "metadata": {
    "investigation_type": "manual"
  },
  "context": {
    "user_department": "fraud_analysis",
    "alert_source": "velocity_check",
    "case_priority": "high"
  },
  "notes": "Suspicious pattern detected"
}
```

**Context Field:**
The `context` field stores application-specific information that is persisted but not validated by the workflow engine. It's available for the integrating application's business logic.

**Response:**
```json
true
```

#### GET /api/entity_workflows
List workflow instances.

**Query Parameters:**
- `entity_table=eq.transactions` - Filter by entity table
- `entity_id=eq.12345` - Filter by entity ID
- `workflow_name=eq.fraud_detection` - Filter by workflow
- `current_state=eq.investigating` - Filter by current state
- `status=eq.active` - Filter by status (active/completed)
- `order=updated_at.desc` - Order results

**Response:**
```json
[
  {
    "id": "uuid",
    "entity_table": "transactions",
    "entity_id": "12345",
    "workflow_name": "fraud_detection",
    "workflow_version": "1.0",
    "current_state": "investigating",
    "current_state_metadata": {
      "display_name": "In Analisi",
      "color": "#blue"
    },
    "started_at": "2024-01-01T10:00:00Z",
    "updated_at": "2024-01-01T10:30:00Z",
    "completed_at": null,
    "status": "active",
    "metadata": {}
  }
]
```

#### GET /api/workflow_history
Get transition history for workflow instances.

**Query Parameters:**
- `entity_workflow_instance_id=eq.uuid` - Filter by instance ID

**Response:**
```json
[
  {
    "id": "uuid",
    "entity_workflow_instance_id": "uuid",
    "entity_table": "transactions",
    "entity_id": "12345",
    "workflow_name": "fraud_detection",
    "from_state": "new",
    "to_state": "investigating",
    "transition_name": "start_investigation",
    "executed_by": "security_analyst_1",
    "executed_at": "2024-01-01T10:30:00Z",
    "metadata": {},
    "notes": "Suspicious pattern detected"
  }
]
```

#### GET /rpc/get_transitions
Get possible transitions for a workflow instance with context information.

**Query Parameters:**
- `instance_id=uuid` - Workflow instance ID

**Response:**
```json
[
  {
    "transition_id": "uuid",
    "transition_name": "approve_transaction",
    "to_state_name": "approved",
    "to_state_metadata": {
      "display_name": "Approvato",
      "color": "#green"
    },
    "transition_context": {
      "authorized_manager_levels": ["senior_manager", "director"],
      "requires_approval_reason": true,
      "max_auto_approval_amount": 10000
    },
    "transition_conditions": {
      "requires_approval": true
    }
  }
]
```

**Context Information:**
Each transition includes its context information that provides guidance and configuration data for the integrating application. This data is informational only and not validated.

## Error Responses

All endpoints return standard HTTP status codes:

- `200 OK` - Success
- `400 Bad Request` - Invalid request
- `404 Not Found` - Resource not found
- `409 Conflict` - Invalid transition
- `500 Internal Server Error` - Server error

**Error Response Format:**
```json
{
  "code": "23505",
  "details": "Key (entity_table, entity_id, workflow_definition_id)=(transactions, 12345, uuid) already exists.",
  "hint": "Check if workflow is already started for this entity",
  "message": "duplicate key value violates unique constraint"
}
```

## PostgREST Features

PyPgFlow leverages PostgREST's powerful query capabilities:

### Filtering
```bash
# Exact match
GET /api/entity_workflows?workflow_name=eq.fraud_detection

# Pattern matching
GET /api/entity_workflows?entity_id=like.*123*

# Multiple conditions
GET /api/entity_workflows?status=eq.active&workflow_name=eq.fraud_detection
```

### Ordering
```bash
# Order by single column
GET /api/entity_workflows?order=updated_at.desc

# Order by multiple columns
GET /api/entity_workflows?order=workflow_name.asc,updated_at.desc
```

### Limiting and Pagination
```bash
# Limit results
GET /api/entity_workflows?limit=10

# Pagination with offset
GET /api/entity_workflows?limit=10&offset=20

# Range header for pagination
Range: 0-9
```

### Selecting Columns
```bash
# Select specific columns
GET /api/entity_workflows?select=id,entity_id,current_state,updated_at

# Select with renaming
GET /api/entity_workflows?select=id,entity:entity_id,state:current_state
```