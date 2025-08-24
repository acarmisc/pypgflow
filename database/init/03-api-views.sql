-- API Views for PostgREST

SET search_path TO api, core, public;

-- Workflow definitions view
CREATE OR REPLACE VIEW api.workflows AS
SELECT 
    wd.id,
    wd.name,
    wd.version,
    wd.metadata,
    wd.is_active,
    wd.created_at,
    wd.updated_at,
    json_agg(
        json_build_object(
            'id', ws.id,
            'name', ws.name,
            'is_initial', ws.is_initial,
            'is_final', ws.is_final,
            'metadata', ws.metadata
        ) ORDER BY ws.name
    ) as states
FROM core.workflow_definitions wd
LEFT JOIN core.workflow_states ws ON ws.workflow_definition_id = wd.id
WHERE wd.is_active = true
GROUP BY wd.id, wd.name, wd.version, wd.metadata, wd.is_active, wd.created_at, wd.updated_at;

-- Workflow states view
CREATE OR REPLACE VIEW api.workflow_states AS
SELECT 
    ws.id,
    wd.name as workflow_name,
    ws.name,
    ws.is_initial,
    ws.is_final,
    ws.metadata,
    ws.created_at
FROM core.workflow_states ws
JOIN core.workflow_definitions wd ON wd.id = ws.workflow_definition_id
WHERE wd.is_active = true;

-- Workflow transitions view
CREATE OR REPLACE VIEW api.workflow_transitions AS
SELECT 
    t.id,
    wd.name as workflow_name,
    sf.name as from_state,
    st.name as to_state,
    t.name as transition_name,
    t.conditions,
    t.context,
    t.metadata
FROM core.workflow_transitions t
JOIN core.workflow_definitions wd ON wd.id = t.workflow_definition_id
LEFT JOIN core.workflow_states sf ON sf.id = t.from_state_id
JOIN core.workflow_states st ON st.id = t.to_state_id
WHERE wd.is_active = true;

-- Entity workflow instances view
CREATE OR REPLACE VIEW api.entity_workflows AS
SELECT 
    ewi.id,
    ewi.entity_table,
    ewi.entity_id,
    wd.name as workflow_name,
    wd.version as workflow_version,
    ws.name as current_state,
    ws.metadata as current_state_metadata,
    ewi.started_at,
    ewi.updated_at,
    ewi.completed_at,
    ewi.metadata,
    CASE WHEN ws.is_final THEN 'completed' ELSE 'active' END as status
FROM core.entity_workflow_instances ewi
JOIN core.workflow_definitions wd ON wd.id = ewi.workflow_definition_id
JOIN core.workflow_states ws ON ws.id = ewi.current_state_id;

-- Workflow history view
CREATE OR REPLACE VIEW api.workflow_history AS
SELECT 
    h.id,
    h.entity_workflow_instance_id,
    ewi.entity_table,
    ewi.entity_id,
    wd.name as workflow_name,
    sf.name as from_state,
    st.name as to_state,
    t.name as transition_name,
    h.executed_by,
    h.executed_at,
    h.metadata,
    h.context,
    h.notes
FROM core.workflow_transition_history h
JOIN core.entity_workflow_instances ewi ON ewi.id = h.entity_workflow_instance_id
JOIN core.workflow_definitions wd ON wd.id = ewi.workflow_definition_id
LEFT JOIN core.workflow_states sf ON sf.id = h.from_state_id
JOIN core.workflow_states st ON st.id = h.to_state_id
LEFT JOIN core.workflow_transitions t ON t.id = h.transition_id
ORDER BY h.executed_at DESC;

-- Function wrappers for API endpoints

-- Start workflow by ID (main API function)
CREATE OR REPLACE FUNCTION api.start_workflow(
    workflow_definition_id UUID,
    entity_table TEXT,
    entity_id TEXT,
    metadata JSONB DEFAULT '{}'::jsonb
) RETURNS UUID AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    -- Get default tenant (in production, this would come from JWT or request context)
    SELECT id INTO v_tenant_id FROM core.tenants WHERE slug = 'default';
    
    RETURN core.start_entity_workflow(v_tenant_id, workflow_definition_id, entity_table, entity_id, metadata);
END;
$$ LANGUAGE plpgsql;

-- Start workflow by name (legacy compatibility)
CREATE OR REPLACE FUNCTION api.start_workflow_by_name(
    workflow_name TEXT,
    entity_table TEXT,
    entity_id TEXT,
    metadata JSONB DEFAULT '{}'::jsonb
) RETURNS UUID AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    -- Get default tenant (in production, this would come from JWT or request context)
    SELECT id INTO v_tenant_id FROM core.tenants WHERE slug = 'default';
    
    RETURN core.start_entity_workflow_by_name(v_tenant_id, workflow_name, entity_table, entity_id, metadata);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION api.execute_transition(
    instance_id UUID,
    to_state TEXT,
    executed_by TEXT DEFAULT 'api_user',
    metadata JSONB DEFAULT '{}'::jsonb,
    notes TEXT DEFAULT NULL,
    context JSONB DEFAULT '{}'::jsonb
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN core.execute_workflow_transition(instance_id, to_state, executed_by, metadata, notes, context);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION api.get_transitions(instance_id UUID)
RETURNS TABLE(
    transition_id UUID,
    transition_name VARCHAR,
    to_state_name VARCHAR,
    to_state_metadata JSONB,
    transition_context JSONB,
    transition_conditions JSONB
) AS $$
BEGIN
    RETURN QUERY SELECT * FROM core.get_possible_transitions(instance_id);
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT SELECT ON api.workflows TO anonymous, authenticated;
GRANT SELECT ON api.workflow_states TO anonymous, authenticated;
GRANT SELECT ON api.workflow_transitions TO anonymous, authenticated;
GRANT SELECT ON api.entity_workflows TO anonymous, authenticated;
GRANT SELECT ON api.workflow_history TO anonymous, authenticated;

GRANT EXECUTE ON FUNCTION api.start_workflow TO authenticated;
GRANT EXECUTE ON FUNCTION api.start_workflow_by_name TO authenticated;
GRANT EXECUTE ON FUNCTION api.execute_transition TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_transitions TO authenticated;