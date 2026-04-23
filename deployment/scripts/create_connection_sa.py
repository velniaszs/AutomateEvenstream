"""
Create or Update Connections using Service Account (username/password) credentials
- MicrosoftOutlook connection (credentialType: Basic, service account stored in connection)
- Notebook connection (credentialType: ServicePrincipal, SP client ID/secret stored in connection)
- Uses ROPC flow (UsernamePasswordCredential) to authenticate to the Fabric API
- Lists connections to check if one with the same display name already exists
- If found: updates credentials (password may have changed)
- If not found: creates a new connection
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/create-connection
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/update-connection

NOTE: Requires MFA to be disabled for the service account and the account to be
excluded from Conditional Access policies that block ROPC flows.
"""

import argparse
import json
import os
import requests
from azure.identity import UsernamePasswordCredential

_FABRIC_API_BASE      = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE         = "https://api.fabric.microsoft.com/.default"
OUTLOOK_CONNECTION_TYPE  = "MicrosoftOutlook"
NOTEBOOK_CONNECTION_TYPE = "Notebook"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create or update a Fabric MicrosoftOutlook connection using a service account.")
    parser.add_argument("--client-id",        required=True,  help="App registration client ID (public client / ROPC enabled)")
    parser.add_argument("--tenant-id",        required=True,  help="Azure AD tenant ID")
    parser.add_argument("--sa-username",      required=True,  help="Service account UPN (caller identity)")
    parser.add_argument("--conn-sa-username",     required=True,  help="Mailbox/service account UPN (stored in the Outlook connection)")
    parser.add_argument("--sp-client-id",          required=True,  help="Service Principal client ID (stored in the Notebook connection)")
    parser.add_argument("--sp-tenant-id",          required=True,  help="Service Principal tenant ID (stored in the Notebook connection)")
    parser.add_argument("--outlook-display-name",  required=True,  help="Display name of the Outlook Fabric connection")
    parser.add_argument("--notebook-display-name", required=True,  help="Display name of the Notebook Fabric connection")
    return parser.parse_args()


def get_headers(args: argparse.Namespace) -> dict:
    credential = UsernamePasswordCredential(
        client_id=args.client_id,
        tenant_id=args.tenant_id,
        username=args.sa_username,
        password=os.environ["SA_PASSWORD"],
    )
    token = credential.get_token(_FABRIC_SCOPE).token
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def list_connections(headers: dict) -> list:
    url = f"{_FABRIC_API_BASE}v1/connections"
    results = []

    while url:
        response = requests.get(url, headers=headers)

        if response.status_code != 200:
            raise Exception(
                f"Failed to list connections: {response.status_code} - {response.text}"
            )

        data = response.json()
        results.extend(data.get("value", []))
        url = data.get("continuationUri")

    return results


def create_connection(display_name: str, connection_type: str, args: argparse.Namespace, headers: dict) -> dict:
    payload = {
        "connectivityType": "ShareableCloud",
        "displayName": display_name,
        "connectionDetails": {
            "type": connection_type,
            "creationMethod": f"{connection_type}.Actions",
            "parameters": [],
        },
        "privacyLevel": "Organizational" if connection_type == NOTEBOOK_CONNECTION_TYPE else "None",
        "credentialDetails": {
            "singleSignOnType": "None",
            "connectionEncryption": "NotEncrypted",
            "skipTestConnection": False,
            "credentials": _build_credentials(connection_type, args),
        },
        "allowConnectionUsageInGateway": connection_type == NOTEBOOK_CONNECTION_TYPE,
        "allowUsageInUserControlledCode": False,
    }

    url = f"{_FABRIC_API_BASE}v1/connections"
    response = requests.post(url, headers=headers, json=payload)

    if response.status_code == 201:
        return response.json()

    raise Exception(
        f"Failed to create connection: {response.status_code} - {response.text}"
    )


def _build_credentials(connection_type: str, args: argparse.Namespace) -> dict:
    if connection_type == NOTEBOOK_CONNECTION_TYPE:
        return {
            "credentialType": "ServicePrincipal",
            "tenantId": args.sp_tenant_id,
            "servicePrincipalClientId": args.sp_client_id,
            "servicePrincipalSecret": os.environ["SP_CLIENT_SECRET"],
        }
    return {
        "credentialType": "Basic",
        "username": args.conn_sa_username,
        "password": os.environ["CONN_SA_PASSWORD"],
    }


def update_connection(connection_id: str, connection_type: str, args: argparse.Namespace, headers: dict) -> dict:
    payload = {
        "connectivityType": "ShareableCloud",
        "credentialDetails": {
            "singleSignOnType": "None",
            "connectionEncryption": "NotEncrypted",
            "skipTestConnection": False,
            "credentials": _build_credentials(connection_type, args),
        },
    }

    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}"
    response = requests.patch(url, headers=headers, json=payload)

    if response.status_code == 200:
        return response.json()

    raise Exception(
        f"Failed to update connection '{connection_id}': {response.status_code} - {response.text}"
    )


def upsert_connection(display_name: str, connection_type: str, connections: list, args: argparse.Namespace, headers: dict) -> None:
    match = next((c for c in connections if c.get("displayName") == display_name), None)
    if match:
        print(f"Connection '{display_name}' already exists (id: {match['id']}). Updating credentials...")
        result = update_connection(match["id"], connection_type, args, headers)
        print(f"Updated. Connection ID: {result['id']}")
    else:
        print(f"Connection '{display_name}' not found. Creating...")
        result = create_connection(display_name, connection_type, args, headers)
        print(f"Created. Connection ID: {result['id']}")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    args = parse_args()
    headers = get_headers(args)

    print("Listing connections...")
    connections = list_connections(headers)

    print("\n--- Outlook Connection ---")
    upsert_connection(args.outlook_display_name, OUTLOOK_CONNECTION_TYPE, connections, args, headers)

    print("\n--- Notebook Connection ---")
    upsert_connection(args.notebook_display_name, NOTEBOOK_CONNECTION_TYPE, connections, args, headers)
