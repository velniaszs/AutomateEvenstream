# Deploy-KQL.ps1
# Deploys KQL commands from a file to a Fabric Eventhouse/KQL Database via REST API.
# Usage: .\Deploy-KQL.ps1 -KqlFilePath ".\prepare_eventhouse_tables.sql"

param (
    [string]$ClusterUri = "https://trd-6uegjpfbf030eemxtw.z1.kusto.fabric.microsoft.com",
    [string]$DatabaseName = "MonitoringEventhouse",
    [string]$KqlFilePath = ".\prepare_eventhouse_tables.kql"
)

$ErrorActionPreference = "Stop"

# --- Configuration (Matches your other scripts) ---
$tenantId = ''
$clientId = ''
$CLIENT_SECRET = ''

# --- 1. Get Token ---
Write-Host "Getting Access Token..." -ForegroundColor Cyan

# Scope for Kusto
$scope = "$ClusterUri/.default"
$tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $CLIENT_SECRET
    scope         = $scope
}

try {
    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body
    $token = $response.access_token
    Write-Host "Token retrieved successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to authenticate. Error: $_"
    exit
}

# --- 2. Parse KQL File ---
if (-not (Test-Path $KqlFilePath)) {
    $scriptRootPath = Join-Path $PSScriptRoot -ChildPath $KqlFilePath
    if (Test-Path $scriptRootPath) {
        $KqlFilePath = $scriptRootPath
        Write-Host "Found file in script directory: $KqlFilePath" -ForegroundColor Yellow
    }
}
$fullPath = Resolve-Path $KqlFilePath
Write-Host "Reading KQL file: $fullPath" -ForegroundColor Cyan


# precise splitting of commands is tricky, but usually empty lines separate commands in KQL scripts.
# We read the whole content and split by double newlines.
$fileContent = Get-Content -Path $fullPath -Raw
# Remove comments (simple -- or // if at start of line, but be careful not to break query strings)
# For now, we assume clean commands separated by at least one blank line.

# Split by blank lines (regex for 2 or more newlines)
$commands = $fileContent -split '(?:\r?\n){2,}'

# --- 3. Execute Commands ---
$mgmtUrl = "$ClusterUri/v1/rest/mgmt"
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

foreach ($cmd in $commands) {
    $cleanCmd = $cmd.Trim()
    
    # Skip empty commands or comments
    if ([string]::IsNullOrWhiteSpace($cleanCmd) -or $cleanCmd.StartsWith("//")) {
        continue
    }

    Write-Host "Executing command..." -ForegroundColor Yellow
    # Print first line of command for context
    $firstLine = ($cleanCmd -split '\r?\n')[0]
    Write-Host "  > $firstLine" -ForegroundColor DarkGray

    $payload = @{
        "db"  = $DatabaseName
        "csl" = $cleanCmd
    } | ConvertTo-Json -Compress

    try {
        $result = Invoke-RestMethod -Uri $mgmtUrl -Method Post -Headers $headers -Body $payload
        Write-Host "  Success" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to execute command. Error: $_"
        # Optional: Print the full command that failed
        # Write-Host $cleanCmd
    }
}

Write-Host "Deployment Complete." -ForegroundColor Cyan
