"""
Data models for PyPgFlow CLI
"""

from typing import List, Dict, Any, Optional
from dataclasses import dataclass, field
from pydantic import BaseModel, Field


@dataclass
class WorkflowState:
    """Workflow state definition"""
    name: str
    initial: bool = False
    final: bool = False
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'WorkflowState':
        return cls(
            name=data['name'],
            initial=data.get('initial', False),
            final=data.get('final', False),
            metadata=data.get('metadata', {})
        )


@dataclass
class WorkflowTransition:
    """Workflow transition definition"""
    from_state: Optional[str]
    to_state: str
    name: str
    conditions: Dict[str, Any] = field(default_factory=dict)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class WorkflowDefinition:
    """Complete workflow definition"""
    name: str
    version: str
    states: List[WorkflowState]
    transitions: List[WorkflowTransition] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    @classmethod
    def from_yaml(cls, yaml_data: Dict[str, Any]) -> 'WorkflowDefinition':
        """Create WorkflowDefinition from YAML data"""
        workflow_info = yaml_data.get('workflow', {})
        
        # Parse states
        states = []
        states_data = yaml_data.get('states', [])
        
        for state_data in states_data:
            states.append(WorkflowState.from_dict(state_data))
        
        # Parse transitions (if provided)
        transitions = []
        transitions_data = yaml_data.get('transitions', [])
        
        for trans_data in transitions_data:
            transitions.append(WorkflowTransition(
                from_state=trans_data.get('from'),
                to_state=trans_data['to'],
                name=trans_data.get('name', f"to_{trans_data['to']}"),
                conditions=trans_data.get('conditions', {}),
                metadata=trans_data.get('metadata', {})
            ))
        
        return cls(
            name=workflow_info['name'],
            version=workflow_info['version'],
            states=states,
            transitions=transitions,
            metadata=workflow_info.get('metadata', {})
        )
    
    def validate(self) -> List[str]:
        """Validate workflow definition and return list of errors"""
        errors = []
        
        # Check that we have states
        if not self.states:
            errors.append("Workflow must have at least one state")
            return errors
        
        # Check for exactly one initial state
        initial_states = [s for s in self.states if s.initial]
        if len(initial_states) != 1:
            errors.append("Workflow must have exactly one initial state")
        
        # Check for at least one final state
        final_states = [s for s in self.states if s.final]
        if len(final_states) == 0:
            errors.append("Workflow must have at least one final state")
        
        # Check for duplicate state names
        state_names = [s.name for s in self.states]
        if len(state_names) != len(set(state_names)):
            errors.append("State names must be unique")
        
        # Validate transitions
        state_name_set = set(state_names)
        for transition in self.transitions:
            if transition.from_state and transition.from_state not in state_name_set:
                errors.append(f"Transition references unknown from_state: {transition.from_state}")
            if transition.to_state not in state_name_set:
                errors.append(f"Transition references unknown to_state: {transition.to_state}")
        
        return errors
    
    def to_json(self) -> Dict[str, Any]:
        """Convert to JSON-serializable format for database storage"""
        return {
            'name': self.name,
            'version': self.version,
            'states': [
                {
                    'name': state.name,
                    'initial': state.initial,
                    'final': state.final,
                    'metadata': state.metadata
                }
                for state in self.states
            ],
            'transitions': [
                {
                    'from_state': trans.from_state,
                    'to_state': trans.to_state,
                    'name': trans.name,
                    'conditions': trans.conditions,
                    'metadata': trans.metadata
                }
                for trans in self.transitions
            ],
            'metadata': self.metadata
        }


class WorkflowInstance(BaseModel):
    """Workflow instance model"""
    id: str
    workflow_name: str
    workflow_version: str
    entity_table: str
    entity_id: str
    current_state: str
    status: str
    started_at: str
    updated_at: str
    completed_at: Optional[str] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)


class TransitionHistory(BaseModel):
    """Workflow transition history model"""
    id: str
    from_state: Optional[str]
    to_state: str
    transition_name: Optional[str]
    executed_by: str
    executed_at: str
    metadata: Dict[str, Any] = Field(default_factory=dict)
    notes: Optional[str] = None