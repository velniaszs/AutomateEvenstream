[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Define file paths
$workspacesPath = Join-Path $PSScriptRoot "\input\workspaces.json"
$allowedWorkspacesPath = Join-Path $PSScriptRoot "\input\allowed_workspaces.json"

# Validate files exist
if (-not (Test-Path $workspacesPath)) {
    Write-Error "workspaces.json not found at $workspacesPath"
    exit 1
}

if (-not (Test-Path $allowedWorkspacesPath)) {
    Write-Error "allowed_workspaces.json not found at $allowedWorkspacesPath"
    exit 1
}

Write-Host "Reading workspaces.json..."
$workspaces = Get-Content $workspacesPath | ConvertFrom-Json

Write-Host "Reading allowed_workspaces.json..."
$allowedWorkspaces = Get-Content $allowedWorkspacesPath | ConvertFrom-Json

# Extract allowed workspace IDs
$allowedIds = $allowedWorkspaces | ForEach-Object { $_.ubsppcoe_workspace_id }

Write-Host "Found $($allowedIds.Count) allowed workspace ID(s)."

# Filter workspaces to only those in the allowed list
$filteredWorkspaces = $workspaces | Where-Object { $_.id -in $allowedIds }

Write-Host "Filtered from $($workspaces.Count) to $($filteredWorkspaces.Count) workspace(s)."

# Overwrite workspaces.json with filtered data
Write-Host "Overwriting workspaces.json with filtered workspaces..."
$filteredWorkspaces | ConvertTo-Json -Depth 10 | Set-Content $workspacesPath

Write-Host "Filtering complete."
