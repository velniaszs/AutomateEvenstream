[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceId = "611585cb-6332-4849-995e-efce839973f1", #WorkspaceId that hosts Monitoring Solution
    [Parameter(Mandatory = $false)]
    [string]$EventhouseName = "MonitoringEventhouse", #Name of the Eventhouse

    [Parameter(Mandatory = $false)]
    [string]$rmWorkspaceName = "ab_test2", #Name of the workspace to be removed

    [Parameter(Mandatory = $false)]
    [string]$rmWorkspaceId = "af2b1ae0-5660-454c-9952-b01cffde1d2f", #WorkspaceId of the workspace to be removed

    [Parameter(Mandatory = $false)]
    [string]$capacityName = "sksdemofabric01" #Capacity Name of the workspace to be added
)

$ErrorActionPreference = "Stop"

# Initialize variables to avoid contamination from previous runs
$wsExists = $false
$evenstreamDeleted = $false

Write-Host "--- Step 1: Getting Fabric Token ---"
$fabricTokenScript = Join-Path $PSScriptRoot "..\get-Fabric-token.ps1"

$fabricToken = & $fabricTokenScript

if ([string]::IsNullOrWhiteSpace($fabricToken)) {
    Write-Error "Failed to retrieve Fabric Token."
    return
}

Write-Host "--- Step 2: Checking if Eventstream exists ---"
$getEvenstreamIdScript = Join-Path $PSScriptRoot "\get-evenstream-id.ps1"
$eventstreamCheck = & $getEvenstreamIdScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -EventstreamName $capacityName

if (-not $eventstreamCheck.Exists) {
    Write-Error "--- Evenstream does not exist---"
    return
} else {
    $eventstreamId = $eventstreamCheck.Id
}

Write-Host "--- Step 3: Getting Eventstream Definition ---"
$getESScript = Join-Path $PSScriptRoot "\get-eventstream-def.ps1"
& $getESScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -EventstreamId $eventstreamId -OutputFile "$PSScriptRoot\input\eventstream.json"

Write-Host "--- Step 4: Checking if workspace to be deleted exists in local evenstream definition ---"
$checkWsScript = Join-Path $PSScriptRoot "\check-evenstream-if-ws-exists.ps1"
$wsExists = & $checkWsScript -sourceWorkspaceName $rmWorkspaceName -sourceWorkspaceId $rmWorkspaceId -jsonPath "$PSScriptRoot\input\eventstream.json"

if ($wsExists) {
    Write-Host "--- Step 5: Removing workspace info from evenstream json file definition ---"
    $createEventstreamDataScript = Join-Path $PSScriptRoot "\remove-eventstream-data.ps1"
    $evenstreamDeleted = & $createEventstreamDataScript -sourceWorkspaceName $rmWorkspaceName -jsonPath "$PSScriptRoot\input\eventstream.json" -capacityName $capacityName -destinationWorkspaceId $WorkspaceId -AuthToken $fabricToken

    IF (-not $evenstreamDeleted) {
    Write-Host "--- Step 6: Updating Eventstream Definition ---"
    $updateESScript = Join-Path $PSScriptRoot "\update-eventstream.ps1"
    & $updateESScript -WorkspaceId $WorkspaceId -EventstreamId $eventstreamId -AuthToken $fabricToken -DefinitionFile "$PSScriptRoot\Output\$capacityName.json"
    }
} else {
    Write-Host "Workspace does not exist in definition. Skipping Step 5 and 6."
}

Write-Host "--- All steps completed ---"
