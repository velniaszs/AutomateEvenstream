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
$processedFolder = Join-Path $PSScriptRoot "Processed"
$updateScript = Join-Path $PSScriptRoot "..\update-eventstream.ps1"

# Create/clear Processed folder
if (Test-Path $processedFolder) {
    Remove-Item -Path "$processedFolder\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path $processedFolder | Out-Null
}

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

$processedFilePath = Join-Path $processedFolder "processed_workspaces.json"

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
            
            # Read existing processed workspaces or create empty array
            $processedWorkspaces = @()
            if (Test-Path $processedFilePath) {
                $processedWorkspaces = Get-Content -Path $processedFilePath -Raw | ConvertFrom-Json
                if ($processedWorkspaces -isnot [Array]) {
                    $processedWorkspaces = @($processedWorkspaces)
                }
            }
            
            # Add current eventstream's workspaces as objects with workspaceId property
            foreach ($wsId in $sourceWorkspaceIds) {
                $processedWorkspaces += [PSCustomObject]@{
                    workspaceId = $wsId
                }
            }
            
            # Save back to file immediately (ensure it's always an array)
            @($processedWorkspaces) | ConvertTo-Json -Depth 10 | Set-Content -Path $processedFilePath
            
            Write-Host "  Processed $($sourceWorkspaceIds.Count) workspace(s) for '$baseName'"
        }
        catch {
            Write-Error "Failed to update '$baseName'. Error: $_"
        }
    } else {
        Write-Host "No matching eventstream found for '$baseName'. Skipping."
    }
}

Write-Host "`nProcessing complete. Results saved to: $processedFilePath"
