param (
    [Parameter(Mandatory = $true)]
    [string]$destinationWorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$DatabaseId,

    [Parameter(Mandatory = $true)]
    [string]$DatabaseName
)

# Paths
$jsonFilePath = Join-Path $PSScriptRoot "input\clean_evenstream.json"
$capacityDetailsPath = Join-Path $PSScriptRoot "input\workspace_capacity_details.json"
$outputFolder = Join-Path $PSScriptRoot "Output"

# Create Output folder if it doesn't exist, or clear it if it does
if (Test-Path $outputFolder) {
    Remove-Item -Path "$outputFolder\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

# Read capacity details
if (-not (Test-Path $capacityDetailsPath)) {
    Write-Error "File not found: $capacityDetailsPath"
    exit 1
}
$capacityDetails = Get-Content -Path $capacityDetailsPath -Raw | ConvertFrom-Json
$uniqueGroups = $capacityDetails | Select-Object -ExpandProperty workspaceGroup -Unique

foreach ($group in $uniqueGroups) {
    # Read the JSON content fresh for each iteration to ensure clean state
    $eventstreamData = Get-Content -Path $jsonFilePath -Raw | ConvertFrom-Json

    # Update destinations
    if ($eventstreamData.destinations) {
        foreach ($destination in $eventstreamData.destinations) {
            $destination.id = [Guid]::NewGuid().ToString()
            
            if ($destination.properties) {
                $destination.properties.workspaceId = $destinationWorkspaceId
                $destination.properties.itemId = $DatabaseId
                
                $randomSuffix = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
                $destination.properties.connectionName = "${group}_${randomSuffix}" # Unique connection name. Added, because after deletion, the same name cannot be reused.
            }
            if ($destination.inputNodes) {
                foreach ($node in $destination.inputNodes) {
                    $node.name = "$group-stream"
                }
            }
        }
    }

    # Update streams
    if ($eventstreamData.streams) {
        foreach ($stream in $eventstreamData.streams) {
            $stream.id = [Guid]::NewGuid().ToString()
            $stream.name = "$group-stream"
        }
    }

    # Save the updated object as formatted JSON to a new file
    $outputPath = Join-Path $outputFolder "$group.json"
    $eventstreamData | ConvertTo-Json -Depth 10 | Set-Content -Path $outputPath

    # Add sources for each workspace in the group
    $groupWorkspaces = $capacityDetails | Where-Object { $_.workspaceGroup -eq $group }
    $addSourceScript = Join-Path $PSScriptRoot "\add-source.ps1"

    foreach ($ws in $groupWorkspaces) {
        $group = $ws.workspaceGroup
        & $addSourceScript -workspaceName $ws.WorkspaceName -workspaceId $ws.WorkspaceId -jsonPath $outputPath -targetStreamName "$group-stream"
    }

    Write-Host "Created $outputPath"
}
