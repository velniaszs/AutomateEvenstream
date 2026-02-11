param(
    [Parameter(Mandatory = $true)]
    [string]$sourceWorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$sourceWorkspaceId,
    
    [Parameter(Mandatory = $false)]
    [string]$jsonPath = (Join-Path $PSScriptRoot "eventstream.json")
)

$sourceWorkspaceName = $sourceWorkspaceName -replace '[^a-zA-Z0-9]', '-'

if (-not (Test-Path $jsonPath)) {
    Write-Error "File not found: $jsonPath"
    exit 1
}

try {
    $jsonContent = Get-Content -Path $jsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "Failed to parse JSON file. Error: $_"
    exit 1
}

if ($null -eq $jsonContent) {
    Write-Error "JSON content is null. Aborting."
    exit 1
}

# Check if source name already exists
$existingName = $jsonContent.sources | Where-Object { $_.name -eq $sourceWorkspaceName }

# Check if workspaceId already exists
$existingId = $jsonContent.sources | Where-Object { $_.properties.workspaceId -eq $sourceWorkspaceId }

if ($existingName -or $existingId) {
    #Write-Host "Skipping addition due to existing source(s)."
    return $true
} else {
    return $false
}

