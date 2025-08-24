#!/usr/bin/env python3
"""
PyPgFlow CLI - Multi-tenant workflow engine management tool
"""

import click
import yaml
import json
import os
from typing import Dict, Any, Optional
from pypgflow.database import DatabaseManager
from pypgflow.models import WorkflowDefinition


@click.group()
@click.option('--database-url', envvar='DATABASE_URL', 
              default='postgresql://pypgflow:pypgflow123@localhost:5432/pypgflow',
              help='PostgreSQL connection URL')
@click.pass_context
def cli(ctx, database_url):
    """PyPgFlow CLI - Multi-tenant workflow engine management"""
    ctx.ensure_object(dict)
    ctx.obj['db'] = DatabaseManager(database_url)


@cli.command()
@click.argument('yaml_file', type=click.Path(exists=True))
@click.option('--tenant-slug', default='default', help='Tenant slug')
@click.option('--dry-run', is_flag=True, help='Show what would be imported without executing')
@click.pass_context
def import_workflow(ctx, yaml_file: str, tenant_slug: str, dry_run: bool):
    """Import a workflow definition from YAML file"""
    db = ctx.obj['db']
    
    try:
        # Read and parse YAML file
        with open(yaml_file, 'r') as f:
            yaml_content = f.read()
            workflow_data = yaml.safe_load(yaml_content)
        
        # Validate workflow structure
        workflow = WorkflowDefinition.from_yaml(workflow_data)
        
        if dry_run:
            click.echo(f"Would import workflow: {workflow.name} v{workflow.version}")
            click.echo(f"States: {', '.join([s.name for s in workflow.states])}")
            click.echo(f"Tenant: {tenant_slug}")
            return
        
        # Get tenant ID
        tenant_id = db.get_tenant_id(tenant_slug)
        if not tenant_id:
            click.echo(f"Error: Tenant '{tenant_slug}' not found", err=True)
            return
        
        # Import workflow
        workflow_json = workflow.to_json()
        workflow_id = db.import_workflow(
            tenant_id=tenant_id,
            name=workflow.name,
            version=workflow.version,
            yaml_content=yaml_content,
            states=workflow_json['states'],
            transitions=workflow_json.get('transitions', [])
        )
        
        click.echo(f"✓ Imported workflow '{workflow.name}' v{workflow.version}")
        click.echo(f"  Workflow ID: {workflow_id}")
        click.echo(f"  States: {len(workflow.states)}")
        click.echo(f"  Tenant: {tenant_slug}")
        
    except Exception as e:
        click.echo(f"Error importing workflow: {e}", err=True)


@cli.command()
@click.option('--tenant-slug', default='default', help='Tenant slug')
@click.option('--format', 'output_format', type=click.Choice(['table', 'json']), default='table')
@click.pass_context
def list_workflows(ctx, tenant_slug: str, output_format: str):
    """List all workflow definitions"""
    db = ctx.obj['db']
    
    try:
        workflows = db.list_workflows(tenant_slug)
        
        if output_format == 'json':
            click.echo(json.dumps(workflows, indent=2, default=str))
        else:
            if not workflows:
                click.echo("No workflows found")
                return
                
            click.echo("WORKFLOWS")
            click.echo("-" * 60)
            for wf in workflows:
                click.echo(f"Name: {wf['name']} v{wf['version']}")
                click.echo(f"Active: {wf['is_active']}")
                click.echo(f"States: {len(wf.get('states', []))}")
                click.echo(f"Created: {wf['created_at']}")
                click.echo("-" * 60)
                
    except Exception as e:
        click.echo(f"Error listing workflows: {e}", err=True)


@cli.command()
@click.option('--entity-table', required=True, help='Entity table name')
@click.option('--entity-id', required=True, help='Entity ID')
@click.option('--workflow-name', help='Workflow name')
@click.option('--workflow-id', help='Workflow definition ID (UUID)')
@click.option('--tenant-slug', default='default', help='Tenant slug')
@click.option('--metadata', help='JSON metadata for the instance')
@click.pass_context
def start_workflow(ctx, entity_table: str, entity_id: str, workflow_name: Optional[str], 
                  workflow_id: Optional[str], tenant_slug: str, metadata: Optional[str]):
    """Start a workflow for an entity (specify either --workflow-name or --workflow-id)"""
    db = ctx.obj['db']
    
    try:
        # Validate input
        if not workflow_name and not workflow_id:
            click.echo("Error: Must specify either --workflow-name or --workflow-id", err=True)
            return
        
        if workflow_name and workflow_id:
            click.echo("Error: Cannot specify both --workflow-name and --workflow-id", err=True)
            return
        
        # Parse metadata if provided
        metadata_dict = {}
        if metadata:
            metadata_dict = json.loads(metadata)
        
        # Get tenant ID
        tenant_id = db.get_tenant_id(tenant_slug)
        if not tenant_id:
            click.echo(f"Error: Tenant '{tenant_slug}' not found", err=True)
            return
        
        # Start workflow
        if workflow_id:
            instance_id = db.start_workflow_by_id(
                tenant_id=tenant_id,
                workflow_definition_id=workflow_id,
                entity_table=entity_table,
                entity_id=entity_id,
                metadata=metadata_dict
            )
            click.echo(f"✓ Started workflow {workflow_id} for {entity_table}:{entity_id}")
        else:
            instance_id = db.start_workflow(
                tenant_id=tenant_id,
                workflow_name=workflow_name,
                entity_table=entity_table,
                entity_id=entity_id,
                metadata=metadata_dict
            )
            click.echo(f"✓ Started workflow '{workflow_name}' for {entity_table}:{entity_id}")
        
        click.echo(f"  Instance ID: {instance_id}")
        
    except Exception as e:
        click.echo(f"Error starting workflow: {e}", err=True)


@cli.command()
@click.option('--entity-table', help='Filter by entity table')
@click.option('--workflow-name', help='Filter by workflow name')
@click.option('--state', help='Filter by current state')
@click.option('--tenant-slug', default='default', help='Tenant slug')
@click.option('--format', 'output_format', type=click.Choice(['table', 'json']), default='table')
@click.option('--limit', type=int, default=50, help='Limit number of results')
@click.pass_context
def list_instances(ctx, entity_table: Optional[str], workflow_name: Optional[str], 
                  state: Optional[str], tenant_slug: str, output_format: str, limit: int):
    """List workflow instances"""
    db = ctx.obj['db']
    
    try:
        instances = db.list_instances(
            tenant_slug=tenant_slug,
            entity_table=entity_table,
            workflow_name=workflow_name,
            state=state,
            limit=limit
        )
        
        if output_format == 'json':
            click.echo(json.dumps(instances, indent=2, default=str))
        else:
            if not instances:
                click.echo("No workflow instances found")
                return
                
            click.echo("WORKFLOW INSTANCES")
            click.echo("-" * 80)
            for inst in instances:
                click.echo(f"ID: {inst['id']}")
                click.echo(f"Entity: {inst['entity_table']}:{inst['entity_id']}")
                click.echo(f"Workflow: {inst['workflow_name']} v{inst.get('workflow_version', 'N/A')}")
                click.echo(f"State: {inst['current_state']} ({inst['status']})")
                click.echo(f"Updated: {inst['updated_at']}")
                click.echo("-" * 80)
                
    except Exception as e:
        click.echo(f"Error listing instances: {e}", err=True)


@cli.command()
@click.argument('instance_id')
@click.argument('to_state')
@click.option('--executed-by', default='cli_user', help='User executing the transition')
@click.option('--metadata', help='JSON metadata for the transition')
@click.option('--context', help='JSON context for the transition validation')
@click.option('--notes', help='Notes for the transition')
@click.pass_context
def transition(ctx, instance_id: str, to_state: str, executed_by: str, 
               metadata: Optional[str], context: Optional[str], notes: Optional[str]):
    """Execute a workflow transition"""
    db = ctx.obj['db']
    
    try:
        # Parse metadata if provided
        metadata_dict = {}
        if metadata:
            metadata_dict = json.loads(metadata)
        
        # Parse context if provided
        context_dict = {}
        if context:
            context_dict = json.loads(context)
        
        # Execute transition
        success = db.execute_transition(
            instance_id=instance_id,
            to_state=to_state,
            executed_by=executed_by,
            metadata=metadata_dict,
            notes=notes,
            context=context_dict
        )
        
        if success:
            click.echo(f"✓ Transitioned instance {instance_id} to state '{to_state}'")
            if context_dict:
                click.echo(f"  Context: {json.dumps(context_dict, indent=2)}")
        else:
            click.echo(f"✗ Failed to transition instance {instance_id}", err=True)
            
    except Exception as e:
        click.echo(f"Error executing transition: {e}", err=True)


@cli.command()
@click.argument('instance_id')
@click.option('--format', 'output_format', type=click.Choice(['table', 'json']), default='table')
@click.pass_context
def history(ctx, instance_id: str, output_format: str):
    """Show workflow transition history for an instance"""
    db = ctx.obj['db']
    
    try:
        history_records = db.get_history(instance_id)
        
        if output_format == 'json':
            click.echo(json.dumps(history_records, indent=2, default=str))
        else:
            if not history_records:
                click.echo("No history found for this instance")
                return
                
            click.echo(f"TRANSITION HISTORY - Instance {instance_id}")
            click.echo("-" * 80)
            for record in history_records:
                from_state = record['from_state'] or 'START'
                click.echo(f"{record['executed_at']} | {from_state} → {record['to_state']}")
                click.echo(f"  By: {record['executed_by']}")
                if record['notes']:
                    click.echo(f"  Notes: {record['notes']}")
                click.echo()
                
    except Exception as e:
        click.echo(f"Error getting history: {e}", err=True)


if __name__ == '__main__':
    cli()