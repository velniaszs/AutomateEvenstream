$workspacesFile = Join-Path $PSScriptRoot "\input\workspaces.json"
$workspaces = Get-Content -Path $workspacesFile -Raw | ConvertFrom-Json

# Read eventstream.json to find the excluded workspace ID
$eventstreamFile = Join-Path $PSScriptRoot "eventstream.json"
$eventstream = Get-Content -Path $eventstreamFile -Raw | ConvertFrom-Json
$destination = $eventstream.destinations | Where-Object { $_.type -eq 'Eventhouse' }
$excludedWorkspaceId = $destination.properties.workspaceId

Write-Host "Excluded Workspace ID: $excludedWorkspaceId"

foreach ($workspace in $workspaces) {
    $name = $workspace.displayName
    $id = $workspace.id
    
    if ($id -eq $excludedWorkspaceId) {
        Write-Host "Skipping workspace: $name ($id) as it matches the destination eventhouse workspace."
        continue
    }
    
    Write-Host "Processing workspace: $name ($id)"
    & "$PSScriptRoot\add-source.ps1" -workspaceName $name -workspaceId $id
}
