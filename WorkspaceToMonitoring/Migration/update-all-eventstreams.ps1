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
$updateScript = Join-Path $PSScriptRoot "..\update-eventstream.ps1"

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

# Iterate through output JSON files and update if a matching eventstream exists
$jsonFiles = Get-ChildItem -Path $outputFolder -Filter "*.json"
Write-Host "Found $($jsonFiles.Count) definition files in Output folder."

foreach ($jsonFile in $jsonFiles) {
    $baseName = $jsonFile.BaseName
    $jsonFilePath = $jsonFile.FullName

    $matchingEs = $eventstreams | Where-Object { $_.displayName -eq $baseName } | Select-Object -First 1

    if ($matchingEs) {
        $esId = $matchingEs.id
        Write-Host "Found matching eventstream for '$baseName' (id: $esId). Updating..."
        try {
            & $updateScript -WorkspaceId $WorkspaceId -EventstreamId $esId -AuthToken $AuthToken -DefinitionFile $jsonFilePath

            $definition = Get-Content -Path $jsonFilePath -Raw | ConvertFrom-Json
            $sourceWorkspaceIds = $definition.sources | ForEach-Object { $_.properties.workspaceId } | Where-Object { $_ }
            Write-Host "  Source workspaceIds in '$baseName':"
            Write-Host $sourceWorkspaceIds #HERE ARE ALL WORKSPACES IN one capacity(evenstream), that successfully Loaded
        }
        catch {
            Write-Error "Failed to update '$baseName'. Error: $_"
        }
    } else {
        Write-Host "No matching eventstream found for '$baseName'. Skipping."
    }
}
