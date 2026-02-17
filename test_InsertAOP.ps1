Write-Host "--- Step 0: Getting KQL Token ---"
$kqlTokenScript = Join-Path $PSScriptRoot "get-kql-token.ps1"
$kqlToken = & $kqlTokenScript

if ([string]::IsNullOrWhiteSpace($kqlToken)) {
    Write-Error "Failed to retrieve KQL Token."
    return
}

$aopScript = Join-Path $PSScriptRoot "PrepareEnvironment\InsertWorkspaceOutboundAccessProtection.ps1"

$params = @{
    WorkspaceId   = "3c22899f-9519-4bf8-852a-87df0f0bc02c"
    WorkspaceName = "ab_demo_3"
    AOPSetting    = "DisableWorkspaceOutboundAccessProtection"
    KqlAuthToken  = $kqlToken
    QueryUri      = "https://trd-6uegjpfbf030eemxtw.z1.kusto.fabric.microsoft.com"
    DatabaseName  = "MonitoringEventhouse"
}

#Write-Host "Calling InsertWorkspaceOutboundAccessProtection.ps1 with parameters:"
#$params.Keys | ForEach-Object { Write-Host "  $($_): $($params[$_])" }

& $aopScript @params
