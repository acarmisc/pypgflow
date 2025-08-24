"""
Database operations for PyPgFlow CLI
"""

import json
import uuid
from typing import Dict, Any, List, Optional
import psycopg2
import psycopg2.extras
from contextlib import contextmanager


class DatabaseManager:
    """Database manager for PyPgFlow operations"""
    
    def __init__(self, connection_url: str):
        self.connection_url = connection_url
        
    @contextmanager
    def get_connection(self):
        """Get database connection with context manager"""
        conn = None
        try:
            conn = psycopg2.connect(self.connection_url)
            conn.autocommit = False
            yield conn
        except Exception as e:
            if conn:
                conn.rollback()
            raise e
        finally:
            if conn:
                conn.close()
    
    def get_tenant_id(self, tenant_slug: str) -> Optional[str]:
        """Get tenant ID by slug"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    "SELECT id FROM core.tenants WHERE slug = %s",
                    (tenant_slug,)
                )
                result = cur.fetchone()
                return str(result['id']) if result else None
    
    def import_workflow(self, tenant_id: str, name: str, version: str, 
                       yaml_content: str, states: List[Dict[str, Any]], 
                       transitions: List[Dict[str, Any]] = None) -> str:
        """Import workflow definition into database"""
        if transitions is None:
            transitions = []
            
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT core.import_workflow(%s, %s, %s, %s, %s, %s)
                    """,
                    (tenant_id, name, version, yaml_content, json.dumps(states), json.dumps(transitions))
                )
                workflow_id = cur.fetchone()[0]
                conn.commit()
                return str(workflow_id)
    
    def list_workflows(self, tenant_slug: str) -> List[Dict[str, Any]]:
        """List all workflows for a tenant"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT wd.id, wd.name, wd.version, wd.is_active, 
                           wd.created_at, wd.updated_at, wd.metadata,
                           COUNT(ws.id) as states_count
                    FROM core.workflow_definitions wd
                    JOIN core.tenants t ON t.id = wd.tenant_id
                    LEFT JOIN core.workflow_states ws ON ws.workflow_definition_id = wd.id
                    WHERE t.slug = %s
                    GROUP BY wd.id, wd.name, wd.version, wd.is_active, 
                             wd.created_at, wd.updated_at, wd.metadata
                    ORDER BY wd.created_at DESC
                    """,
                    (tenant_slug,)
                )
                return [dict(row) for row in cur.fetchall()]
    
    def start_workflow_by_id(self, tenant_id: str, workflow_definition_id: str,
                            entity_table: str, entity_id: str, 
                            metadata: Dict[str, Any]) -> str:
        """Start workflow instance for entity using workflow ID"""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT core.start_entity_workflow(%s, %s, %s, %s, %s)
                    """,
                    (tenant_id, workflow_definition_id, entity_table, entity_id, 
                     json.dumps(metadata))
                )
                instance_id = cur.fetchone()[0]
                conn.commit()
                return str(instance_id)
    
    def start_workflow(self, tenant_id: str, workflow_name: str, 
                      entity_table: str, entity_id: str, 
                      metadata: Dict[str, Any]) -> str:
        """Start workflow instance for entity using workflow name (compatibility function)"""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT core.start_entity_workflow_by_name(%s, %s, %s, %s, %s)
                    """,
                    (tenant_id, workflow_name, entity_table, entity_id, 
                     json.dumps(metadata))
                )
                instance_id = cur.fetchone()[0]
                conn.commit()
                return str(instance_id)
    
    def list_instances(self, tenant_slug: str, entity_table: Optional[str] = None,
                      workflow_name: Optional[str] = None, 
                      state: Optional[str] = None, 
                      limit: int = 50) -> List[Dict[str, Any]]:
        """List workflow instances with optional filters"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                query = """
                    SELECT ewi.id, ewi.entity_table, ewi.entity_id,
                           wd.name as workflow_name, wd.version as workflow_version,
                           ws.name as current_state, ewi.started_at, ewi.updated_at,
                           ewi.completed_at, ewi.metadata,
                           CASE WHEN ws.is_final THEN 'completed' ELSE 'active' END as status
                    FROM core.entity_workflow_instances ewi
                    JOIN core.tenants t ON t.id = ewi.tenant_id
                    JOIN core.workflow_definitions wd ON wd.id = ewi.workflow_definition_id
                    JOIN core.workflow_states ws ON ws.id = ewi.current_state_id
                    WHERE t.slug = %s
                """
                params = [tenant_slug]
                
                if entity_table:
                    query += " AND ewi.entity_table = %s"
                    params.append(entity_table)
                
                if workflow_name:
                    query += " AND wd.name = %s"
                    params.append(workflow_name)
                
                if state:
                    query += " AND ws.name = %s"
                    params.append(state)
                
                query += " ORDER BY ewi.updated_at DESC LIMIT %s"
                params.append(limit)
                
                cur.execute(query, params)
                return [dict(row) for row in cur.fetchall()]
    
    def execute_transition(self, instance_id: str, to_state: str, 
                          executed_by: str, metadata: Dict[str, Any],
                          notes: Optional[str] = None, 
                          context: Dict[str, Any] = None) -> bool:
        """Execute workflow transition"""
        if context is None:
            context = {}
            
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT core.execute_workflow_transition(%s, %s, %s, %s, %s, %s)
                    """,
                    (instance_id, to_state, executed_by, json.dumps(metadata), notes, json.dumps(context))
                )
                result = cur.fetchone()[0]
                conn.commit()
                return result
    
    def get_history(self, instance_id: str) -> List[Dict[str, Any]]:
        """Get transition history for workflow instance"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT h.id, sf.name as from_state, st.name as to_state,
                           t.name as transition_name, h.executed_by, h.executed_at,
                           h.metadata, h.notes
                    FROM core.workflow_transition_history h
                    LEFT JOIN core.workflow_states sf ON sf.id = h.from_state_id
                    JOIN core.workflow_states st ON st.id = h.to_state_id
                    LEFT JOIN core.workflow_transitions t ON t.id = h.transition_id
                    WHERE h.entity_workflow_instance_id = %s
                    ORDER BY h.executed_at ASC
                    """,
                    (instance_id,)
                )
                return [dict(row) for row in cur.fetchall()]
    
    def get_possible_transitions(self, instance_id: str) -> List[Dict[str, Any]]:
        """Get possible transitions for workflow instance"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT * FROM core.get_possible_transitions(%s)
                    """,
                    (instance_id,)
                )
                return [dict(row) for row in cur.fetchall()]