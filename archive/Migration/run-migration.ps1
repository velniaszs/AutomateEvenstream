[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceId = "611585cb-6332-4849-995e-efce839973f1",

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

# 2. Get KQL Token
Write-Host "--- Step 2: Getting KQL Token ---"
$kqlTokenScript = Join-Path $PSScriptRoot "..\get-kql-token.ps1"
# get-kql-token.ps1 DOES Write-Output.
$kqlToken = & $kqlTokenScript

if ([string]::IsNullOrWhiteSpace($kqlToken)) {
    Write-Error "Failed to retrieve KQL Token."
    return
}
Write-Host "KQL Token retrieved."
#Write-Host $kqlToken

# 3. Create Eventhouse
Write-Host "--- Step 3: Creating Eventhouse ---"
$createEventhouseScript = Join-Path $PSScriptRoot "..\create-eventhouse.ps1"
& $createEventhouseScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -DisplayName $EventhouseName


# 4. Create Table
Write-Host "--- Step 4: Creating Eventhouse Table ---"
$createTableScript = Join-Path $PSScriptRoot "..\create-table.ps1"
$DatabaseId = & $createTableScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -KqlAuthToken $kqlToken -EventhouseName $EventhouseName

Write-Host "--- Step 5: Download Capacities ---"
$listCapacitiesScript = Join-Path $PSScriptRoot "..\list-capacities.ps1"
& $listCapacitiesScript -AuthToken $fabricToken

Write-Host "--- Step 6: Download Workspaces ---"
$listWorkspacesScript = Join-Path $PSScriptRoot "..\list-workspaces.ps1"
& $listWorkspacesScript -AuthToken $fabricToken -VerifyOAP $false -WorkspaceId $WorkspaceId

Write-Host "--- Step 7: Join Workspaces and Capacities ---"
$joinScript = Join-Path $PSScriptRoot "..\join-workspaces-capacities.ps1"
& $joinScript -GroupSize 5 #will be 48 in the future. 5 is for testing purposes

Write-Host "--- Step 8: Create Folders for each Capacity Region ---"
$createFolderScript = Join-Path $PSScriptRoot "..\create-region-folders.ps1"
& $createFolderScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken

Write-Host "--- Step 9: Get folders, where we will create Evenstreams ---"
$getfoldersScript = Join-Path $PSScriptRoot "..\get-folders.ps1"
& $getfoldersScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken

Write-Host "--- Step 10: Create Blank Eventstreams in designated folders ---"
$createEventstreamsScript = Join-Path $PSScriptRoot "..\create-all-evenstreams-in-folders.ps1"
& $createEventstreamsScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken

Write-Host "--- Step 11: Create Eventstream Data Files ---"
$createEventstreamDataScript = Join-Path $PSScriptRoot "..\create-evenstream-data.ps1"
& $createEventstreamDataScript -WorkspaceId $WorkspaceId -DatabaseName "MonitoringEventhouse" -DatabaseId $DatabaseId

Write-Host "Waiting for 1 minute before updating eventstreams..."
Start-Sleep -Seconds 60

Write-Host "--- Step 12: Update Eventstreams Data ---"
$updateAllEventstreamsScript = Join-Path $PSScriptRoot "..\update-all-eventstreams.ps1"
& $updateAllEventstreamsScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken

Write-Host "--- All steps completed ---"
