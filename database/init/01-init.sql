-- PyPgFlow Database Initialization
-- Multi-tenant workflow engine with PostgreSQL

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS api;

-- Set search path
SET search_path TO core, public;

-- Enable RLS for multi-tenancy
ALTER DATABASE pypgflow SET row_security = on;

-- Create tenant table
CREATE TABLE core.tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) UNIQUE NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for tenants
CREATE INDEX idx_tenants_slug ON core.tenants(slug);
CREATE INDEX idx_tenants_created_at ON core.tenants(created_at);

-- Create workflow definitions table
CREATE TABLE core.workflow_definitions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    version VARCHAR(50) NOT NULL,
    yaml_content TEXT NOT NULL,
    states JSONB NOT NULL,
    transitions JSONB NOT NULL DEFAULT '[]',
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tenant_id, name, version)
);

-- Create indexes for workflow_definitions
CREATE INDEX idx_workflow_definitions_tenant_id ON core.workflow_definitions(tenant_id);
CREATE INDEX idx_workflow_definitions_name ON core.workflow_definitions(name);
CREATE INDEX idx_workflow_definitions_active ON core.workflow_definitions(is_active);
CREATE INDEX idx_workflow_definitions_metadata ON core.workflow_definitions USING GIN(metadata);

-- Create workflow states table
CREATE TABLE core.workflow_states (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_definition_id UUID NOT NULL REFERENCES core.workflow_definitions(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    is_initial BOOLEAN DEFAULT FALSE,
    is_final BOOLEAN DEFAULT FALSE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(workflow_definition_id, name)
);

-- Create indexes for workflow_states
CREATE INDEX idx_workflow_states_workflow_definition_id ON core.workflow_states(workflow_definition_id);
CREATE INDEX idx_workflow_states_name ON core.workflow_states(name);
CREATE INDEX idx_workflow_states_initial ON core.workflow_states(is_initial);
CREATE INDEX idx_workflow_states_final ON core.workflow_states(is_final);

-- Create workflow transitions table
CREATE TABLE core.workflow_transitions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_definition_id UUID NOT NULL REFERENCES core.workflow_definitions(id) ON DELETE CASCADE,
    from_state_id UUID REFERENCES core.workflow_states(id) ON DELETE CASCADE,
    to_state_id UUID NOT NULL REFERENCES core.workflow_states(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    conditions JSONB DEFAULT '{}',
    context JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for workflow_transitions
CREATE INDEX idx_workflow_transitions_workflow_definition_id ON core.workflow_transitions(workflow_definition_id);
CREATE INDEX idx_workflow_transitions_from_state_id ON core.workflow_transitions(from_state_id);
CREATE INDEX idx_workflow_transitions_to_state_id ON core.workflow_transitions(to_state_id);
CREATE INDEX idx_workflow_transitions_name ON core.workflow_transitions(name);
CREATE INDEX idx_workflow_transitions_context ON core.workflow_transitions USING GIN(context);
CREATE INDEX idx_workflow_transitions_conditions ON core.workflow_transitions USING GIN(conditions);

-- Create entity workflow instances table (frontier table)
CREATE TABLE core.entity_workflow_instances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE,
    workflow_definition_id UUID NOT NULL REFERENCES core.workflow_definitions(id) ON DELETE CASCADE,
    entity_table VARCHAR(255) NOT NULL,
    entity_id VARCHAR(255) NOT NULL,
    current_state_id UUID NOT NULL REFERENCES core.workflow_states(id),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ NULL,
    metadata JSONB DEFAULT '{}',
    UNIQUE(tenant_id, entity_table, entity_id, workflow_definition_id)
);

-- Create indexes for entity_workflow_instances
CREATE INDEX idx_entity_workflow_instances_tenant_id ON core.entity_workflow_instances(tenant_id);
CREATE INDEX idx_entity_workflow_instances_workflow_definition_id ON core.entity_workflow_instances(workflow_definition_id);
CREATE INDEX idx_entity_workflow_instances_entity ON core.entity_workflow_instances(entity_table, entity_id);
CREATE INDEX idx_entity_workflow_instances_current_state_id ON core.entity_workflow_instances(current_state_id);
CREATE INDEX idx_entity_workflow_instances_updated_at ON core.entity_workflow_instances(updated_at);
CREATE INDEX idx_entity_workflow_instances_completed_at ON core.entity_workflow_instances(completed_at);

-- Create workflow transition history table (audit trail)
CREATE TABLE core.workflow_transition_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_workflow_instance_id UUID NOT NULL REFERENCES core.entity_workflow_instances(id) ON DELETE CASCADE,
    transition_id UUID REFERENCES core.workflow_transitions(id),
    from_state_id UUID REFERENCES core.workflow_states(id),
    to_state_id UUID NOT NULL REFERENCES core.workflow_states(id),
    executed_by VARCHAR(255),
    executed_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}',
    context JSONB DEFAULT '{}',
    notes TEXT
);

-- Create indexes for workflow_transition_history
CREATE INDEX idx_workflow_transition_history_instance_id ON core.workflow_transition_history(entity_workflow_instance_id);
CREATE INDEX idx_workflow_transition_history_transition_id ON core.workflow_transition_history(transition_id);
CREATE INDEX idx_workflow_transition_history_executed_at ON core.workflow_transition_history(executed_at);
CREATE INDEX idx_workflow_transition_history_executed_by ON core.workflow_transition_history(executed_by);
CREATE INDEX idx_workflow_transition_history_context ON core.workflow_transition_history USING GIN(context);

-- Create update timestamp trigger function
CREATE OR REPLACE FUNCTION core.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create update triggers
CREATE TRIGGER update_tenants_updated_at BEFORE UPDATE ON core.tenants FOR EACH ROW EXECUTE FUNCTION core.update_updated_at_column();
CREATE TRIGGER update_workflow_definitions_updated_at BEFORE UPDATE ON core.workflow_definitions FOR EACH ROW EXECUTE FUNCTION core.update_updated_at_column();
CREATE TRIGGER update_entity_workflow_instances_updated_at BEFORE UPDATE ON core.entity_workflow_instances FOR EACH ROW EXECUTE FUNCTION core.update_updated_at_column();

-- Row Level Security policies
ALTER TABLE core.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.workflow_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.workflow_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.workflow_transitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.entity_workflow_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.workflow_transition_history ENABLE ROW LEVEL SECURITY;

-- Create roles
CREATE ROLE anonymous;
CREATE ROLE authenticated;

-- Grant permissions
GRANT USAGE ON SCHEMA api TO anonymous, authenticated;
GRANT USAGE ON SCHEMA core TO authenticated;

-- Insert default tenant for development
INSERT INTO core.tenants (name, slug) VALUES ('Default Tenant', 'default');