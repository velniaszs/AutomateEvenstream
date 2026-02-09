[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceId = "611585cb-6332-4849-995e-efce839973f1", #WorkspaceId that hosts Monitoring Solution
    [Parameter(Mandatory = $false)]
    [string]$EventhouseName = "MonitoringEventhouse", #Name of the Eventhouse

    [Parameter(Mandatory = $false)]
    [string]$sourceWorkspaceName = "ab-test2", #Name of the workspace to be added

    [Parameter(Mandatory = $false)]
    [string]$sourceWorkspaceId = "af2b1ae0-5660-454c-9952-b01cffde1d2f", #WorkspaceId of the workspace to be added

    [Parameter(Mandatory = $false)]
    [string]$RegionName = "West US", #Region Name of the workspace capacity to be added

    [Parameter(Mandatory = $false)]
    [string]$capacityName = "sksdemofabric01" #Capacity Name of the workspace to be added
)

$ErrorActionPreference = "Stop"

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

Write-Host "--- Step 2: Creating folder for Capacity Region if not exists ---"
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
} else {
    Write-Host "Eventstream already exists. Skipping Step 4."
    $eventstreamId = $eventstreamCheck.Id
}

if (-not $eventstreamCheck.Exists) {
    Write-Host "New Eventstream created. Waiting for 1 minute before updating eventstreams..."
    Start-Sleep -Seconds 60
}

if ($eventstreamId -eq $null) {
    Write-Host "Eventstream ID is null. checking for Id again..."
    Write-Host "--- Step 3: Checking if Eventstream exists ---"
    $getEvenstreamIdScript = Join-Path $PSScriptRoot "\get-evenstream-id.ps1"
    $eventstreamCheck = & $getEvenstreamIdScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -EventstreamName $capacityName
    $eventstreamId = $eventstreamCheck.Id
}

Write-Host "--- Step 5: Getting Eventstream Definition ---"
$getESScript = Join-Path $PSScriptRoot "\get-eventstream-def.ps1"
& $getESScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -EventstreamId $eventstreamId -OutputFile "$PSScriptRoot\input\eventstream.json"

Write-Host "--- Checking if source workspace already exists in local definition ---"
$checkWsScript = Join-Path $PSScriptRoot "\check-evenstream-if-ws-exists.ps1"
$wsExists = & $checkWsScript -sourceWorkspaceName $sourceWorkspaceName -sourceWorkspaceId $sourceWorkspaceId -jsonPath "$PSScriptRoot\input\eventstream.json"

if (-not $wsExists) {
    Write-Host "--- Step 6: Adding workspace info to evenstream json file definition ---"
    $createEventstreamDataScript = Join-Path $PSScriptRoot "\create-eventstream-data.ps1"
    & $createEventstreamDataScript -sourceWorkspaceName $sourceWorkspaceName -sourceWorkspaceId $sourceWorkspaceId -jsonPath "$PSScriptRoot\input\eventstream.json" -capacityName $capacityName -destinationWorkspaceId $WorkspaceId -DatabaseId $databaseId

    if (-not $eventstreamCheck.Exists) {
        Write-Host "New Eventstream created. Waiting for 1 minute before updating eventstreams..."
        Start-Sleep -Seconds 60
    }

    Write-Host "--- Step 7: Updating Eventstream Definition ---"
    $updateESScript = Join-Path $PSScriptRoot "\update-eventstream.ps1"
    & $updateESScript -WorkspaceId $WorkspaceId -EventstreamId $eventstreamId -AuthToken $fabricToken -DefinitionFile "$PSScriptRoot\Output\$capacityName.json"
} else {
    Write-Host "Source workspace already exists in definition. Skipping Step 6 and 7."
}

Write-Host "--- All steps completed ---"
