"""
Create or Update Connection using Service Account (username/password) credentials
- Uses ROPC flow (UsernamePasswordCredential) to authenticate to the Fabric API
- Lists connections to check if one with the same display name already exists
- If found: updates credentials (password may have changed)
- If not found: creates a new connection with OAuth2 credential type
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

_FABRIC_API_BASE  = "https://api.fabric.microsoft.com/"
_FABRIC_SCOPE     = "https://api.fabric.microsoft.com/.default"
CONNECTION_TYPE   = "MicrosoftOutlook"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create or update a Fabric MicrosoftOutlook connection using a service account.")
    parser.add_argument("--client-id",        required=True,  help="App registration client ID (public client / ROPC enabled)")
    parser.add_argument("--tenant-id",        required=True,  help="Azure AD tenant ID")
    parser.add_argument("--sa-username",      required=True,  help="Service account UPN (caller identity)")
    parser.add_argument("--conn-sa-username", required=True,  help="Mailbox account UPN (stored in the connection)")
    parser.add_argument("--display-name",     required=True,  help="Display name of the Fabric connection")
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


def create_connection(args: argparse.Namespace, headers: dict) -> dict:
    payload = {
        "connectivityType": "ShareableCloud",
        "displayName": args.display_name,
        "connectionDetails": {
            "type": CONNECTION_TYPE,
            "creationMethod": f"{CONNECTION_TYPE}.Actions",
            "parameters": [],
        },
        "privacyLevel": "None",
        "credentialDetails": {
            "singleSignOnType": "None",
            "connectionEncryption": "NotEncrypted",
            "skipTestConnection": False,
            "credentials": {
                "credentialType": "Basic",
                "username": args.conn_sa_username,
                "password": os.environ["CONN_SA_PASSWORD"],
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


def update_connection(connection_id: str, args: argparse.Namespace, headers: dict) -> dict:
    payload = {
        "connectivityType": "ShareableCloud",
        "credentialDetails": {
            "singleSignOnType": "None",
            "connectionEncryption": "NotEncrypted",
            "skipTestConnection": False,
            "credentials": {
                "credentialType": "Basic",
                "username": args.conn_sa_username,
                "password": os.environ["CONN_SA_PASSWORD"],
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
    args = parse_args()
    headers = get_headers(args)

    print("Listing connections...")
    connections = list_connections(headers)
    match = next((c for c in connections if c.get("displayName") == args.display_name), None)

    if match:
        print(f"Connection '{args.display_name}' already exists (id: {match['id']}). Updating credentials...")
        result = update_connection(match["id"], args, headers)
        print("Updated:")
    else:
        print(f"Connection '{args.display_name}' not found. Creating...")
        result = create_connection(args, headers)
        print("Created:")

    print(json.dumps(result, indent=2))
