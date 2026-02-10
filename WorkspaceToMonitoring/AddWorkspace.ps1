[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceId = "611585cb-6332-4849-995e-efce839973f1", #WorkspaceId that hosts Monitoring Solution
    [Parameter(Mandatory = $false)]
    [string]$EventhouseName = "MonitoringEventhouse", #Name of the Eventhouse

    [Parameter(Mandatory = $false)]
    [string]$sourceWorkspaceName = "ab_test5", #Name of the workspace to be added

    [Parameter(Mandatory = $false)]
    [string]$sourceWorkspaceId = "f085bd5f-211d-4e78-8795-0db1a1e464f1", #WorkspaceId of the workspace to be added

    [Parameter(Mandatory = $false)]
    [string]$RegionName = "West US", #Region Name of the workspace capacity to be added

    [Parameter(Mandatory = $false)]
    [string]$capacityName = "sksdemofabric01" #Capacity Name of the workspace to be added
)

$ErrorActionPreference = "Stop"

# Initialize variables to avoid contamination from previous runs
$wsExists = $false
$isNewEvenstream = $false

Write-Host "--- Step 0: Getting Fabric Token ---"
$fabricTokenScript = Join-Path $PSScriptRoot "..\get-Fabric-token.ps1"

$fabricToken = & $fabricTokenScript

if ([string]::IsNullOrWhiteSpace($fabricToken)) {
    Write-Error "Failed to retrieve Fabric Token."
    return
}

Write-Host "--- Step 1: Getting Eventhouse Database ID ---"
$getEventhouseDbIdScript = Join-Path $PSScriptRoot "\get-eventhouse-db-id.ps1"
$databaseId = & $getEventhouseDbIdScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -EventhouseName $EventhouseName

Write-Host "--- Step 2: Creating folder for Capacity Region in Workspace: $RegionName ---"
$createfolderScript = Join-Path $PSScriptRoot "\create-region-folder.ps1"
$folderId = & $createfolderScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -RegionName $RegionName

Write-Host "--- Step 3: Checking if Eventstream exists ---"
$getEvenstreamIdScript = Join-Path $PSScriptRoot "\get-evenstream-id.ps1"
$eventstreamCheck = & $getEvenstreamIdScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -EventstreamName $capacityName

if (-not $eventstreamCheck.Exists) {
    Write-Host "--- Step 4: Creating Blank Eventstream in designated folder if stream does not exists---"
    $createfolderScript = Join-Path $PSScriptRoot "\create-eventstream.ps1"
    $esResult = & $createfolderScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -FolderId $folderId -EventstreamName $capacityName -capacityName $capacityName
    $eventstreamId = $esResult.Id

    Write-Host "--- Waiting 60s ..."
    Start-Sleep -Seconds 60

    Write-Host "--- Step 4a: Checking if Eventstream exists ---"
    $getEvenstreamIdScript = Join-Path $PSScriptRoot "\get-evenstream-id.ps1"
    $eventstreamCheck = & $getEvenstreamIdScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -EventstreamName $capacityName
    $eventstreamId = $eventstreamCheck.Id
    $isNewEvenstream = $true
} else {
    $eventstreamId = $eventstreamCheck.Id

    Write-Host "--- Step 5: Getting Eventstream Definition ---"
    $getESScript = Join-Path $PSScriptRoot "\get-eventstream-def.ps1"
    & $getESScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -EventstreamId $eventstreamId -OutputFile "$PSScriptRoot\input\eventstream.json"

    Write-Host "--- Step 5a:Checking if source workspace already exists in local definition ---"
    $checkWsScript = Join-Path $PSScriptRoot "\check-evenstream-if-ws-exists.ps1"
    $wsExists = & $checkWsScript -sourceWorkspaceName $sourceWorkspaceName -sourceWorkspaceId $sourceWorkspaceId -jsonPath "$PSScriptRoot\input\eventstream.json"
}

if (-not $wsExists) {
    if ($isNewEvenstream) {
        $jsonPath = Join-Path $PSScriptRoot "input\clean_evenstream.json"
    } else {
        $jsonPath = Join-Path $PSScriptRoot "input\eventstream.json"
    }

    Write-Host "--- Step 6: Adding workspace info to evenstream json file definition ---"
    $createEventstreamDataScript = Join-Path $PSScriptRoot "\create-eventstream-data.ps1"
    & $createEventstreamDataScript -sourceWorkspaceName $sourceWorkspaceName -sourceWorkspaceId $sourceWorkspaceId -jsonPath $jsonPath -capacityName $capacityName -destinationWorkspaceId $WorkspaceId -DatabaseId $databaseId

    Write-Host "--- Step 7: Updating Eventstream Definition ---"
    $updateESScript = Join-Path $PSScriptRoot "\update-eventstream.ps1"
    & $updateESScript -WorkspaceId $WorkspaceId -EventstreamId $eventstreamId -AuthToken $fabricToken -DefinitionFile "$PSScriptRoot\Output\$capacityName.json"
} else {
    Write-Host "Source workspace already exists in definition. Skipping Step 6 and 7."
}

Write-Host "--- All steps completed ---"
