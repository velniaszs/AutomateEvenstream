"""
Local Fabric Deployment Script
Runs the same deployment as deploy-fabric.yml but from your local machine.

Features:
  - Deploy Fabric items using fabric-cicd
  - Execute notebooks after deployment (like fabric-launcher)
  - Pass parameters to notebooks
  - Check notebook run status
  - Load configuration from variables/*.yml files

Usage:
  1. Set environment: python deploy-local.py --environment TEST
  2. Or use environment variable: set FABRIC_ENVIRONMENT=TEST && python deploy-local.py
  3. Or edit ENVIRONMENT variable below
"""

import subprocess
import sys
import os
import time
import json
import argparse
from pathlib import Path
from datetime import datetime

# ============================================================================
# CONFIGURATION
# ============================================================================

# Default environment (overridden by --environment flag or FABRIC_ENVIRONMENT env var)
ENVIRONMENT = os.getenv("FABRIC_ENVIRONMENT", "TEST")

# Service Principal credentials
# Best practice: Use environment variables or Azure Key Vault
TENANT_ID = os.getenv("FABRIC_TENANT_ID", "9e929790-272d-4977-a2ab-301443c11ece")
CLIENT_ID = os.getenv("FABRIC_CLIENT_ID", "b5c04c9c-0588-418f-8f60-2d83d38cb635")
CLIENT_SECRET = os.getenv("FABRIC_CLIENT_SECRET", "")

# Repository paths (will be overridden by variables/*.yml if specified)
FABRIC_REPO_PATH = r"c:\GIT\GIT\test_Fabric"
PIPELINE_REPO_PATH = r"c:\GIT\GIT\AutomateEvenstream"

# Repository paths (will be overridden by variables/*.yml if specified)
FABRIC_REPO_PATH = r"c:\GIT\GIT\test_Fabric"
PIPELINE_REPO_PATH = r"c:\GIT\GIT\AutomateEvenstream"

# Post-deployment notebook execution (optional)
# Similar to fabric-launcher's run_notebook() feature
POST_DEPLOYMENT_NOTEBOOKS = {
    "enabled": True,  # Set to True to run notebooks after deployment
    "notebooks": [
        # Example:
        {
            "name": "LoadOAP",
            # "parameters": {
            #     "environment": "ENVIRONMENT",  # Will be replaced with actual env
            #     "setup_permissions": True,
            #     "initialize_data": True
            # },
            "wait_for_completion": True,
            "timeout_seconds": 1000
        }
    ]
}

# ============================================================================

def load_variables_from_yaml(environment):
    """
    Load environment-specific variables from variables/{environment}-variables.yml
    
    Args:
        environment: Environment name (DEV, TEST, PROD)
        
    Returns:
        Dictionary of variables from the YAML file (keys converted to lowercase)
    """
    try:
        import yaml
    except ImportError:
        print("⚠️  PyYAML not installed. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml"], 
                            capture_output=True)
        import yaml
    
    # Variables file path
    script_dir = Path(__file__).parent
    variables_file = script_dir / "variables" / f"{environment.lower()}-variables.yml"
    
    if not variables_file.exists():
        print(f"⚠️  Variables file not found: {variables_file}")
        print(f"   Using default configuration")
        return {}
    
    print(f"📄 Loading variables from: {variables_file}")
    
    with open(variables_file, 'r') as f:
        yaml_content = yaml.safe_load(f)
    
    # Convert Azure DevOps YAML format to dictionary
    # Format: variables: [{"name": "key", "value": "val"}, ...]
    # Convert all keys to lowercase for consistency
    variables = {}
    
    if 'variables' in yaml_content:
        for var in yaml_content['variables']:
            if isinstance(var, dict) and 'name' in var and 'value' in var:
                # Convert key to lowercase
                key = var['name'].lower()
                variables[key] = var['value']
    
    print(f"✅ Loaded {len(variables)} variables from YAML")
    
    return variables


def get_configuration(environment):
    """
    Get configuration for the specified environment.
    
    Loads from variables/*.yml and merges with defaults.
    All variable names are converted to lowercase.
    
    Args:
        environment: Environment name (DEV, TEST, PROD)
        
    Returns:
        Dictionary with configuration values (lowercase keys)
    """
    # Load from YAML (keys already converted to lowercase)
    variables = load_variables_from_yaml(environment)
    
    # Build configuration with fallbacks
    config = {
        "environment": variables.get("environment", environment),
        "workspace_id": variables.get("workspaceid"),
        "workspace_name": variables.get("workspacename"),
        "fabric_repo_path": variables.get("fabricrepopath", FABRIC_REPO_PATH),
        "pipeline_repo_path": variables.get("pipelinerepopath", PIPELINE_REPO_PATH),
        # Add any other variables from YAML
        **{k: v for k, v in variables.items() 
           if k not in ["environment", "workspaceid", "workspacename", 
                       "fabricrepopath", "pipelinerepopath"]}
    }
    
    # Validate required fields
    if not config["workspace_id"]:
        raise ValueError(
            f"workspace_id not found in {environment.lower()}-variables.yml. "
            f"Please add 'workspaceId' to the variables file."
        )
    
    return config

# ============================================================================

def create_notebook_executor(workspace_id):
    """Create a notebook executor instance for running notebooks."""
    try:
        from notebook_executor import NotebookExecutor
        
        return NotebookExecutor(
            workspace_id=workspace_id,
            tenant_id=TENANT_ID,
            client_id=CLIENT_ID,
            client_secret=CLIENT_SECRET
        )
    except ImportError as e:
        print(f"❌ Error: {e}")
        print("   Install semantic-link-labs: pip install semantic-link-labs")
        raise


def run_post_deployment_notebooks(workspace_id, environment=None):
    """Execute post-deployment notebooks if configured."""
    if not POST_DEPLOYMENT_NOTEBOOKS.get("enabled", False):
        return
    
    notebooks = POST_DEPLOYMENT_NOTEBOOKS.get("notebooks", [])
    if not notebooks:
        return
    
    print("\n" + "=" * 70)
    print("POST-DEPLOYMENT NOTEBOOK EXECUTION")
    print("=" * 70)
    
    # Create notebook executor
    try:
        executor = create_notebook_executor(workspace_id)
    except Exception as e:
        print(f"❌ Failed to create notebook executor: {e}")
        print("⚠️  Skipping post-deployment notebook execution")
        return
    
    results = []
    
    for notebook_config in notebooks:
        notebook_name = notebook_config.get("name")
        parameters = notebook_config.get("parameters", {})
        wait = notebook_config.get("wait_for_completion", True)
        timeout = notebook_config.get("timeout_seconds", 300)
        
        # Replace ENVIRONMENT placeholder in parameters
        if parameters and environment:
            parameters = {
                k: environment if v == "ENVIRONMENT" else v
                for k, v in parameters.items()
            }
        
        try:
            if wait:
                # Run synchronously (waits for completion)
                result = executor.run_notebook_synchronous(
                    notebook_name=notebook_name,
                    parameters=parameters,
                    timeout_seconds=timeout
                )
            else:
                # Run asynchronously (fire and forget)
                result = executor.run_notebook(
                    notebook_name=notebook_name,
                    parameters=parameters,
                    timeout_seconds=timeout
                )
            
            results.append(result)
            
        except Exception as e:
            print(f"❌ Error executing {notebook_name}: {e}")
            results.append({
                "success": False,
                "notebook_name": notebook_name,
                "status": "Error",
                "error": str(e)
            })
    
    # Print summary
    print("\n📊 Post-Deployment Notebook Summary:")
    for result in results:
        status = result.get("status", "Unknown")
        success = result.get("success", False)
        
        if success or status == "Completed":
            status_icon = "✅"
        elif status in ["Failed", "Error"]:
            status_icon = "❌"
        else:
            status_icon = "⚠️"
            
        print(f"  {status_icon} {result.get('notebook_name', 'Unknown')}: {status}")
        if "error" in result:
            print(f"     Error: {result['error']}")
    
    print("=" * 70 + "\n")

# ============================================================================

def check_dependencies():
    """Check if required packages are installed."""
    required_packages = ["fabric_cicd", "azure.identity", "requests"]
    missing = []
    
    for package in required_packages:
        try:
            __import__(package)
        except ImportError:
            missing.append(package)
    
    if missing:
        print(f"⚠️  Missing packages: {', '.join(missing)}")
        print("Installing required packages...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "fabric-cicd", "azure-identity", "requests"])
        print("✓ Packages installed successfully\n")
    
    # Check for optional semantic-link-labs (for notebook execution)
    if POST_DEPLOYMENT_NOTEBOOKS.get("enabled", False):
        try:
            __import__("sempy.fabric")
        except ImportError:
            print("⚠️  semantic-link-labs not installed (required for notebook execution)")
            print("Installing semantic-link-labs...")
            subprocess.check_call([sys.executable, "-m", "pip", "install", "semantic-link-labs"])
            print("✓ semantic-link-labs installed successfully\n")

def deploy_fabric(environment):
    """Run the fabric-cicd deployment."""
    
    # Load configuration from YAML
    try:
        config = get_configuration(environment)
    except Exception as e:
        print(f"❌ Error loading configuration: {e}")
        sys.exit(1)
    
    # Validate configuration
    if CLIENT_SECRET == "your-client-secret-here" or not CLIENT_SECRET:
        print("❌ Error: CLIENT_SECRET not configured")
        print("   Set environment variable: FABRIC_CLIENT_SECRET")
        print("   Or edit CLIENT_SECRET in this script")
        sys.exit(1)
    
    workspace_id = config["workspace_id"]
    workspace_name = config.get("workspace_name", "Unknown")
    fabric_repo = Path(config["fabric_repo_path"])
    pipeline_repo = Path(config["pipeline_repo_path"])
    
    # Validate paths
    if not fabric_repo.exists():
        print(f"❌ Error: Fabric repository path does not exist: {fabric_repo}")
        sys.exit(1)
    
    fabric_cicd_script = pipeline_repo / "deployment" / "fabric-cicd.py"
    if not fabric_cicd_script.exists():
        print(f"❌ Error: fabric-cicd.py not found at: {fabric_cicd_script}")
        sys.exit(1)
    
    print(f"==> Deploying to {environment} Environment")
    print(f"    Workspace: {workspace_name}")
    print(f"    Workspace ID: {workspace_id}")
    print(f"    Fabric Repo: {fabric_repo}")
    print(f"    Client ID: {CLIENT_ID}")
    print(f"    Tenant ID: {TENANT_ID}\n")
    
    # Run fabric-cicd.py
    cmd = [
        sys.executable,
        str(fabric_cicd_script),
        "--client-id", CLIENT_ID,
        "--client-secret", CLIENT_SECRET,
        "--tenant-id", TENANT_ID,
        "--workspace-id", workspace_id,
        "--environment", environment,
        "--repository-path", str(fabric_repo)
    ]
    
    print(f"Running deployment...\n")
    result = subprocess.run(cmd, capture_output=False, text=True)
    
    if result.returncode == 0:
        print(f"\n✓ Deployment to {environment} completed successfully!")
        return workspace_id  # Return workspace_id for post-deployment tasks
    else:
        print(f"\n❌ Deployment failed with exit code {result.returncode}")
        sys.exit(result.returncode)

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description='Deploy Fabric items using configuration from variables/*.yml'
    )
    parser.add_argument(
        '--environment', '-e',
        default=ENVIRONMENT,
        choices=['DEV', 'TEST', 'PROD'],
        help=f'Target environment (default: {ENVIRONMENT})'
    )
    args = parser.parse_args()
    
    environment = args.environment.upper()
    
    print("=" * 70)
    print("Fabric Local Deployment Script")
    print("=" * 70)
    print(f"Target Environment: {environment}")
    print()
    
    # Check dependencies
    check_dependencies()
    
    # Run deployment
    workspace_id = deploy_fabric(environment)
    
    # Run post-deployment notebooks if configured
    run_post_deployment_notebooks(workspace_id, environment)

if __name__ == "__main__":
    main()
