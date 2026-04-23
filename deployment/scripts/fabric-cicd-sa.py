# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""
Deploy Fabric items using fabric-cicd authenticated with a Service Account (ROPC flow).
Passwords are read from environment variables; other parameters are passed as CLI arguments.

NOTE: Requires MFA to be disabled for the service account and the account to be
excluded from Conditional Access policies that block ROPC flows.
"""

import argparse
import os
from azure.identity import UsernamePasswordCredential

from fabric_cicd import FabricWorkspace, publish_all_items, unpublish_all_orphan_items

parser = argparse.ArgumentParser(description='Deploy Fabric items using fabric-cicd with a service account')
parser.add_argument('--client-id',        required=True, help='App registration client ID (public client / ROPC enabled)')
parser.add_argument('--tenant-id',        required=True, help='Azure AD Tenant ID')
parser.add_argument('--sa-username',      required=True, help='Service account UPN')
parser.add_argument('--workspace-id',     required=True, help='Fabric Workspace ID')
parser.add_argument('--environment',      default='DEV', help='Deployment environment (DEV, TEST, PROD)')
parser.add_argument('--repository-path',  default='workspace', help='Path to repository with Fabric workspace items')
args = parser.parse_args()

sa_password = os.environ['SA_PASSWORD']  # injected from Key Vault in pipeline

token_credential = UsernamePasswordCredential(
    client_id=args.client_id,
    tenant_id=args.tenant_id,
    username=args.sa_username,
    password=sa_password,
)

workspace_id       = args.workspace_id
environment        = args.environment
repository_directory = args.repository_path
item_type_in_scope = ["Notebook", "Lakehouse", "DataPipeline", "Eventhouse", "KQLDatabase"]

print(f"==> Deploying Fabric items from: {repository_directory}")
print(f"    Environment: {environment}")
print(f"    Workspace ID: {workspace_id}")
print(f"    Service account: {args.sa_username}")

target_workspace = FabricWorkspace(
    workspace_id=workspace_id,
    environment=environment,
    repository_directory=repository_directory,
    item_type_in_scope=item_type_in_scope,
    token_credential=token_credential,
)

publish_all_items(target_workspace)
unpublish_all_orphan_items(target_workspace)
