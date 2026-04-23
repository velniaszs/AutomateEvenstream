"""
Create or Update Connections using Service Principal credentials
- MicrosoftOutlook connection (credentialType: ServicePrincipal)
- Notebook connection (credentialType: ServicePrincipal)
- Lists connections to check if one with the same display name already exists
- If found: updates credentials (client ID / secret may have changed)
- If not found: creates a new connection
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/create-connection
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/update-connection
"""

import json
import requests
from azure.identity import ClientSecretCredential

# --- Configuration (caller identity - used to authenticate to the API) ---
TENANT_ID = "9e929790-272d-4977-a2ab-301443c11ece"

# --- New connection settings ---
OUTLOOK_DISPLAY_NAME  = "TEST Detect Correct Outlook Conn"
NOTEBOOK_DISPLAY_NAME = "TEST Detect Correct Notebook Conn"

# Connection types
OUTLOOK_CONNECTION_TYPE  = "MicrosoftOutlook"
NOTEBOOK_CONNECTION_TYPE = "Notebook"

# Service Principal credentials to store in the connection
SP_TENANT_ID    = "9e929790-272d-4977-a2ab-301443c11ece"
SP_CLIENT_ID    = "b5c04c9c-0588-418f-8f60-2d83d38cb635"
SP_CLIENT_SECRET = ""
# -------------------------------------------------------------------------

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


def create_connection(display_name: str, connection_type: str, headers: dict) -> dict:
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
            "credentials": {
                "credentialType": "ServicePrincipal",
                "tenantId": SP_TENANT_ID,
                "servicePrincipalClientId": SP_CLIENT_ID,
                "servicePrincipalSecret": SP_CLIENT_SECRET,
            }
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


def update_connection(connection_id: str, headers: dict) -> dict:
    payload = {
        "connectivityType": "ShareableCloud",
        "credentialDetails": {
            "singleSignOnType": "None",
            "connectionEncryption": "NotEncrypted",
            "skipTestConnection": False,
            "credentials": {
                "credentialType": "ServicePrincipal",
                "tenantId": SP_TENANT_ID,
                "servicePrincipalClientId": SP_CLIENT_ID,
                "servicePrincipalSecret": SP_CLIENT_SECRET,
            }
        },
    }

    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}"
    response = requests.patch(url, headers=headers, json=payload)

    if response.status_code == 200:
        return response.json()

    raise Exception(
        f"Failed to update connection '{connection_id}': {response.status_code} - {response.text}"
    )


def upsert_connection(display_name: str, connection_type: str, connections: list, headers: dict) -> None:
    match = next((c for c in connections if c.get("displayName") == display_name), None)
    if match:
        print(f"Connection '{display_name}' already exists (id: {match['id']}). Updating credentials...")
        result = update_connection(match["id"], headers)
        print(f"Updated. Connection ID: {result['id']}")
    else:
        print(f"Connection '{display_name}' not found. Creating...")
        result = create_connection(display_name, connection_type, headers)
        print(f"Created. Connection ID: {result['id']}")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    headers = get_headers()

    print("Listing connections...")
    connections = list_connections(headers)

    print("\n--- Outlook Connection ---")
    upsert_connection(OUTLOOK_DISPLAY_NAME, OUTLOOK_CONNECTION_TYPE, connections, headers)

    print("\n--- Notebook Connection ---")
    upsert_connection(NOTEBOOK_DISPLAY_NAME, NOTEBOOK_CONNECTION_TYPE, connections, headers)

