"""
List Connection Role Assignments for a specific connection (by display name)
using a Service Principal credential.

https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connection-role-assignments
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections
"""

import argparse
import json
import os
import requests
from azure.identity import ClientSecretCredential

_FABRIC_API_BASE = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE    = "https://api.fabric.microsoft.com/.default"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="List role assignments for a Fabric connection (by display name) using a Service Principal."
    )
    parser.add_argument("--tenant-id",    required=True, help="Azure AD tenant ID")
    parser.add_argument("--client-id",    required=True, help="Service Principal client ID")
    parser.add_argument("--display-name", required=True, help="Display name of the Fabric connection (e.g. 'Notebook DEV')")
    return parser.parse_args()


def get_headers(args: argparse.Namespace) -> dict:
    credential = ClientSecretCredential(
        tenant_id=args.tenant_id,
        client_id=args.client_id,
        client_secret=os.environ["CLIENT_SECRET"],
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


def find_connection_id(connections: list, display_name: str) -> str:
    match = next((c for c in connections if c.get("displayName") == display_name), None)
    if not match:
        raise Exception(f"Connection '{display_name}' not found.")
    return match["id"]


def list_role_assignments(connection_id: str, headers: dict) -> list:
    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}/roleAssignments"
    results = []

    while url:
        response = requests.get(url, headers=headers)

        if response.status_code != 200:
            raise Exception(
                f"Failed to list role assignments: {response.status_code} - {response.text}"
            )

        data = response.json()
        results.extend(data.get("value", []))
        url = data.get("continuationUri")

    return results


if __name__ == "__main__":
    args = parse_args()
    headers = get_headers(args)

    print(f"Looking up connection '{args.display_name}'...")
    connections = list_connections(headers)
    connection_id = find_connection_id(connections, args.display_name)
    print(f"Found connection ID: {connection_id}")

    print(f"\nListing role assignments for '{args.display_name}'...")
    assignments = list_role_assignments(connection_id, headers)
    print(f"Total: {len(assignments)}")
    print(json.dumps(assignments, indent=2))
