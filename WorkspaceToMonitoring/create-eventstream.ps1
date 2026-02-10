[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$EventstreamName,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken ,

    [Parameter(Mandatory = $true)]
    [string]$folderId,

    [Parameter(Mandatory = $true)]
    [string]$capacityName
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    Write-Error "AuthToken is empty."
    return
}

$payload = [ordered]@{
    displayName = $EventstreamName
    description = "Monitoring for CapacityName"
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
    $content = $response.Content | ConvertFrom-Json
    #Write-Host "Eventstream '$EventstreamName' created successfully. ID: $($content.id)"
    return $content.id
}
catch {
    throw "Failed to create Eventstream. Error: $_"
}
