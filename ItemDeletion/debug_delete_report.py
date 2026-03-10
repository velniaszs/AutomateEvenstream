"""
Debug script: authenticate via SPN and delete a single Fabric Report item.
Fill in the credentials and workspace_id below before running.
"""

import requests

# ---------------------------------------------------------------------------
# Configuration — fill these in before running
# ---------------------------------------------------------------------------
TENANT_ID     = "your-tenant-id"
CLIENT_ID     = "your-client-id"
CLIENT_SECRET = "your-client-secret"

WORKSPACE_ID  = "your-workspace-id"
REPORT_ID     = "your-report-id"
SCORECARD_ID  = "your-scorecard-id"
DASHBOARD_ID  = "your-dashboard-id"

FABRIC_API_BASE = "https://api.fabric.microsoft.com/v1"
PBI_API_BASE    = "https://api.powerbi.com/v1.0/myorg"
# ---------------------------------------------------------------------------


def get_token(tenant_id, client_id, client_secret):
    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    payload = {
        "grant_type":    "client_credentials",
        "client_id":     client_id,
        "client_secret": client_secret,
        "scope":         "https://api.fabric.microsoft.com/.default",
    }
    resp = requests.post(url, data=payload)
    resp.raise_for_status()
    return resp.json()["access_token"]


def delete_report_pbi_group(token, workspace_id, item_id):
    url = f"{PBI_API_BASE}/groups/{workspace_id}/reports/{item_id}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type":  "application/json",
    }

    resp = requests.delete(url, headers=headers)

    print(f"[PBI-GROUP] Status : {resp.status_code}")
    print(f"[PBI-GROUP] Headers: {dict(resp.headers)}")
    print(f"[PBI-GROUP] Body   : {resp.text}")


def delete_scorecard_pbi(token, workspace_id, item_id):
    url = f"{PBI_API_BASE}/groups/{workspace_id}/scorecards({item_id})"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type":  "application/json",
    }

    resp = requests.delete(url, headers=headers)

    print(f"[PBI-SCORECARD] Status : {resp.status_code}")
    print(f"[PBI-SCORECARD] Headers: {dict(resp.headers)}")
    print(f"[PBI-SCORECARD] Body   : {resp.text}")


def delete_dashboard_pbi(token, workspace_id, item_id):
    url = f"{PBI_API_BASE}/groups/{workspace_id}/dashboards/{item_id}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type":  "application/json",
    }

    resp = requests.delete(url, headers=headers)

    print(f"[PBI-DASHBOARD] Status : {resp.status_code}")
    print(f"[PBI-DASHBOARD] Headers: {dict(resp.headers)}")
    print(f"[PBI-DASHBOARD] Body   : {resp.text}")


def get_scorecards_pbi(token, workspace_id):
    url = f"{PBI_API_BASE}/groups/{workspace_id}/scorecards"
    headers = {"Authorization": f"Bearer {token}"}
    items = []
    while url:
        resp = requests.get(url, headers=headers)
        resp.raise_for_status()
        data = resp.json()
        items.extend(data.get("value", []))
        url = data.get("@odata.nextLink")
    return items


def get_workspace_items(token, workspace_id):
    url = f"{FABRIC_API_BASE}/workspaces/{workspace_id}/items"
    headers = {"Authorization": f"Bearer {token}"}
    items = []
    while url:
        resp = requests.get(url, headers=headers)
        resp.raise_for_status()
        data = resp.json()
        items.extend(data.get("value", []))
        url = data.get("continuationUri")
    return items


def delete_report(token, workspace_id, item_id):
    url = f"{FABRIC_API_BASE}/workspaces/{workspace_id}/reports/{item_id}"
    headers = {
        "Authorization":  f"Bearer {token}",
        "Content-Type":   "application/json",
    }

    resp = requests.delete(url, headers=headers)

    print(f"Status : {resp.status_code}")
    print(f"Headers: {dict(resp.headers)}")
    print(f"Body   : {resp.text}")


if __name__ == "__main__":
    token = get_token(TENANT_ID, CLIENT_ID, CLIENT_SECRET)

    items = get_workspace_items(token, WORKSPACE_ID)
    print(f"Workspace items ({len(items)}):")
    for item in items:
        print(f"  {item.get('type'):30} {item.get('id')}  {item.get('displayName')}")

    #scorecards = get_scorecards_pbi(token, WORKSPACE_ID)
    #print(f"Scorecards ({len(scorecards)}):")
    #for sc in scorecards:
    #    print(f"  {sc.get('id')}  {sc.get('name')}")


    #delete_scorecard_pbi(token, WORKSPACE_ID, SCORECARD_ID)
    #delete_dashboard_pbi(token, WORKSPACE_ID, DASHBOARD_ID)
    #delete_report(token, WORKSPACE_ID, REPORT_ID)
    delete_report_pbi_group(token, WORKSPACE_ID, REPORT_ID)
