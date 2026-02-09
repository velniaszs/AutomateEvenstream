[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken
)

$ErrorActionPreference = "Stop"

# Paths to JSON files
$workspaceDetailsPath = Join-Path $PSScriptRoot "\input\workspace_capacity_details.json"
$foldersPath = Join-Path $PSScriptRoot "\input\folders.json"
$createEventstreamScript = Join-Path $PSScriptRoot "\create-eventstream.ps1"

# Check if files exist
if (-not (Test-Path $workspaceDetailsPath)) { Write-Error "File not found: $workspaceDetailsPath"; exit }
if (-not (Test-Path $foldersPath)) { Write-Error "File not found: $foldersPath"; exit }
if (-not (Test-Path $createEventstreamScript)) { Write-Error "Script not found: $createEventstreamScript"; exit }

# Read JSON data
try {
    $workspaceDetails = Get-Content -Path $workspaceDetailsPath -Raw | ConvertFrom-Json
    $foldersData = Get-Content -Path $foldersPath -Raw | ConvertFrom-Json
    
    # Handle folders.json structure (it might be wrapped in a 'value' property or be a direct array)
    if ($foldersData.PSObject.Properties.Match('value')) {
        $folders = $foldersData.value
    } else {
        $folders = $foldersData
    }
}
catch {
    Write-Error "Failed to read or parse JSON files. Error: $_"
    exit
}

# Get existing Eventstreams in the workspace
Write-Host "Fetching existing Eventstreams in workspace '$WorkspaceId'..."
$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}
$existingEventstreamsUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams"
try {
    $existingEventstreamsResponse = Invoke-RestMethod -Uri $existingEventstreamsUri -Method Get -Headers $headers -ErrorAction Stop
    $existingEventstreamNames = $existingEventstreamsResponse.value | Select-Object -ExpandProperty displayName
    Write-Host "Found $($existingEventstreamNames.Count) existing eventstreams."
}
catch {
    Write-Warning "Failed to list existing eventstreams. Proceeding without filtering. Error: $_"
    $existingEventstreamNames = @()
}

# Get unique combinations of workspaceGroup and RegionName
$uniqueGroups = $workspaceDetails | Group-Object workspaceGroup, RegionName | ForEach-Object {
    [PSCustomObject]@{
        workspaceGroup = $_.Group[0].workspaceGroup
        RegionName     = $_.Group[0].RegionName
        CapacityId     = ($_.Group.CapacityId | Select-Object -Unique) -join ","
    }
}

# Filter out groups that already have an eventstream
$groupsToCreate = @($uniqueGroups | Where-Object {
    if ($existingEventstreamNames -contains $_.workspaceGroup) {
        Write-Host "Skipping '$($_.workspaceGroup)' - Eventstream already exists." -ForegroundColor Yellow
        return $false
    }
    return $true
})

Write-Host "Found $($groupsToCreate.Count) unique eventstreams to create (after filtering existing)."

foreach ($group in $groupsToCreate) {
    $displayName = $group.workspaceGroup
    $regionName = $group.RegionName
    $capacityId = $group.CapacityId

    if ([string]::IsNullOrWhiteSpace($displayName) -or [string]::IsNullOrWhiteSpace($regionName)) {
        Write-Warning "Skipping entry with missing DisplayName or RegionName."
        continue
    }

    Write-Host "Processing: Group='$displayName', Region='$regionName'"

    # Find matching folder ID
    $folder = $folders | Where-Object { $_.displayName -eq $regionName }

    if (-not $folder) {
        Write-Warning "  No folder found for Region '$regionName'. Skipping creation for '$displayName'."
        continue
    }

    $folderId = $folder.id
    Write-Host "  Found Folder ID: $folderId"

    # Call create-eventstream.ps1
    try {
        Write-Host "  Calling create-eventstream.ps1..."
        & $createEventstreamScript -WorkspaceId $WorkspaceId -DisplayName $displayName -AuthToken $AuthToken -folderId $folderId -capacityId $capacityId
    }
    catch {
        Write-Error "  Failed to create eventstream '$displayName'. Error: $_"
    }
}

Write-Host "Evenstreams Created"
