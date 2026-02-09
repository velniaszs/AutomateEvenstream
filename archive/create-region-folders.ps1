param (
    [Parameter(Mandatory=$true)]
    [string]$AuthToken,
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceId
)

# Path to capacities.json
$jsonPath = Join-Path $PSScriptRoot "\input\workspace_capacity_details.json"
if (-not (Test-Path $jsonPath)) {
    Write-Error "workspace_capacity_details.json not found at $jsonPath"
    exit 1
}

# Read and parse JSON
try {
    $capacities = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse workspace_capacity_details.json: $_"
    exit 1
}

# Get unique regions
$regions = $capacities | Select-Object -ExpandProperty RegionName -Unique

if (-not $regions) {
    Write-Warning "No regions found in workspace_capacity_details.json"
    exit
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

# Create folder for each region
foreach ($region in $regions) {
    if ([string]::IsNullOrWhiteSpace($region)) { continue }

    Write-Host "Processing region: $region"

    $existingFolder = $existingFolders | Where-Object { $_.displayName -eq $region }
    if ($existingFolder) {
        Write-Host "Folder '$region' already exists. Skipping." -ForegroundColor Yellow
        continue
    }

    $body = @{
        displayName = $region
    } | ConvertTo-Json

    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/folders"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "Successfully created folder '$region'. ID: $($response.id)" -ForegroundColor Green
    }
    catch {
        # Check if error is because folder already exists or other issue
        $errorDetails = $_.Exception.Response.GetResponseStream()
        $reader = [System.IO.StreamReader]::new($errorDetails)
        $responseBody = $reader.ReadToEnd()
        
        Write-Error "Failed to create folder '$region'. Error: $($_.Exception.Message). Details: $responseBody"
    }
}
