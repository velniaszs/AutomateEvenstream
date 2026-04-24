# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""
Example of authenticating with SPN + Secret
Can be expanded to retrieve values from Key Vault or other sources
"""

import argparse
import os
from azure.identity import ClientSecretCredential

from fabric_cicd import FabricWorkspace, publish_all_items, unpublish_all_orphan_items

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Deploy Fabric items using fabric-cicd')
parser.add_argument('--client-id', required=True, help='Azure AD Application (Client) ID')
parser.add_argument('--tenant-id', required=True, help='Azure AD Tenant ID')
parser.add_argument('--workspace-id', required=True, help='Fabric Workspace ID')
parser.add_argument('--environment', default='Dev', help='Deployment environment (Dev, Test, Prod)')
parser.add_argument('--repository-path', default='workspace', help='Path to repository with Fabric workspace items')

args = parser.parse_args()

# Authentication credentials
client_id = args.client_id
client_secret = os.environ["CLIENT_SECRET"]
tenant_id = args.tenant_id
token_credential = ClientSecretCredential(client_id=client_id, client_secret=client_secret, tenant_id=tenant_id)

# Deployment parameters
workspace_id = args.workspace_id
environment = args.environment
repository_directory = args.repository_path
item_type_in_scope = ["Notebook", "Lakehouse", "DataPipeline", "Eventhouse", "KQLDatabase"]

print(f"==> Deploying Fabric items from: {repository_directory}")
print(f"    Environment: {environment}")
print(f"    Workspace ID: {workspace_id}")

# Initialize the FabricWorkspace object with the required parameters
target_workspace = FabricWorkspace(
    workspace_id=workspace_id,
    environment=environment,
    repository_directory=repository_directory,
    item_type_in_scope=item_type_in_scope,
    token_credential=token_credential,
)

# Publish all items defined in item_type_in_scope
publish_all_items(target_workspace)

# Unpublish all items defined in item_type_in_scope not found in repository
unpublish_all_orphan_items(target_workspace)