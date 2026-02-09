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
$url = "https://api.fabric.microsoft.com/v1/admin/items"
$allWorkspaces = @()
$loopCount = 0

do {
    $loopCount++
    Write-Host "Loop iteration: $loopCount"
    #Write-Host "Fetching from: $url"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
    }
    catch {
        Write-Error "Failed to fetch items. Error: $_"
        return
    }

    if ($response.itemEntities) {
        $allWorkspaces += $response.itemEntities
    }

    # Handle Pagination
    # The API returns 'continuationUri' for the next page if available
    if ($response.continuationUri) {
        $url = $response.continuationUri
        #Start-Sleep -Seconds 10
    } else {
        $url = $null
    }

} while ($null -ne $url)

Write-Host "Total items found: $($allWorkspaces.Count)"
