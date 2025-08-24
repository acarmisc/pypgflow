-- PostgreSQL Functions for PyPgFlow API

SET search_path TO core, api, public;

-- Function to import workflow from YAML
CREATE OR REPLACE FUNCTION core.import_workflow(
    p_tenant_id UUID,
    p_name VARCHAR,
    p_version VARCHAR,
    p_yaml_content TEXT,
    p_states JSONB,
    p_transitions JSONB DEFAULT '[]'::jsonb
) RETURNS UUID AS $$
DECLARE
    v_workflow_id UUID;
    v_state JSONB;
    v_state_id UUID;
    v_initial_state_id UUID;
BEGIN
    -- Insert workflow definition
    INSERT INTO core.workflow_definitions (tenant_id, name, version, yaml_content, states)
    VALUES (p_tenant_id, p_name, p_version, p_yaml_content, p_states)
    RETURNING id INTO v_workflow_id;
    
    -- Insert states
    FOR v_state IN SELECT * FROM jsonb_array_elements(p_states)
    LOOP
        INSERT INTO core.workflow_states (
            workflow_definition_id, 
            name, 
            is_initial, 
            is_final, 
            metadata
        )
        VALUES (
            v_workflow_id,
            v_state->>'name',
            COALESCE((v_state->>'initial')::boolean, false),
            COALESCE((v_state->>'final')::boolean, false),
            COALESCE(v_state->'metadata', '{}'::jsonb)
        )
        RETURNING id INTO v_state_id;
        
        -- Store initial state ID for later use
        IF COALESCE((v_state->>'initial')::boolean, false) THEN
            v_initial_state_id := v_state_id;
        END IF;
    END LOOP;
    
    -- Process transitions from YAML
    IF jsonb_array_length(p_transitions) > 0 THEN
        -- Insert transitions defined in YAML
        INSERT INTO core.workflow_transitions (
            workflow_definition_id, 
            from_state_id, 
            to_state_id, 
            name, 
            conditions, 
            context, 
            metadata
        )
        SELECT 
            v_workflow_id,
            CASE 
                WHEN (transition->>'from') = '*' THEN NULL  -- wildcard transitions
                ELSE (SELECT id FROM core.workflow_states WHERE workflow_definition_id = v_workflow_id AND name = (transition->>'from'))
            END as from_state_id,
            (SELECT id FROM core.workflow_states WHERE workflow_definition_id = v_workflow_id AND name = (transition->>'to')) as to_state_id,
            transition->>'name',
            COALESCE(transition->'conditions', '{}'::jsonb),
            COALESCE(transition->'context', '{}'::jsonb),
            COALESCE(transition->'metadata', '{}'::jsonb)
        FROM jsonb_array_elements(p_transitions) AS transition;
    ELSE
        -- Auto-generate basic transitions (fallback if no transitions defined in YAML)
        INSERT INTO core.workflow_transitions (workflow_definition_id, from_state_id, to_state_id, name)
        SELECT 
            v_workflow_id,
            s1.id as from_state_id,
            s2.id as to_state_id,
            'transition_to_' || s2.name as name
        FROM core.workflow_states s1
        CROSS JOIN core.workflow_states s2
        WHERE s1.workflow_definition_id = v_workflow_id
        AND s2.workflow_definition_id = v_workflow_id
        AND s1.id != s2.id
        AND NOT s1.is_final;  -- Can't transition from final states
    END IF;
    
    RETURN v_workflow_id;
END;
$$ LANGUAGE plpgsql;

-- Function to start workflow for entity by workflow ID
CREATE OR REPLACE FUNCTION core.start_entity_workflow(
    p_tenant_id UUID,
    p_workflow_definition_id UUID,
    p_entity_table VARCHAR,
    p_entity_id VARCHAR,
    p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS UUID AS $$
DECLARE
    v_initial_state_id UUID;
    v_instance_id UUID;
BEGIN
    -- Verify workflow exists and belongs to tenant
    IF NOT EXISTS (
        SELECT 1 FROM core.workflow_definitions 
        WHERE id = p_workflow_definition_id 
        AND tenant_id = p_tenant_id 
        AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Workflow % not found for tenant % or is not active', p_workflow_definition_id, p_tenant_id;
    END IF;
    
    -- Get initial state
    SELECT id INTO v_initial_state_id
    FROM core.workflow_states
    WHERE workflow_definition_id = p_workflow_definition_id
    AND is_initial = true
    LIMIT 1;
    
    IF v_initial_state_id IS NULL THEN
        RAISE EXCEPTION 'No initial state found for workflow %', p_workflow_definition_id;
    END IF;
    
    -- Create workflow instance
    INSERT INTO core.entity_workflow_instances (
        tenant_id,
        workflow_definition_id,
        entity_table,
        entity_id,
        current_state_id,
        metadata
    )
    VALUES (
        p_tenant_id,
        p_workflow_definition_id,
        p_entity_table,
        p_entity_id,
        v_initial_state_id,
        p_metadata
    )
    RETURNING id INTO v_instance_id;
    
    -- Record initial transition
    INSERT INTO core.workflow_transition_history (
        entity_workflow_instance_id,
        from_state_id,
        to_state_id,
        executed_by,
        metadata,
        notes
    )
    VALUES (
        v_instance_id,
        NULL,  -- No previous state
        v_initial_state_id,
        'system',
        '{"action": "workflow_started"}'::jsonb,
        'Workflow started'
    );
    
    RETURN v_instance_id;
END;
$$ LANGUAGE plpgsql;

-- Function to execute workflow transition
CREATE OR REPLACE FUNCTION core.execute_workflow_transition(
    p_instance_id UUID,
    p_to_state_name VARCHAR,
    p_executed_by VARCHAR DEFAULT 'system',
    p_metadata JSONB DEFAULT '{}'::jsonb,
    p_notes TEXT DEFAULT NULL,
    p_context JSONB DEFAULT '{}'::jsonb
) RETURNS BOOLEAN AS $$
DECLARE
    v_current_state_id UUID;
    v_to_state_id UUID;
    v_workflow_id UUID;
    v_transition_exists BOOLEAN;
BEGIN
    -- Get current instance info
    SELECT current_state_id, workflow_definition_id
    INTO v_current_state_id, v_workflow_id
    FROM core.entity_workflow_instances
    WHERE id = p_instance_id;
    
    IF v_current_state_id IS NULL THEN
        RAISE EXCEPTION 'Workflow instance % not found', p_instance_id;
    END IF;
    
    -- Get target state ID
    SELECT id INTO v_to_state_id
    FROM core.workflow_states
    WHERE workflow_definition_id = v_workflow_id
    AND name = p_to_state_name;
    
    IF v_to_state_id IS NULL THEN
        RAISE EXCEPTION 'State % not found in workflow', p_to_state_name;
    END IF;
    
    -- Check if transition is valid (no context validation needed)
    SELECT EXISTS(
        SELECT 1 FROM core.workflow_transitions t
        WHERE t.workflow_definition_id = v_workflow_id
        AND (t.from_state_id = v_current_state_id OR t.from_state_id IS NULL)
        AND t.to_state_id = v_to_state_id
    ) INTO v_transition_exists;
    
    IF NOT v_transition_exists THEN
        RAISE EXCEPTION 'Invalid transition from current state to %', p_to_state_name;
    END IF;
    
    -- Update instance current state
    UPDATE core.entity_workflow_instances
    SET current_state_id = v_to_state_id,
        updated_at = NOW(),
        completed_at = CASE 
            WHEN (SELECT is_final FROM core.workflow_states WHERE id = v_to_state_id) 
            THEN NOW() 
            ELSE completed_at 
        END
    WHERE id = p_instance_id;
    
    -- Record transition in history
    INSERT INTO core.workflow_transition_history (
        entity_workflow_instance_id,
        from_state_id,
        to_state_id,
        executed_by,
        metadata,
        context,
        notes
    )
    VALUES (
        p_instance_id,
        v_current_state_id,
        v_to_state_id,
        p_executed_by,
        p_metadata,
        p_context,
        p_notes
    );
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to get possible transitions for current state
CREATE OR REPLACE FUNCTION core.get_possible_transitions(p_instance_id UUID)
RETURNS TABLE(
    transition_id UUID,
    transition_name VARCHAR,
    to_state_name VARCHAR,
    to_state_metadata JSONB,
    transition_context JSONB,
    transition_conditions JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.id,
        t.name,
        s.name,
        s.metadata,
        t.context,
        t.conditions
    FROM core.entity_workflow_instances ewi
    JOIN core.workflow_transitions t ON t.workflow_definition_id = ewi.workflow_definition_id
    JOIN core.workflow_states s ON s.id = t.to_state_id
    WHERE ewi.id = p_instance_id
    AND (t.from_state_id = ewi.current_state_id OR t.from_state_id IS NULL);
END;
$$ LANGUAGE plpgsql;

-- Function to start workflow for entity by workflow name (helper function)
CREATE OR REPLACE FUNCTION core.start_entity_workflow_by_name(
    p_tenant_id UUID,
    p_workflow_name VARCHAR,
    p_entity_table VARCHAR,
    p_entity_id VARCHAR,
    p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS UUID AS $$
DECLARE
    v_workflow_id UUID;
BEGIN
    -- Get workflow definition ID by name
    SELECT id INTO v_workflow_id
    FROM core.workflow_definitions
    WHERE tenant_id = p_tenant_id 
    AND name = p_workflow_name 
    AND is_active = true
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_workflow_id IS NULL THEN
        RAISE EXCEPTION 'Workflow % not found for tenant %', p_workflow_name, p_tenant_id;
    END IF;
    
    -- Call the main function with workflow ID
    RETURN core.start_entity_workflow(p_tenant_id, v_workflow_id, p_entity_table, p_entity_id, p_metadata);
END;
$$ LANGUAGE plpgsql;


-- Grant permissions to authenticated users
GRANT EXECUTE ON FUNCTION core.import_workflow TO authenticated;
GRANT EXECUTE ON FUNCTION core.start_entity_workflow TO authenticated;
GRANT EXECUTE ON FUNCTION core.start_entity_workflow_by_name TO authenticated;
GRANT EXECUTE ON FUNCTION core.execute_workflow_transition TO authenticated;
GRANT EXECUTE ON FUNCTION core.get_possible_transitions TO authenticated;