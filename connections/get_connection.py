"""
Get Connection by ID
https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/get-connection
"""

import json
import requests
from azure.identity import InteractiveBrowserCredential

# --- Configuration ---
CONNECTION_ID = "371bdff8-1e2c-4a6a-9836-4494786f0b3e"
# ---------------------

_FABRIC_API_BASE = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE    = "https://api.fabric.microsoft.com/.default"


def get_connection(connection_id: str) -> dict:
    credential = InteractiveBrowserCredential()
    token = credential.get_token(_FABRIC_SCOPE).token
    headers = {"Authorization": f"Bearer {token}"}

    url = f"{_FABRIC_API_BASE}v1/connections/{connection_id}"
    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        return response.json()

    raise Exception(
        f"Failed to get connection: {response.status_code} - {response.text}"
    )


if __name__ == "__main__":
    connection = get_connection(CONNECTION_ID)
    print(json.dumps(connection, indent=2))
