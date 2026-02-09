[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken
)

$ErrorActionPreference = "Stop"


# Get existing Eventstreams in the workspace
$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}
$url = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses"
try {
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
    $response | ConvertTo-Json -Depth 10
}
catch {
    Write-Warning "Error: $_"
}