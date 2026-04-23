"""
Add or update a user's role assignment on a connection
- Looks up connection by display name
- Lists role assignments to check if user already has one
- If found: updates the role (PATCH)
- If not found: adds a new role assignment (POST)
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connection-role-assignments
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/add-connection-role-assignment
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/update-connection-role-assignment
"""

import json
import requests
from azure.identity import ClientSecretCredential

# --- Service Principal credentials (caller identity) ---
SP_TENANT_ID     = "9e929790-272d-4977-a2ab-301443c11ece"
SP_CLIENT_ID     = "b5c04c9c-0588-418f-8f60-2d83d38cb635"
SP_CLIENT_SECRET = ""
# -------------------------------------------------------

# --- Target connection ---
CONNECTION_DISPLAY_NAME = "TEST Detect Correct Outlook Conn"

# --- User to assign ---
USER_ID = "03a65ab7-d0e9-4e6b-95cb-2de5bbb7ac43"
# Role options: "User", "UserWithReshare", "Owner"
USER_ROLE = "Owner"
# ----------------------

_FABRIC_API_BASE = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE    = "https://api.fabric.microsoft.com/.default"


def get_headers() -> dict:
    credential = ClientSecretCredential(
        tenant_id=SP_TENANT_ID,
        client_id=SP_CLIENT_ID,
        client_secret=SP_CLIENT_SECRET,
    )
    token = credential.get_token(_FABRIC_SCOPE).token
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def find_connection_by_name(display_name: str, headers: dict) -> dict:
    url = f"{_FABRIC_API_BASE}v1/connections"

    while url:
        response = requests.get(url, headers=headers)

        if response.status_code != 200:
            raise Exception(
                f"Failed to list connections: {response.status_code} - {response.text}"
            )

        data = response.json()
        match = next((c for c in data.get("value", []) if c.get("displayName") == display_name), None)
        if match:
            return match

        url = data.get("continuationUri")

    raise Exception(f"Connection '{display_name}' not found.")


def get_role_assignment(connection_id: str, user_id: str, headers: dict) -> dict | None:
    """Lists role assignments and returns the matching one for user_id, or None if not found."""
    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}/roleAssignments"

    while url:
        response = requests.get(url, headers=headers)

        if response.status_code != 200:
            raise Exception(
                f"Failed to list role assignments: {response.status_code} - {response.text}"
            )

        data = response.json()
        match = next(
            (r for r in data.get("value", []) if r.get("principal", {}).get("id") == user_id),
            None,
        )
        if match:
            return match

        url = data.get("continuationUri")

    return None


def update_role_assignment(connection_id: str, user_id: str, role: str, headers: dict) -> dict:
    """Updates an existing role assignment via PATCH."""
    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}/roleAssignments/{user_id}"
    payload = {"role": role}
    response = requests.patch(url, headers=headers, json=payload)

    if response.status_code == 200:
        return response.json()

    raise Exception(
        f"Failed to update role assignment: {response.status_code} - {response.text}"
    )


def add_role_assignment(connection_id: str, user_id: str, role: str, headers: dict) -> dict:
    """Creates a new role assignment via POST (add-connection-role-assignment)."""
    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}/roleAssignments"
    payload = {
        "role": role,
        "principal": {
            "id": user_id,
            "type": "User",
        },
    }
    response = requests.post(url, headers=headers, json=payload)

    if response.status_code == 201:
        return response.json()

    raise Exception(
        f"Failed to add role assignment: {response.status_code} - {response.text}"
    )


if __name__ == "__main__":
    headers = get_headers()

    print(f"Looking up connection '{CONNECTION_DISPLAY_NAME}'...")
    connection = find_connection_by_name(CONNECTION_DISPLAY_NAME, headers)
    connection_id = connection["id"]
    print(f"Found connection id: {connection_id}")

    print(f"Checking if user '{USER_ID}' already has a role assignment...")
    existing = get_role_assignment(connection_id, USER_ID, headers)

    if existing:
        print(f"Existing role: '{existing['role']}'. Updating to '{USER_ROLE}'...")
        result = update_role_assignment(connection_id, USER_ID, USER_ROLE, headers)
        print("Updated:")
    else:
        print(f"No existing role assignment found. Adding role '{USER_ROLE}'...")
        result = add_role_assignment(connection_id, USER_ID, USER_ROLE, headers)
        print("Added:")

    print(json.dumps(result, indent=2))
