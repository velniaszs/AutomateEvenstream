param(
    [Parameter(Mandatory = $true)]
    [string]$sourceWorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$sourceWorkspaceId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("yes", "no")]
    [string]$CheckWorkspace = "yes",

    [Parameter(Mandatory = $true)]
    [string]$capacityName,
    
    [Parameter(Mandatory = $false)]
    [string]$jsonPath = (Join-Path $PSScriptRoot "eventstream.json"),

    [Parameter(Mandatory = $true)]
    [string]$destinationWorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$DatabaseId
)

$sourceWorkspaceName = $sourceWorkspaceName -replace '[^a-zA-Z0-9]', '-'

if (-not (Test-Path $jsonPath)) {
    Write-Error "File not found: $jsonPath"
    exit 1
}

try {
    $content = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse JSON file. Error: $_"
    exit 1
}

if (-not $content) {
    Write-Warning "File is empty or invalid JSON structure."
    exit
}

if ($content.PSObject.Properties.Match('sources')) {
    $sources = $content.sources
    # Explicitly check if the array is empty
    if ($sources.Count -eq 0) {
        #Write-Host "json files does not have any sources in source array. Will use empty template."
        $IsEvenstreamEmpty = "yes"
    } else {
        #Write-Host "json files has sources. will add only new source"
        $IsEvenstreamEmpty = "no"
    }
}


$outputFolder = Join-Path $PSScriptRoot "Output"
# Create Output folder if it doesn't exist
if (-not (Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

if ($IsEvenstreamEmpty -eq "yes") {
    $cleanJsonPath = Join-Path $PSScriptRoot "\input\clean_evenstream.json"
    if (Test-Path $cleanJsonPath) {
        Copy-Item -Path $cleanJsonPath -Destination (Join-Path $outputFolder "$capacityName.json") -Force
    } else {
        Copy-Item -Path $jsonPath -Destination (Join-Path $outputFolder "$capacityName.json") -Force
    }
}

$outputjsonPath = Join-Path $outputFolder "$capacityName.json"

# 2. Read and parse the JSON
try {
    $jsonContent = Get-Content -Path $outputjsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "Failed to read or parse $outputjsonPath. Error: $_"
    exit 1
}

if ($null -eq $jsonContent) {
    Write-Error "JSON content is null. Aborting."
    exit 1
}

if ($CheckWorkspace -eq "yes") {
    # Check if source name already exists
    $existingName = $jsonContent.sources | Where-Object { $_.name -eq $sourceWorkspaceName }
    if ($existingName) {
        Write-Warning "Source with name '$sourceWorkspaceName' already exists."
    }

    # Check if workspaceId already exists
    $existingId = $jsonContent.sources | Where-Object { $_.properties.workspaceId -eq $sourceWorkspaceId }
    if ($existingId) {
        Write-Warning "Source with workspaceId '$sourceWorkspaceId' already exists."
    }

    if ($existingName -or $existingId) {
        Write-Warning "Skipping addition due to existing source(s)."
        return
    }
}

#-----------------------------
if ($IsEvenstreamEmpty -eq "yes") {
    # Update destinations
    if ($jsonContent.destinations) {
        foreach ($destination in $jsonContent.destinations) {
            $destination.id = [Guid]::NewGuid().ToString()
            
            if ($destination.properties) {
                $destination.properties.workspaceId = $destinationWorkspaceId
                $destination.properties.itemId = $DatabaseId
                
                $randomSuffix = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
                $destination.properties.connectionName = "${capacityName}_${randomSuffix}" # Unique connection name. Added, because after deletion, the same name cannot be reused.
            }
            if ($destination.inputNodes) {
                foreach ($node in $destination.inputNodes) {
                    $node.name = "$capacityName-stream"
                }
            }
        }
    }

    # Update streams
    if ($jsonContent.streams) {
        foreach ($stream in $jsonContent.streams) {
            $stream.id = [Guid]::NewGuid().ToString()
            $stream.name = "$capacityName-stream"
        }
    }
}
#------------------------------

# 3. Define the new source object
#    Using [Guid]::NewGuid() ensures a unique ID
$newSource = [PSCustomObject]@{
    id = [Guid]::NewGuid().ToString()
    name = $sourceWorkspaceName
    type = "FabricWorkspaceItemEvents"
    properties = [PSCustomObject]@{
        eventScope = "Workspace"
        workspaceId = $sourceWorkspaceId
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
$stream = $jsonContent.streams | Where-Object { $_.name -eq "$capacityName-stream" }

if ($stream) {
    # Add the new source name to the stream's inputNodes
    $stream.inputNodes += [PSCustomObject]@{ name = $sourceWorkspaceName }
    #Write-Host "Added '$sourceWorkspaceName' to stream '$capacityName-stream'."
} else {
    Write-Warning "Stream '$capacityName-stream' not found. Source added but not connected."
}

# 6. Save the file
#    IMPORTANT: -Depth 10 is required to preserve nested properties
$jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $outputjsonPath -Encoding UTF8

#Write-Host "Successfully updated $outputjsonPath"