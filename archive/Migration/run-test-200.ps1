[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceId ="611585cb-6332-4849-995e-efce839973f1",

    [Parameter(Mandatory = $false)]
    [string]$EventhouseName = "MonitoringEventhouse"
)

$ErrorActionPreference = "Stop"

# 1. Get Fabric Token
Write-Host "--- Step 1: Getting Fabric Token ---"
$fabricTokenScript = Join-Path $PSScriptRoot "..\get-Fabric-token.ps1"

$fabricToken = & $fabricTokenScript

if ([string]::IsNullOrWhiteSpace($fabricToken)) {
    Write-Error "Failed to retrieve Fabric Token."
    return
}
Write-Host "Fabric Token retrieved."

Write-Host "--- Step 6: Download Workspaces ---"
$listWorkspacesScript = Join-Path $PSScriptRoot "..\test-workspaces2.ps1"
#$listWorkspacesScript = Join-Path $PSScriptRoot "..\test-items.ps1"

1..200 | ForEach-Object {
    Write-Host "Running iteration $_..."
    & $listWorkspacesScript -AuthToken $fabricToken -VerifyOAP $false -WorkspaceId $WorkspaceId
    #Start-Sleep -Seconds 10
}
