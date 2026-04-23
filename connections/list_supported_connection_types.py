"""
List Supported Connection Types using Service Principal credentials
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-supported-connection-types
"""

import json
import requests
from azure.identity import ClientSecretCredential

# --- Service Principal credentials ---
SP_TENANT_ID     = "9e929790-272d-4977-a2ab-301443c11ece"
SP_CLIENT_ID     = "b5c04c9c-0588-418f-8f60-2d83d38cb635"
SP_CLIENT_SECRET = ""
# -------------------------------------

_FABRIC_API_BASE = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE    = "https://api.fabric.microsoft.com/.default"


def list_supported_connection_types() -> list:
    credential = ClientSecretCredential(
        tenant_id=SP_TENANT_ID,
        client_id=SP_CLIENT_ID,
        client_secret=SP_CLIENT_SECRET,
    )
    token = credential.get_token(_FABRIC_SCOPE).token
    headers = {"Authorization": f"Bearer {token}"}

    url = f"{_FABRIC_API_BASE}v1/connections/supportedConnectionTypes"
    results = []

    while url:
        response = requests.get(url, headers=headers)

        if response.status_code != 200:
            raise Exception(
                f"Failed to list supported connection types: {response.status_code} - {response.text}"
            )

        data = response.json()
        results.extend(data.get("value", []))
        url = data.get("continuationUri")

    return results


OUTPUT_FILE = "connections/supported_connection_types.json"

if __name__ == "__main__":
    connection_types = list_supported_connection_types()
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(connection_types, f, indent=2)
    print(f"Saved {len(connection_types)} supported connection types to {OUTPUT_FILE}")
