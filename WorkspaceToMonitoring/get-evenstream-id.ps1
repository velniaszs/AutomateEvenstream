[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [Parameter(Mandatory = $true)]
    [string]$EventstreamName

)

$ErrorActionPreference = "Stop"

# Get existing Eventstreams in the workspace
Write-Host "Checking if Eventstream '$EventstreamName' already exists in workspace '$WorkspaceId'..."
$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}
$existingEventstreamsUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams"
try {
    $existingEventstreamsResponse = Invoke-RestMethod -Uri $existingEventstreamsUri -Method Get -Headers $headers -ErrorAction Stop
    $existingEventstreams = $existingEventstreamsResponse.value
}
catch {
    Write-Error "Failed to list existing eventstreams. Error: $_"
}

# Check if already exists
$existing = $existingEventstreams | Where-Object { $_.displayName -eq $EventstreamName }
if ($existing) {
    Write-Host "'$EventstreamName' - Eventstream already exists (ID: $($existing.id))." 
    return @{
        Id      = $existing.id
        Exists = $true
    }
} 
else {
    return @{
        Id      = $null
        Exists = $false
    }
}