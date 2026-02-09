[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [Parameter(Mandatory = $true)]
    [string]$EventstreamName,

    [Parameter(Mandatory = $true)]
    [string]$FolderId,

    [Parameter(Mandatory = $true)]
    [string]$capacityName
)

$ErrorActionPreference = "Stop"

Write-Host "Creating Eventstream '$EventstreamName' in Folder '$FolderId'..."
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { "." }
$createEventstreamScript = Join-Path $scriptRoot "create-eventstream.ps1"
try {
    $result = & $createEventstreamScript -WorkspaceId $WorkspaceId -DisplayName $EventstreamName -AuthToken $AuthToken -folderId $FolderId -capacityName $capacityName
    return @{
        Id      = $result
        Skipped = $false
    }
}
catch {
    throw "Failed to create eventstream '$EventstreamName'. Error: $_"
}
