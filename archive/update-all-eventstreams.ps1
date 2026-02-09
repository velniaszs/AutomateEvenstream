[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken
)

$ErrorActionPreference = "Stop"

# Paths
$outputFolder = Join-Path $PSScriptRoot "Output"
$updateScript = Join-Path $PSScriptRoot "update-eventstream.ps1"

# Validate paths
if (-not (Test-Path $outputFolder)) {
    Write-Error "Output folder not found: $outputFolder"
    return
}

if (-not (Test-Path $updateScript)) {
    Write-Error "Update script not found: $updateScript"
    return
}

# Get Eventstreams from Fabric API
Write-Host "Fetching existing Eventstreams in workspace '$WorkspaceId'..."
$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}
$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
    $eventstreams = $response.value
}
catch {
    Write-Error "Failed to list eventstreams. Error: $_"
    return
}

Write-Host "Found $($eventstreams.Count) eventstreams."

# Iterate through eventstreams and update if matching JSON exists
foreach ($es in $eventstreams) {
    $esName = $es.displayName
    $esId = $es.id
    
    $jsonFilePath = Join-Path $outputFolder "$esName.json"

    if (Test-Path $jsonFilePath) {
        Write-Host "Found matching definition file for '$esName' ($jsonFilePath). Updating..."
        try {
            & $updateScript -WorkspaceId $WorkspaceId -EventstreamId $esId -AuthToken $AuthToken -DefinitionFile $jsonFilePath
        }
        catch {
            Write-Error "Failed to update '$esName'. Error: $_"
        }
    } else {
        Write-Host "No definition file found for '$esName' in Output folder. Skipping."
    }
}
