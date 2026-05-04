"""
Add a User as Owner to a Fabric Connection (by display name) using a Service Principal.
- Lists role assignments for the connection
- If the principal is not present (or has a different role), adds an Owner role assignment
- Idempotent: skips if already assigned as Owner

https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connection-role-assignments
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/add-connection-role-assignment
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections
"""

import argparse
import json
import os
import requests
from azure.identity import ClientSecretCredential

_FABRIC_API_BASE = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE    = "https://api.fabric.microsoft.com/.default"
OWNER_ROLE       = "Owner"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Add a user as Owner to a Fabric connection (by display name) using a Service Principal."
    )
    parser.add_argument("--tenant-id",    required=True, help="Azure AD tenant ID")
    parser.add_argument("--client-id",    required=True, help="Service Principal client ID")
    parser.add_argument("--display-name", required=True, help="Display name of the Fabric connection (e.g. 'Notebook DEV')")
    parser.add_argument("--principal-id", required=True, help="Object ID (Entra ID) of the user/SP/group to add as Owner")
    parser.add_argument("--principal-type", default="User",
                        choices=["User", "Group", "ServicePrincipal"],
                        help="Type of principal (default: User)")
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


def find_assignment(assignments: list, principal_id: str) -> dict:
    return next(
        (a for a in assignments if a.get("principal", {}).get("id") == principal_id),
        None,
    )


def add_role_assignment(connection_id: str, principal_id: str, principal_type: str, headers: dict) -> dict:
    payload = {
        "principal": {
            "id": principal_id,
            "type": principal_type,
        },
        "role": OWNER_ROLE,
    }

    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}/roleAssignments"
    response = requests.post(url, headers=headers, json=payload)

    if response.status_code in (200, 201):
        return response.json()

    raise Exception(
        f"Failed to add role assignment: {response.status_code} - {response.text}"
    )


if __name__ == "__main__":
    args = parse_args()
    headers = get_headers(args)

    print(f"Looking up connection '{args.display_name}'...")
    connections = list_connections(headers)
    connection_id = find_connection_id(connections, args.display_name)
    print(f"Found connection ID: {connection_id}")

    print(f"\nListing role assignments...")
    assignments = list_role_assignments(connection_id, headers)
    print(f"Existing assignments: {len(assignments)}")

    existing = find_assignment(assignments, args.principal_id)
    if existing and existing.get("role") == OWNER_ROLE:
        print(f"Principal '{args.principal_id}' is already Owner. Nothing to do.")
    elif existing:
        print(
            f"Principal '{args.principal_id}' has role '{existing.get('role')}', not '{OWNER_ROLE}'. "
            f"The API does not support changing roles via add; adjust manually if needed."
        )
    else:
        print(f"Principal '{args.principal_id}' not found. Adding as Owner...")
        result = add_role_assignment(connection_id, args.principal_id, args.principal_type, headers)
        print("Added.")
        print(json.dumps(result, indent=2))
