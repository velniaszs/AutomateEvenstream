[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$MonWorkspaceId = "611585cb-6332-4849-995e-efce839973f1", #WorkspaceId that hosts Monitoring Solution
    [Parameter(Mandatory = $false)]
    [string]$MonEventhouseName = "MonitoringEventhouse", #Name of the Monitoring Solution Eventhouse

    [Parameter(Mandatory = $false)]
    [string]$AddWorkspaceName = "ab_demo_2", #Name of the workspace to be added

    [Parameter(Mandatory = $false)]
    [string]$AddWorkspaceId = "6660419a-a6f9-41ea-bd0f-597d1f3c519b", #WorkspaceId of the workspace to be added

    [Parameter(Mandatory = $false)]
    [string]$AddRegionName = "West US", #Region Name of the workspace capacity to be added

    [Parameter(Mandatory = $false)]
    [string]$AddCapacityName = "sksdemofabric01", #Capacity Name of the workspace to be added

    [Parameter(Mandatory = $false)]
    [bool]$AopEnabled = $true #Enabled or Disabled AOP setting for added workspace
)

$ErrorActionPreference = "Stop"

# Initialize variables to avoid contamination from previous runs
$wsExists = $false
$isNewEvenstream = $false
$eventstreamId = $null
$dbDetails = $null
$folderId = $null
$eventstreamCheck = $null

$AOPSetting = if ($AopEnabled) { "EnableWorkspaceOutboundAccessProtection" } else { "DisableWorkspaceOutboundAccessProtection" }

Write-Host "--- Step 0: Getting Fabric Token ---"
$fabricTokenScript = Join-Path $PSScriptRoot "..\get-Fabric-token.ps1"
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

Write-Host "--- Step 2: Creating folder for Capacity Region in Workspace: $AddRegionName ---"
$createfolderScript = Join-Path $PSScriptRoot "\create-region-folder.ps1"
$folderId = & $createfolderScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -RegionName $AddRegionName

Write-Host "--- Step 3: Checking if Eventstream exists ---"
$getEvenstreamIdScript = Join-Path $PSScriptRoot "\get-evenstream-id.ps1"
$eventstreamCheck = & $getEvenstreamIdScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -EventstreamName $AddCapacityName

if (-not $eventstreamCheck.Exists) {
    Write-Host "--- Step 4: Creating Blank Eventstream in designated folder if stream does not exists---"
    $createEventstreamScript = Join-Path $PSScriptRoot "\create-eventstream.ps1"
    $esResult = & $createEventstreamScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -FolderId $folderId -EventstreamName $AddCapacityName -capacityName $AddCapacityName
    $eventstreamId = $esResult.Id

    Write-Host "--- Waiting 60s ..."
    Start-Sleep -Seconds 60

    Write-Host "--- Step 4a: Checking if Eventstream exists ---"
    $getEvenstreamIdScript = Join-Path $PSScriptRoot "\get-evenstream-id.ps1"
    $eventstreamCheck = & $getEvenstreamIdScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -EventstreamName $AddCapacityName
    $eventstreamId = $eventstreamCheck.Id
    $isNewEvenstream = $true
} else {
    $eventstreamId = $eventstreamCheck.Id

    Write-Host "--- Step 5: Getting Eventstream Definition ---"
    $getESScript = Join-Path $PSScriptRoot "\get-eventstream-def.ps1"
    & $getESScript -WorkspaceId $MonWorkspaceId -AuthToken $fabricToken -EventstreamId $eventstreamId -OutputFile "$PSScriptRoot\input\eventstream.json"

    Write-Host "--- Step 5a:Checking if source workspace already exists in local definition ---"
    $checkWsScript = Join-Path $PSScriptRoot "\check-evenstream-if-ws-exists.ps1"
    $wsExists = & $checkWsScript -sourceWorkspaceName $AddWorkspaceName -sourceWorkspaceId $AddWorkspaceId -jsonPath "$PSScriptRoot\input\eventstream.json"
}

if (-not $wsExists) {
    if ($isNewEvenstream) {
        $jsonPath = Join-Path $PSScriptRoot "input\clean_evenstream.json"
    } else {
        $jsonPath = Join-Path $PSScriptRoot "input\eventstream.json"
    }

    Write-Host "--- Step 6: Adding workspace info to evenstream json file definition ---"
    $createEventstreamDataScript = Join-Path $PSScriptRoot "\create-eventstream-data.ps1"
    & $createEventstreamDataScript -sourceWorkspaceName $AddWorkspaceName -sourceWorkspaceId $AddWorkspaceId -jsonPath $jsonPath -capacityName $AddCapacityName -destinationWorkspaceId $MonWorkspaceId -DatabaseId $databaseId

    Write-Host "--- Step 7: Updating Eventstream Definition ---"
    $updateESScript = Join-Path $PSScriptRoot "\update-eventstream.ps1"
    & $updateESScript -WorkspaceId $MonWorkspaceId -EventstreamId $eventstreamId -AuthToken $fabricToken -DefinitionFile "$PSScriptRoot\Output\$AddCapacityName.json"
} else {
    Write-Host "--- Source workspace already exists in definition. Skipping Step 6 and 7. ---"
}

Write-Host "--- Step 8: Inserting Workspace Outbound Access Protection ---"
$aopScript = Join-Path $PSScriptRoot "..\PrepareEnvironment\InsertWorkspaceOutboundAccessProtection.ps1"
& $aopScript -WorkspaceId $AddWorkspaceId -WorkspaceName $AddWorkspaceName -AOPSetting $AOPSetting -KqlAuthToken $kqlToken -QueryUri $dbDetails.QueryServiceUri -DatabaseName $MonEventhouseName

Write-Host "--- All steps completed ---"
