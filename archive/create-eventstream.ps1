[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$DisplayName,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [Parameter(Mandatory = $true)]
    [string]$folderId,

    [Parameter(Mandatory = $true)]
    [string]$capacityId
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    Write-Error "AuthToken is empty."
    return
}

$payload = [ordered]@{
    displayName = $DisplayName
    description = "Monitoring for CapacityId $capacityId"
    folderId = $folderId
}

$jsonPayload = $payload | ConvertTo-Json -Depth 10

$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams"
$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

try {
    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $jsonPayload -UseBasicParsing
    Write-Host "Eventstream created successfully."
}
catch {
    Write-Error "Failed to create Eventstream. Error: $_"
}
