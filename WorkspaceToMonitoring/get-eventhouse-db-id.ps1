[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [Parameter(Mandatory = $false)]
    [string]$EventhouseName = "MyEventhouse"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    Write-Error "AuthToken is empty."
    return
}

if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
    Write-Error "WorkspaceId is empty."
    return
}

$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

# 1. Check if Eventhouse exists
#Write-Host "Checking for Eventhouse '$EventhouseName'..."
$eventhousesUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses"
try {
    $eventhousesResponse = Invoke-RestMethod -Uri $eventhousesUri -Method Get -Headers $headers
}
catch {
    Write-Error "Failed to list eventhouses. Error: $_"
    return
}

$eventhouse = $eventhousesResponse.value | Where-Object { $_.displayName -eq $EventhouseName }

if ($null -eq $eventhouse) {
    Write-Error "Eventhouse '$EventhouseName' not found in workspace '$WorkspaceId'."
    return
}

#Write-Host "Found Eventhouse: $($eventhouse.displayName) (ID: $($eventhouse.id))"

# 2. Find the KQL Database
# We assume the default database has the same name as the Eventhouse.
#Write-Host "Looking for KQL Database '$EventhouseName'..."
$kqlDbsUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/kqlDatabases"
try {
    $kqlDbsResponse = Invoke-RestMethod -Uri $kqlDbsUri -Method Get -Headers $headers
}
catch {
    Write-Error "Failed to list KQL databases. Error: $_"
    return
}

$targetDb = $kqlDbsResponse.value | Where-Object { $_.displayName -eq $EventhouseName }

if ($null -eq $targetDb) {
    Write-Error "KQL Database with name '$EventhouseName' not found. Please ensure the database exists."
    return
}

#Write-Host "Found KQL Database: $($targetDb.displayName) (ID: $($targetDb.id))"

return @{
    Id = $targetDb.id
    QueryServiceUri = $targetDb.properties.queryServiceUri
}
