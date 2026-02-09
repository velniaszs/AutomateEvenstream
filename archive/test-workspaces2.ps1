[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AuthToken,
    [string]$OutputFile = "$PSScriptRoot\input\workspaces.json",
    [bool]$VerifyOAP = $true,
    [string]$WorkspaceId
)

$ErrorActionPreference = "Stop"

# 1. Validate Access Token
if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    Write-Error "AuthToken is empty."
    return
}

$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

# 2. List Workspaces with Pagination
$url = "https://api.fabric.microsoft.com/v1/admin/workspaces?state=Active&type=Workspace"
$allWorkspaces = @()

Write-Host "Starting workspace discovery..."

do {
    #Write-Host "Fetching from: $url"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
    }
    catch {
        Write-Host "exception status code info:"
        Write-Error $_.Exception.Response.StatusCode
        Write-Error "Failed to fetch workspaces. Error: $_"
        return
    }

    if ($response.workspaces) {
        $allWorkspaces += $response.workspaces
    }

    # Handle Pagination
    # The API returns 'continuationUri' for the next page if available
    if ($response.continuationUri) {
        $url = $response.continuationUri
    } else {
        $url = $null
    }

} while ($null -ne $url)

Write-Host "Total workspaces found: $($allWorkspaces.Count)"
