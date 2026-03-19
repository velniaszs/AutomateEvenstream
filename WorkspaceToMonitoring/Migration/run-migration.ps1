[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId='',

    [Parameter(Mandatory = $false)]
    [string]$ClientId = '',

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = '',

    [Parameter(Mandatory = $false)]
    [string]$MonWorkspaceId = "611585cb-6332-4849-995e-efce839973f1",

    [Parameter(Mandatory = $false)]
    [string]$MonEventhouseName = "MonitoringEventhouse"
)

$ErrorActionPreference = "Stop"

# 1. Get Fabric Token
Write-Host "--- Step 0: Getting Fabric Token ---"
$fabricTokenScript = Join-Path $PSScriptRoot "..\..\get-Fabric-token.ps1"
$fabricToken = & $fabricTokenScript -tenantId $TenantId -clientId $ClientId -client_secret $ClientSecret

if ([string]::IsNullOrWhiteSpace($fabricToken)) {
    Write-Error "Failed to retrieve Fabric Token."
    return
}
Write-Host "Fabric Token retrieved."

# 2. Get KQL Token
Write-Host "--- Step 0: Getting KQL Token ---"
$kqlTokenScript = Join-Path $PSScriptRoot "..\..\get-kql-token.ps1"
$kqlToken = & $kqlTokenScript -tenantId $TenantId -clientId $ClientId -client_secret $ClientSecret

if ([string]::IsNullOrWhiteSpace($kqlToken)) {
    Write-Error "Failed to retrieve KQL Token."
    return
}
Write-Host "KQL Token retrieved."
#Write-Host $kqlToken

Write-Host "--- Step 1: Getting Eventhouse Database ID ---"
$getEventhouseDbIdScript = Join-Path $PSScriptRoot "..\get-eventhouse-db-id.ps1"
$dbDetails = & $getEventhouseDbIdScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -EventhouseName $MonEventhouseName
$databaseId = $dbDetails.Id

Write-Host "--- Step 2: Download Capacities ---"
$listCapacitiesScript = Join-Path $PSScriptRoot "\list-capacities.ps1"
& $listCapacitiesScript -AuthToken $fabricToken

Write-Host "--- Step 3: Download Workspaces ---"
$listWorkspacesScript = Join-Path $PSScriptRoot "\list-workspaces.ps1"
& $listWorkspacesScript -AuthToken $fabricToken -VerifyOAP $false -WorkspaceId $MonWorkspaceId

Write-Host "--- Step 4: Join Workspaces and Capacities ---"
$joinScript = Join-Path $PSScriptRoot "\join-workspaces-capacities.ps1"
& $joinScript -GroupSize 48 #will be 48 in the future. 5 is for testing purposes

Write-Host "--- Step 5: Create Folders for each Capacity Region ---"
$createFolderScript = Join-Path $PSScriptRoot "\create-region-folders.ps1"
& $createFolderScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken

Write-Host "--- Step 6: Get folders, where we will create Evenstreams ---"
$getfoldersScript = Join-Path $PSScriptRoot "\get-folders.ps1"
& $getfoldersScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken

Write-Host "--- Step 7: Create Blank Eventstreams in designated folders ---"
$createEventstreamsScript = Join-Path $PSScriptRoot "\create-all-evenstreams-in-folders.ps1"
& $createEventstreamsScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken

Write-Host "--- Step 8: Create Eventstream Data Files ---"
$createEventstreamDataScript = Join-Path $PSScriptRoot "\create-evenstreams-data.ps1"
& $createEventstreamDataScript -WorkspaceId $MonWorkspaceId -DatabaseName "MonitoringEventhouse" -DatabaseId $databaseId

Write-Host "Waiting for 1 minute before updating eventstreams..."
Start-Sleep -Seconds 60

Write-Host "--- Step 9: Update Eventstreams Data ---"
$updateAllEventstreamsScript = Join-Path $PSScriptRoot "..\update-all-eventstreams.ps1"
& $updateAllEventstreamsScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken

Write-Host "--- All steps completed ---"
