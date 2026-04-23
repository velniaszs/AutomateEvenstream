"""
Create or Update Connection using Service Principal credentials
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
DISPLAY_NAME = "TEST Detect Correct Outlook Conn"

# Connection details (based on existing connection in output.json)
CONNECTION_TYPE = "MicrosoftOutlook"

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


def create_connection(headers: dict) -> dict:
    payload = {
        "connectivityType": "ShareableCloud",
        "displayName": DISPLAY_NAME,
        "connectionDetails": {
            "type": CONNECTION_TYPE,
            "creationMethod": "MicrosoftOutlook.Actions",
            "parameters": [],
        },
        "privacyLevel": "None",
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
        "allowConnectionUsageInGateway": False,
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


if __name__ == "__main__":
    headers = get_headers()

    print(f"Listing connections...")
    connections = list_connections(headers)
    match = next((c for c in connections if c.get("displayName") == DISPLAY_NAME), None)

    if match:
        print(f"Connection '{DISPLAY_NAME}' already exists (id: {match['id']}). Updating credentials...")
        result = update_connection(match["id"], headers)
        print("Updated:")
    else:
        print(f"Connection '{DISPLAY_NAME}' not found. Creating...")
        result = create_connection(headers)
        print("Created:")

    print(json.dumps(result, indent=2))

