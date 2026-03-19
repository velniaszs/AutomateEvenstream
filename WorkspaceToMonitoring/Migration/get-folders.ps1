param (
    [Parameter(Mandatory=$true)]
    [string]$AuthToken,
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceId
)

$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

# Get existing folders
$foldersUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/folders"
try {
    $folders = Invoke-RestMethod -Uri $foldersUri -Method Get -Headers $headers -ErrorAction Stop
    
    $outputFile = Join-Path $PSScriptRoot "input\folders.json"
    $folders | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile
    Write-Host "Folders saved to $outputFile"
}
catch {
    Write-Warning "Error: $_"
}