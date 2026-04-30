<#
.SYNOPSIS
    Continuous streaming generator for WorkspaceLogs - simulates live Fabric
    item events while the pipeline runs, for streaming load / soak tests.

.DESCRIPTION
    Pushes synthetic WorkspaceLogs events into the test Eventhouse using the
    streaming ingestion endpoint:
        POST {QueryUri}/v1/rest/ingest/{db}/WorkspaceLogs?streamFormat=JSON

    Streaming ingestion gives sub-second latency and is the closest analog to
    a live event source. Reuses workspace GUIDs from _TestWorkspacePool so
    joins remain meaningful while the soak runs.

    Distributions:
        type: 80% Microsoft.Fabric.ItemCreateSucceeded / 20% ...ItemDeleteSucceeded
        data_itemKind: chosen from a list keyed off the workspace's
                       DataverseWorkspace.OAPActivity value:
                         EnableWorkspaceOutboundAccessProtection  -> protected list
                         DisableWorkspaceOutboundAccessProtection -> unprotected list
                         (unknown / null)                         -> union of both
        Plus 0-1 "flagged" Notebook events injected per HTTP batch
        (any workspace, regardless of OAP state).

.PARAMETER QueryUri
    Eventhouse query URI (the streaming-ingest endpoint lives on the same host).

.PARAMETER DatabaseName
    Eventhouse database name.

.PARAMETER KqlAuthToken
    Bearer token (use authenticate\get-kql-token.ps1).

.PARAMETER Profile
    steady   - constant -RatePerSecond for -DurationMinutes
    burst    - alternating BurstRate for BurstSeconds, then idle for IdleSeconds
    ramp     - linear ramp from RatePerSecond to BurstRate over the duration

.PARAMETER RatePerSecond
    Steady-state events per second. Default 100.

.PARAMETER BurstRate
    Peak EPS for 'burst' or 'ramp' profile. Default 1000.

.PARAMETER BurstSeconds / IdleSeconds
    'burst' profile timing.

.PARAMETER DurationMinutes
    Total wall-clock duration. Default 60.

.PARAMETER BatchSize
    Events per HTTP POST. Default 200. Larger = higher throughput / less overhead.

.PARAMETER WorkspacePoolSize
    How many workspace GUIDs to cache locally on startup. Default 20000
    (matches _TestWorkspacePool).

.EXAMPLE
    .\Testing\StressTest\Run-StreamingLoad.ps1 `
        -QueryUri 'https://trd-xxx.z1.kusto.fabric.microsoft.com' `
        -DatabaseName 'MonitoringEventhouseStress' `
        -KqlAuthToken $token `
        -LoadProfile steady -RatePerSecond 200 -DurationMinutes 60

.NOTES
    Streaming ingestion must be ENABLED on the database AND on the
    WorkspaceLogs table:
        .alter database <db> policy streamingingestion enable
        .alter table WorkspaceLogs policy streamingingestion enable
    See: https://learn.microsoft.com/azure/data-explorer/ingest-data-streaming
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $QueryUri,
    [Parameter(Mandatory = $true)] [string] $DatabaseName,
    [Parameter(Mandatory = $true)] [string] $KqlAuthToken,

    [ValidateSet('steady','burst','ramp')]
    [string] $LoadProfile    = 'steady',

    [int] $RatePerSecond     = 100,
    [int] $BurstRate         = 1000,
    [int] $BurstSeconds      = 30,
    [int] $IdleSeconds       = 60,
    [int] $DurationMinutes   = 60,
    [int] $BatchSize         = 200,
    [int] $WorkspacePoolSize = 20000
)

$ErrorActionPreference = 'Stop'

$queryUri2  = "$QueryUri/v1/rest/query"
$ingestUri  = "$QueryUri/v1/rest/ingest/$DatabaseName/WorkspaceLogs?streamFormat=JSON&mappingName=WorkspaceLogs_mapping"

$jsonHeaders = @{
    Authorization  = "Bearer $KqlAuthToken"
    'Content-Type' = 'application/json'
}
$ingestHeaders = @{
    Authorization  = "Bearer $KqlAuthToken"
    'Content-Type' = 'application/json'
}

# ---------------------------------------------------------------------------
# Pull workspace pool locally once so the hot loop has zero query overhead.
# ---------------------------------------------------------------------------
Write-Host "Loading workspace pool (top $WorkspacePoolSize) joined with DataverseWorkspace.OAPActivity..." -ForegroundColor Cyan
$poolKql = @"
_TestWorkspacePool
| take $WorkspacePoolSize
| join kind=leftouter (
    DataverseWorkspace
    | summarize arg_max(ingestion_time(), OAPActivity) by WorkspaceId
  ) on WorkspaceId
| project WorkspaceId, WorkspaceName, OAPActivity
"@
$poolBody = @{
    csl = $poolKql
    db  = $DatabaseName
} | ConvertTo-Json
$resp = Invoke-RestMethod -Uri $queryUri2 -Method Post -Headers $jsonHeaders -Body $poolBody -TimeoutSec 600
$primary = $resp.Tables | Where-Object { $_.TableName -eq 'Table_0' -or $_.Name -eq 'PrimaryResult' } | Select-Object -First 1
if (-not $primary -or $primary.Rows.Count -eq 0) {
    throw "_TestWorkspacePool is empty. Run Run-StressTestBackfill.ps1 -Phases Pool first."
}
$pool = @($primary.Rows | ForEach-Object {
    [pscustomobject]@{
        WorkspaceId   = $_[0]
        WorkspaceName = $_[1]
        OAPActivity   = $_[2]
    }
})
$poolCount = $pool.Count
$enabledCount  = @($pool | Where-Object { $_.OAPActivity -eq 'EnableWorkspaceOutboundAccessProtection' }).Count
$disabledCount = @($pool | Where-Object { $_.OAPActivity -eq 'DisableWorkspaceOutboundAccessProtection' }).Count
Write-Host ("Loaded {0} workspaces (OAP enabled: {1}, disabled: {2}, other/null: {3})." -f `
    $poolCount, $enabledCount, $disabledCount, ($poolCount - $enabledCount - $disabledCount)) -ForegroundColor Green

# Item kinds allowed when OAP is ENABLED on the workspace.
$itemKindsOapEnabled = @(
    'Lakehouse','Notebook','SparkJobDefinition','Environment','Warehouse',
    'DataFlow','DataPipeline','CopyJob','MirroredDatabase','SQLEndpoint',
    'VariableLibrary','SqlAnalyticsEndpoint','Experiment','MlModel'
)

# Item kinds allowed when OAP is DISABLED on the workspace.
$itemKindsOapDisabled = @(
    'VariableLibrary','SemanticModel','Report','App','Dashboard','Scorecard',
    'KQLDashboard','Eventstream','cosmosdb','azuredb','SqlAnalyticsEndpoint',
    'MountedDataFactory','DataFlowGen1'
)

# Fallback (workspace OAPActivity unknown / null) - union of both lists.
$itemKindsAny = @($itemKindsOapEnabled + $itemKindsOapDisabled | Select-Object -Unique)

$rng = [System.Random]::new()

function New-Event {
    param(
        # When set, force this itemKind (used to inject flagged Notebook events).
        [string] $ForceKind
    )
    $ws = $pool[$rng.Next(0, $poolCount)]
    $isCreate = ($rng.NextDouble() -lt 0.8)
    $type   = if ($isCreate) { 'Microsoft.Fabric.ItemCreateSucceeded' } else { 'Microsoft.Fabric.ItemDeleteSucceeded' }
    $itemId = [guid]::NewGuid().ToString()

    if ($ForceKind) {
        $kind = $ForceKind
    }
    else {
        switch ($ws.OAPActivity) {
            'EnableWorkspaceOutboundAccessProtection'  { $kindList = $itemKindsOapEnabled  }
            'DisableWorkspaceOutboundAccessProtection' { $kindList = $itemKindsOapDisabled }
            default                                    { $kindList = $itemKindsAny         }
        }
        $kind = $kindList[$rng.Next(0, $kindList.Length)]
    }

    [pscustomobject]@{
        type                       = $type
        datacontenttype            = 'application/json'
        id                         = [guid]::NewGuid().ToString()
        time                       = (Get-Date).ToUniversalTime().ToString('o')
        dataschemaversion          = 1.0
        subject                    = "/workspaces/$($ws.WorkspaceId)/items/$itemId"
        source                     = $ws.WorkspaceId
        specversion                = 1.0
        data = [pscustomobject]@{
            workspaceId            = $ws.WorkspaceId
            workspaceName          = $ws.WorkspaceName
            itemName               = "stream_item_$itemId"
            itemId                 = $itemId
            itemKind               = $kind
            executingPrincipalId   = [guid]::NewGuid().ToString()
            executingPrincipalType = 'User'
        }
    }
}

function Send-Batch {
    param([int]$Count)
    if ($Count -le 0) { return 0 }

    # Inject 0 or 1 "flagged" Notebook event per batch (any workspace, any OAP state).
    $flaggedExtra = if ($rng.NextDouble() -lt 0.5) { 1 } else { 0 }
    $totalDocs    = $Count + $flaggedExtra

    # Build NDJSON payload (one JSON document per line).
    $sb = [System.Text.StringBuilder]::new($totalDocs * 400)
    for ($k = 0; $k -lt $Count; $k++) {
        $null = $sb.AppendLine( ((New-Event) | ConvertTo-Json -Compress -Depth 6) )
    }
    for ($k = 0; $k -lt $flaggedExtra; $k++) {
        $null = $sb.AppendLine( ((New-Event -ForceKind 'Notebook') | ConvertTo-Json -Compress -Depth 6) )
    }
    try {
        Invoke-RestMethod -Uri $ingestUri -Method Post -Headers $ingestHeaders `
            -Body $sb.ToString() -TimeoutSec 60 | Out-Null
        return $totalDocs
    } catch {
        Write-Warning "Ingest batch failed: $($_.Exception.Message)"
        return 0
    }
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
$totalSeconds = $DurationMinutes * 60
$startUtc     = Get-Date
$endUtc       = $startUtc.AddSeconds($totalSeconds)
$totalSent    = 0
$secCount     = 0

Write-Host "`nProfile: $LoadProfile  Duration: ${DurationMinutes}m  BatchSize: $BatchSize" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop early.`n" -ForegroundColor Yellow

while ((Get-Date) -lt $endUtc) {
    $secStart = Get-Date

    # Resolve target EPS for this second
    switch ($LoadProfile) {
        'steady' {
            $eps = $RatePerSecond
        }
        'burst' {
            $cyc      = $BurstSeconds + $IdleSeconds
            $posInCyc = $secCount % $cyc
            $eps = if ($posInCyc -lt $BurstSeconds) { $BurstRate } else { 0 }
        }
        'ramp' {
            $progress = ((Get-Date) - $startUtc).TotalSeconds / $totalSeconds
            $eps = [int]($RatePerSecond + ($BurstRate - $RatePerSecond) * $progress)
        }
    }

    # Send in batches inside this 1-second window
    $remaining = $eps
    $sentThisSec = 0
    while ($remaining -gt 0) {
        $thisBatch = [Math]::Min($BatchSize, $remaining)
        $sentThisSec += (Send-Batch -Count $thisBatch)
        $remaining   -= $thisBatch
    }
    $totalSent += $sentThisSec
    $secCount++

    if (($secCount % 10) -eq 0) {
        $elapsed = ((Get-Date) - $startUtc).TotalSeconds
        $avgEps  = [int]($totalSent / [Math]::Max($elapsed,1))
        Write-Host ("  t={0,5}s  target={1,5} EPS  sent_last_sec={2,5}  total={3,9}  avg={4,5} EPS" -f `
            ([int]$elapsed), $eps, $sentThisSec, $totalSent, $avgEps)
    }

    # Pace to ~1 second per iteration
    $elapsedSec = ((Get-Date) - $secStart).TotalMilliseconds
    $sleep = 1000 - $elapsedSec
    if ($sleep -gt 0) { Start-Sleep -Milliseconds ([int]$sleep) }
}

$elapsedTotal = ((Get-Date) - $startUtc).TotalSeconds
Write-Host "`nStream complete. Sent $totalSent events in ${elapsedTotal}s ($([int]($totalSent/$elapsedTotal)) avg EPS)." -ForegroundColor Green
