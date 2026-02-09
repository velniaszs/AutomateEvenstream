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
$fabricTokenScript = Join-Path $PSScriptRoot "..\get-Fabric-token2.ps1"

$fabricToken = & $fabricTokenScript

if ([string]::IsNullOrWhiteSpace($fabricToken)) {
    Write-Error "Failed to retrieve Fabric Token."
    return
}
Write-Host "Fabric Token retrieved."

#$listWorkspacesScript = Join-Path $PSScriptRoot "..\test-workspaces2.ps1"
#$listWorkspacesScript = Join-Path $PSScriptRoot "..\test-items.ps1"
#$listWorkspacesScript = Join-Path $PSScriptRoot "..\test-wbi-wsp.ps1"
$createEventhouseScript = Join-Path $PSScriptRoot "..\create-eventhouse.ps1"
& $createEventhouseScript -WorkspaceId $WorkspaceId -AuthToken $fabricToken -DisplayName $EventhouseName

#Write-Host "--- Step 2: Get Activity Events for past 5 days ---"
#$activityEventsScript = Join-Path $PSScriptRoot "..\test-activityevents.ps1"

# Power BI Activity Events API expects requires dates wrapped in single quotes
$dateFormat = "yyyy-MM-ddTHH:mm:ss.fffZ"
$startDateTime = "'" + (Get-Date).AddHours(-5).ToUniversalTime().ToString($dateFormat) + "'"
$endDateTime = "'" + (Get-Date).ToUniversalTime().ToString($dateFormat) + "'"
$today = (Get-Date).Date
#$startDateTime = "'" + $today.AddDays(-1).AddHours(20).AddMinutes(30).ToUniversalTime().ToString($dateFormat) + "'"
#$endDateTime = "'" + $today.AddMinutes(30).ToUniversalTime().ToString($dateFormat) + "'"

#& $activityEventsScript -AuthToken $fabricToken -StartDateTime $startDateTime -EndDateTime $endDateTime

