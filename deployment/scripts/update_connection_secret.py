"""
Update the Service Principal secret of an existing Power BI gateway data source.

The Fabric connections API is disabled in this tenant, so credential rotation is
done through the Power BI REST API (Gateways / Datasources) instead.

- Looks up a data source by name across the gateways the caller can administer
- If not found: raises an error (this script never creates data sources)
- If found: updates only the credentials with the new client secret

Power BI has no "ServicePrincipal" credential type on a gateway data source. A
service principal sign-in (client id + secret) is stored as a "Basic" credential
where the username is the service principal client/app id and the password is the
secret. See the credential-types reference below.

https://learn.microsoft.com/en-us/rest/api/power-bi/gateways/get-gateways
https://learn.microsoft.com/en-us/rest/api/power-bi/gateways/get-datasources
https://learn.microsoft.com/en-us/rest/api/power-bi/gateways/update-datasource
https://learn.microsoft.com/en-us/power-bi/developer/embedded/configure-credentials

NOTE: The API never returns stored secrets, so the new secret must be supplied.
It is read from the NEW_CLIENT_SECRET environment variable to avoid exposing it
in the process command line.
"""

import argparse
import json
import os
import requests
from azure.identity import ClientSecretCredential

_POWERBI_API_BASE = "https://api.powerbi.com/v1.0/myorg/"
_POWERBI_SCOPE    = "https://analysis.windows.net/powerbi/api/.default"

# Power BI sends cloud data source credentials without public-key encryption.
# On-premises gateways require RSA-OAEP encryption of the credential blob, which
# this script does not implement.
_ENCRYPTED_CONNECTION = "NotEncrypted"
_ENCRYPTION_ALGORITHM = "None"
_PRIVACY_LEVEL        = "Organizational"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Update the Service Principal secret of an existing Power BI gateway data source.")
    parser.add_argument("--tenant-id",       required=True, help="Azure AD tenant ID (used for API auth)")
    parser.add_argument("--client-id",       required=True, help="Service Principal client ID (used for API auth and stored as the data source username)")
    parser.add_argument("--connection-name", required=True, help="Name of the data source whose secret should be updated")
    return parser.parse_args()


def get_headers(args: argparse.Namespace) -> dict:
    credential = ClientSecretCredential(
        tenant_id=args.tenant_id,
        client_id=args.client_id,
        client_secret=os.environ["NEW_CLIENT_SECRET"],
    )
    token = credential.get_token(_POWERBI_SCOPE).token
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def get_gateways(headers: dict) -> list:
    url = f"{_POWERBI_API_BASE}gateways"
    response = requests.get(url, headers=headers)

    if response.status_code != 200:
        raise Exception(
            f"Failed to list gateways: {response.status_code} - {response.text}"
        )

    return response.json().get("value", [])


def get_datasources(gateway_id: str, headers: dict) -> list:
    url = f"{_POWERBI_API_BASE}gateways/{gateway_id}/datasources"
    response = requests.get(url, headers=headers)

    if response.status_code != 200:
        raise Exception(
            f"Failed to list data sources for gateway '{gateway_id}': "
            f"{response.status_code} - {response.text}"
        )

    return response.json().get("value", [])


def find_datasource(datasource_name: str, headers: dict) -> dict:
    gateways = get_gateways(headers)

    print(f"Available gateways ({len(gateways)}):")
    for gateway in gateways:
        print(f"  - {gateway.get('name', '<unnamed>')} (id: {gateway['id']})")

    for gateway in gateways:
        for datasource in get_datasources(gateway["id"], headers):
            if datasource.get("datasourceName") == datasource_name:
                return datasource

    raise Exception(
        f"Data source '{datasource_name}' not found in any accessible gateway. "
        f"This script only updates existing data sources."
    )


def update_secret(datasource: dict, args: argparse.Namespace, headers: dict) -> None:
    gateway_id    = datasource["gatewayId"]
    datasource_id = datasource["id"]

    # Service principal (client id + secret) is stored as a Basic credential:
    # username = client/app id, password = secret.
    credentials = json.dumps({
        "credentialData": [
            {"name": "username", "value": args.client_id},
            {"name": "password", "value": os.environ["NEW_CLIENT_SECRET"]},
        ]
    })

    payload = {
        "credentialDetails": {
            "credentialType": "Basic",
            "credentials": credentials,
            "encryptedConnection": _ENCRYPTED_CONNECTION,
            "encryptionAlgorithm": _ENCRYPTION_ALGORITHM,
            "privacyLevel": _PRIVACY_LEVEL,
        }
    }

    url = f"{_POWERBI_API_BASE}gateways/{gateway_id}/datasources/{datasource_id}"
    response = requests.patch(url, headers=headers, json=payload)

    if response.status_code == 200:
        return

    raise Exception(
        f"Failed to update data source '{datasource_id}': "
        f"{response.status_code} - {response.text}\n"
        f"If this data source is on an on-premises gateway, its credentials must be "
        f"RSA-encrypted with the gateway public key, which this script does not support."
    )


if __name__ == "__main__":
    args = parse_args()
    headers = get_headers(args)

    print("Searching gateways for the data source...")
    datasource = find_datasource(args.connection_name, headers)
    print(
        f"Data source '{args.connection_name}' found "
        f"(id: {datasource['id']}, gateway: {datasource['gatewayId']}). Updating secret..."
    )

    update_secret(datasource, args, headers)
    print(f"Updated. Data source ID: {datasource['id']}")
