param(
    [Parameter(Mandatory = $true)]
    [string]$workspaceName,

    [Parameter(Mandatory = $true)]
    [string]$workspaceId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("yes", "no")]
    [string]$CheckWorkspace = "no",

    [Parameter(Mandatory = $true)]
    [string]$targetStreamName,
    
    [Parameter(Mandatory = $false)]
    [string]$jsonPath = (Join-Path $PSScriptRoot "eventstream.json")
)

# 2. Read and parse the JSON
try {
    $jsonContent = Get-Content -Path $jsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "Failed to read or parse $jsonPath. Error: $_"
    exit 1
}

if ($null -eq $jsonContent) {
    Write-Error "JSON content is null. Aborting."
    exit 1
}

if ($CheckWorkspace -eq "yes") {
    # Check if source name already exists
    $existingName = $jsonContent.sources | Where-Object { $_.name -eq $workspaceName }
    if ($existingName) {
        Write-Warning "Source with name '$workspaceName' already exists."
    }

    # Check if workspaceId already exists
    $existingId = $jsonContent.sources | Where-Object { $_.properties.workspaceId -eq $workspaceId }
    if ($existingId) {
        Write-Warning "Source with workspaceId '$workspaceId' already exists."
    }

    if ($existingName -or $existingId) {
        Write-Warning "Skipping addition due to existing source(s)."
        return
    }
}

# 3. Define the new source object
#    Using [Guid]::NewGuid() ensures a unique ID
$newSource = [PSCustomObject]@{
    id = [Guid]::NewGuid().ToString()
    name = $workspaceName
    type = "FabricWorkspaceItemEvents"
    properties = [PSCustomObject]@{
        eventScope = "Workspace"
        workspaceId = $workspaceId
        includedEventTypes = @(
            "Microsoft.Fabric.ItemCreateSucceeded",
            "Microsoft.Fabric.ItemDeleteSucceeded"
        )
        filters = @()
    }
}

# 4. Add the new source to the 'sources' array
$jsonContent.sources += $newSource

# 5. (Recommended) Connect the new source to your stream
#    Find the stream by name (e.g., "LoadWorkspaceChanges-stream")
$stream = $jsonContent.streams | Where-Object { $_.name -eq $targetStreamName }

if ($stream) {
    # Add the new source name to the stream's inputNodes
    $stream.inputNodes += [PSCustomObject]@{ name = $workspaceName }
    Write-Host "Added '$workspaceName' to stream '$targetStreamName'."
} else {
    Write-Warning "Stream '$targetStreamName' not found. Source added but not connected."
}

# 6. Save the file
#    IMPORTANT: -Depth 10 is required to preserve nested properties
$jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host "Successfully updated $jsonPath"