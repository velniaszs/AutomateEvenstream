"""
Update the Service Principal secret of an existing Fabric connection
- Looks up a connection by display name
- If not found: raises an error (this script never creates connections)
- If found: updates only the credentials, keeping every other credential
  setting (singleSignOnType, connectionEncryption, skipTestConnection)
  exactly as it is on the existing connection
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/get-connection
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/update-connection

NOTE: The Fabric API never returns stored secrets, so the new secret must be
supplied. It is read from the NEW_CLIENT_SECRET environment variable to avoid
exposing it in the process command line.
"""

import argparse
import json
import os
import requests
from azure.identity import ClientSecretCredential

_FABRIC_API_BASE = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE    = "https://api.fabric.microsoft.com/.default"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Update the Service Principal secret of an existing Fabric connection.")
    parser.add_argument("--tenant-id",       required=True, help="Azure AD tenant ID (used for API auth and the connection credential)")
    parser.add_argument("--client-id",       required=True, help="Service Principal client ID (used for API auth and the connection credential)")
    parser.add_argument("--connection-name", required=True, help="Display name of the connection whose secret should be updated")
    return parser.parse_args()


def get_headers(args: argparse.Namespace) -> dict:
    credential = ClientSecretCredential(
        tenant_id=args.tenant_id,
        client_id=args.client_id,
        client_secret=os.environ["NEW_CLIENT_SECRET"],
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


def find_connection(display_name: str, connections: list) -> dict:
    match = next((c for c in connections if c.get("displayName") == display_name), None)
    if not match:
        raise Exception(
            f"Connection '{display_name}' not found. This script only updates existing connections."
        )
    return match


def update_secret(connection: dict, args: argparse.Namespace, headers: dict) -> dict:
    existing = connection.get("credentialDetails") or {}

    credential_type = existing.get("credentialType")
    if credential_type != "ServicePrincipal":
        raise Exception(
            f"Connection '{connection.get('displayName')}' uses credential type "
            f"'{credential_type}', expected 'ServicePrincipal'."
        )

    payload = {
        "connectivityType": connection.get("connectivityType", "ShareableCloud"),
        "credentialDetails": {
            "singleSignOnType": existing.get("singleSignOnType", "None"),
            "connectionEncryption": existing.get("connectionEncryption", "NotEncrypted"),
            "skipTestConnection": existing.get("skipTestConnection", False),
            "credentials": {
                "credentialType": "ServicePrincipal",
                "tenantId": args.tenant_id,
                "servicePrincipalClientId": args.client_id,
                "servicePrincipalSecret": os.environ["NEW_CLIENT_SECRET"],
            },
        },
    }

    url = f"{_FABRIC_API_BASE}v1/connections/{connection['id']}"
    response = requests.patch(url, headers=headers, json=payload)

    if response.status_code == 200:
        return response.json()

    raise Exception(
        f"Failed to update connection '{connection['id']}': {response.status_code} - {response.text}"
    )


if __name__ == "__main__":
    args = parse_args()
    headers = get_headers(args)

    print("Listing connections...")
    connections = list_connections(headers)

    connection = find_connection(args.connection_name, connections)
    print(f"Connection '{args.connection_name}' found (id: {connection['id']}). Updating secret...")

    result = update_secret(connection, args, headers)
    print(f"Updated. Connection ID: {result['id']}")
    print(json.dumps(result, indent=2))
