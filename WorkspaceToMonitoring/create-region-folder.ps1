param (
    [Parameter(Mandatory=$true)]
    [string]$AuthToken,
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceId,
    [Parameter(Mandatory=$true)]
    [string]$RegionName
)

if ([string]::IsNullOrWhiteSpace($RegionName)) {
    Write-Error "RegionName cannot be empty."
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

# Get existing folders
$foldersUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/folders"
try {
    $existingFoldersResponse = Invoke-RestMethod -Uri $foldersUri -Method Get -Headers $headers -ErrorAction Stop
    $existingFolders = $existingFoldersResponse.value
}
catch {
    Write-Warning "Failed to list existing folders. Proceeding with creation attempts. Error: $_"
    $existingFolders = @()
}

Write-Host "Processing region: $RegionName"

$existingFolder = $existingFolders | Where-Object { $_.displayName -eq $RegionName }
if ($existingFolder) {
    Write-Host "Folder '$RegionName' already exists. Skipping." -ForegroundColor Yellow
    # Optionally return the ID if needed by caller:
    return $existingFolder.id
    exit
}

$body = @{
    displayName = $RegionName
} | ConvertTo-Json

$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/folders"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
    Write-Host "Successfully created folder '$RegionName'. ID: $($response.id)"
    return $response.id
}
catch {
    Write-Error "Failed to create folder '$RegionName'. Error: $_"
}
