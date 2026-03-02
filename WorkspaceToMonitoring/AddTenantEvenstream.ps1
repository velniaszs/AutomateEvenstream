[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$MonWorkspaceId = "611585cb-6332-4849-995e-efce839973f1", #WorkspaceId that hosts Monitoring Solution
    [Parameter(Mandatory = $false)]
    [string]$MonEventhouseName = "MonitoringEventhouse", #Name of the Monitoring Solution Eventhouse

    [Parameter(Mandatory = $false)]
    [string]$sourceTenantName = "TenantWorkspaceEvents", #Name of the workspace to be added

    [Parameter(Mandatory = $false)]
    [string]$AddTenantId = "9e929790-272d-4977-a2ab-301443c11ece", #WorkspaceId of the workspace to be added

    [Parameter(Mandatory = $false)]
    [string]$AddRegionName = "Eventstream", #Region Name of the workspace capacity to be added

    [Parameter(Mandatory = $false)]
    [string]$EventstreamName = "TenantLevelWorkspaceEvents" #Capacity Name of the workspace to be added
)

$ErrorActionPreference = "Stop"

# Initialize variables to avoid contamination from previous runs
$wsExists = $false
$isNewEvenstream = $false
$eventstreamId = $null
$dbDetails = $null
$folderId = $null
$eventstreamCheck = $null

Write-Host "--- Step 0: Getting Fabric Token ---"
$fabricTokenScript = Join-Path $PSScriptRoot "..\get-Fabric-token-user.ps1"
$fabricToken = & $fabricTokenScript


if ([string]::IsNullOrWhiteSpace($fabricToken)) {
    Write-Error "Failed to retrieve Fabric Token."
    return
}

Write-Host "--- Step 0: Getting KQL Token ---"
$kqlTokenScript = Join-Path $PSScriptRoot "..\get-kql-token.ps1"
$kqlToken = & $kqlTokenScript

if ([string]::IsNullOrWhiteSpace($fabricToken)) {
    Write-Error "Failed to retrieve Fabric Token."
    return
}

if ([string]::IsNullOrWhiteSpace($kqlToken)) {
    Write-Error "Failed to retrieve KQL Token."
    return
}

Write-Host "--- Step 1: Getting Eventhouse Database ID ---"
$getEventhouseDbIdScript = Join-Path $PSScriptRoot "\get-eventhouse-db-id.ps1"
$dbDetails = & $getEventhouseDbIdScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -EventhouseName $MonEventhouseName
$databaseId = $dbDetails.Id

Write-Host "--- Step 2: Creating folder for Eventstream in Workspace: $AddRegionName ---"
$createfolderScript = Join-Path $PSScriptRoot "\create-region-folder.ps1"
$folderId = & $createfolderScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -RegionName $AddRegionName

Write-Host "--- Step 3: Checking if Eventstream exists ---"
$getEvenstreamIdScript = Join-Path $PSScriptRoot "\get-evenstream-id.ps1"
$eventstreamCheck = & $getEvenstreamIdScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -EventstreamName $EventstreamName

if (-not $eventstreamCheck.Exists) {
    Write-Host "--- Step 4: Creating Blank Eventstream if stream does not exists---"
    $createEventstreamScript = Join-Path $PSScriptRoot "\create-eventstream.ps1"
    $esResult = & $createEventstreamScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -FolderId $folderId -EventstreamName $EventstreamName -capacityName $EventstreamName
    $eventstreamId = $esResult.Id

    Write-Host "--- Waiting 30s ..."
    Start-Sleep -Seconds 30

    Write-Host "--- Step 4a: Checking if Eventstream exists ---"
    $getEvenstreamIdScript = Join-Path $PSScriptRoot "\get-evenstream-id.ps1"
    $eventstreamCheck = & $getEvenstreamIdScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -EventstreamName $EventstreamName
    $eventstreamId = $eventstreamCheck.Id
    $isNewEvenstream = $true
} else {
    $eventstreamId = $eventstreamCheck.Id

    Write-Host "--- Step 5: Getting Eventstream Definition ---"
    $getESScript = Join-Path $PSScriptRoot "\get-eventstream-def.ps1"
    & $getESScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -EventstreamId $eventstreamId -OutputFile "$PSScriptRoot\input\eventstream.json"

    Write-Host "--- Step 5a:Checking if source workspace already exists in local definition ---"
    $checkWsScript = Join-Path $PSScriptRoot "\check-evenstream-if-ws-exists.ps1"
    $wsExists = & $checkWsScript -sourceWorkspaceName $sourceTenantName -sourceWorkspaceId $AddTenantId -jsonPath "$PSScriptRoot\input\eventstream.json"
}

if (-not $wsExists) {
    if ($isNewEvenstream) {
        $jsonPath = Join-Path $PSScriptRoot "input\clean_evenstream.json"
    } else {
        $jsonPath = Join-Path $PSScriptRoot "input\eventstream.json"
    }

    Write-Host "--- Step 6: Adding workspace info to evenstream json file definition ---"
    $createEventstreamDataScript = Join-Path $PSScriptRoot "\create-eventstream-data-tenant.ps1"
    & $createEventstreamDataScript -jsonPath $jsonPath -capacityName $EventstreamName -destinationWorkspaceId $MonWorkspaceId -DatabaseId $databaseId

    Write-Host "--- Step 7: Updating Eventstream Definition ---"
    $updateESScript = Join-Path $PSScriptRoot "\update-eventstream.ps1"
    & $updateESScript -WorkspaceId $MonWorkspaceId -EventstreamId $eventstreamId -AuthToken $fabricToken -DefinitionFile "$PSScriptRoot\Output\$EventstreamName.json"
} else {
    Write-Host "--- Source workspace already exists in definition. Skipping Step 6 and 7. ---"
}

Write-Host "--- All steps completed ---"
