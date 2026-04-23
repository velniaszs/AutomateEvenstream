"""
Delete Connection by Display Name using Service Principal credentials
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/delete-connection
"""

import json
import requests
from azure.identity import ClientSecretCredential

# --- Service Principal credentials ---
SP_TENANT_ID     = "9e929790-272d-4977-a2ab-301443c11ece"
SP_CLIENT_ID     = "b5c04c9c-0588-418f-8f60-2d83d38cb635"
SP_CLIENT_SECRET = ""
# -------------------------------------

# --- Name of the connection to delete ---
CONNECTION_DISPLAY_NAME = "MicrosoftOutlook SP connection"
# ----------------------------------------

_FABRIC_API_BASE = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE    = "https://api.fabric.microsoft.com/.default"


def get_headers() -> dict:
    credential = ClientSecretCredential(
        tenant_id=SP_TENANT_ID,
        client_id=SP_CLIENT_ID,
        client_secret=SP_CLIENT_SECRET,
    )
    token = credential.get_token(_FABRIC_SCOPE).token
    return {"Authorization": f"Bearer {token}"}


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


def delete_connection(connection_id: str, headers: dict) -> None:
    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}"
    response = requests.delete(url, headers=headers)

    if response.status_code != 200:
        raise Exception(
            f"Failed to delete connection '{connection_id}': {response.status_code} - {response.text}"
        )


if __name__ == "__main__":
    headers = get_headers()

    print(f"Listing connections...")
    connections = list_connections(headers)

    matches = [c for c in connections if c.get("displayName") == CONNECTION_DISPLAY_NAME]

    if not matches:
        print(f"No connection found with name: '{CONNECTION_DISPLAY_NAME}'")
    else:
        print(f"Found {len(matches)} connection(s) matching '{CONNECTION_DISPLAY_NAME}'")
        for conn in matches:
            conn_id = conn["id"]
            print(f"  Deleting '{conn['displayName']}' (id: {conn_id})...")
            delete_connection(conn_id, headers)
            print(f"  Deleted.")
