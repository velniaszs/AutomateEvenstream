<#
.SYNOPSIS
    Benchmarks pipeline KQL queries against the Eventhouse and stores
    timing/CPU/memory metrics for before-vs-after comparison.

.DESCRIPTION
    For each *.kql file in -QueryFolder, executes the query -Iterations times,
    tagging every request with a unique ClientRequestId of the form
        bench:<RunLabel>:<QueryName>:<iter>
    After all runs, fetches `.show queries` filtered by that prefix and
    appends durations / CPU / memory / cache stats to the BenchmarkResults
    table for later comparison across phases (baseline / post-load / under-stream).

    Uses the Eventhouse REST API directly (same pattern as
    WorkspaceToMonitoring scripts), so no extra modules required.

.PARAMETER QueryUri
    Eventhouse query URI.

.PARAMETER DatabaseName
    Eventhouse database name.

.PARAMETER KqlAuthToken
    Bearer token (use authenticate\get-kql-token.ps1).

.PARAMETER QueryFolder
    Folder containing .kql files to benchmark. Defaults to the sibling
    'Queries' folder next to this script.

.PARAMETER Iterations
    How many times to run each query. Default 30 (sufficient for P50/P95).

.PARAMETER RunLabel
    Free-form label identifying this benchmark run. Recommended values:
        baseline           - before any backfill
        postload           - after 2y backfill
        understream-100    - during 100 EPS streaming
        understream-1000   - during 1000 EPS streaming
        combined           - everything together

.PARAMETER WarmupIterations
    Throw-away runs per query before timed runs. Default 2.

.EXAMPLE
    $token = & .\authenticate\get-kql-token.ps1 -tenantId $tid -clientId $cid -client_secret $cs
    .\Testing\StressTest\Run-Benchmarks.ps1 `
        -QueryUri 'https://trd-xxx.z1.kusto.fabric.microsoft.com' `
        -DatabaseName 'MonitoringEventhouseStress' `
        -KqlAuthToken $token `
        -RunLabel 'baseline'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $QueryUri,
    [Parameter(Mandatory = $true)] [string] $DatabaseName,
    [Parameter(Mandatory = $true)] [string] $KqlAuthToken,

    [string] $QueryFolder       = (Join-Path $PSScriptRoot 'Queries'),
    [int]    $Iterations        = 30,
    [Parameter(Mandatory = $true)] [string] $RunLabel,
    [int]    $WarmupIterations  = 2,
    [string] $OutputFolder      = (Join-Path $PSScriptRoot 'Results')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $QueryFolder)) {
    throw "QueryFolder '$QueryFolder' does not exist."
}

$queryFiles = Get-ChildItem -Path $QueryFolder -Filter '*.kql' -File
if ($queryFiles.Count -eq 0) {
    throw "No .kql files found in '$QueryFolder'."
}

# Sanitize label for use in ClientRequestId / table values
$safeLabel = ($RunLabel -replace '[^a-zA-Z0-9_-]', '_')
$runId     = "$safeLabel-$(Get-Date -Format 'yyyyMMddHHmmss')"

$mgmtUri  = "$QueryUri/v1/rest/mgmt"
$queryUri2 = "$QueryUri/v1/rest/query"
$baseHeaders = @{
    Authorization  = "Bearer $KqlAuthToken"
    'Content-Type' = 'application/json'
}

function Invoke-Kql {
    param(
        [Parameter(Mandatory)] [string] $Csl,
        [ValidateSet('mgmt','query')] [string] $Endpoint = 'query',
        [string] $ClientRequestId,
        [int]    $TimeoutSec = 600,
        [int]    $MaxAttempts = 1
    )
    $uri = if ($Endpoint -eq 'mgmt') { $mgmtUri } else { $queryUri2 }
    $headers = $baseHeaders.Clone()
    if ($ClientRequestId) { $headers['x-ms-client-request-id'] = $ClientRequestId }
    $body = @{ csl = $Csl; db = $DatabaseName } | ConvertTo-Json -Depth 4

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec $TimeoutSec
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            $statusCode = if ($resp) { [int]$resp.StatusCode } else { 0 }
            $detail = ''
            if ($resp) {
                try {
                    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                    $detail = $sr.ReadToEnd()
                } catch { }
            }
            # Retry on transient: 520 internal error, 429 throttling, 503 unavailable
            $isTransient = ($statusCode -in @(429, 503, 520))
            if ($isTransient -and $attempt -lt $MaxAttempts) {
                $backoff = [int]([math]::Pow(2, $attempt) * 5)  # 10s, 20s, 40s...
                Write-Warning "    KQL request failed ($statusCode). Retry $attempt/$($MaxAttempts-1) in ${backoff}s..."
                Start-Sleep -Seconds $backoff
                continue
            }
            Write-Host "KQL request failed. Body sent:" -ForegroundColor Red
            Write-Host $Csl -ForegroundColor DarkGray
            Write-Host "Server response:" -ForegroundColor Red
            Write-Host $detail -ForegroundColor DarkGray
            throw
        }
    }
}

# ---------------------------------------------------------------------------
# Ensure BenchmarkResults table exists
# ---------------------------------------------------------------------------
$createTable = @'
.create-merge table BenchmarkResults (
    RunId:string,
    RunLabel:string,
    QueryName:string,
    Iteration:int,
    ClientRequestId:string,
    StartedOn:datetime,
    DurationMs:long,
    CpuMs:long,
    MemoryPeakMB:real,
    TotalRows:long,
    ScannedRows:long,
    CacheHotHitMB:real,
    CacheColdHitMB:real,
    State:string,
    FailureReason:string,
    CapturedAt:datetime
)
'@
Write-Host "Ensuring BenchmarkResults table..." -ForegroundColor Cyan
Invoke-Kql -Csl $createTable -Endpoint mgmt | Out-Null

# ---------------------------------------------------------------------------
# Placeholder resolver
#
# A query file may declare a resolver header to get fresh per-iteration values:
#   // @resolver: <Table> <WorkspaceIdColumn> <IdColumn> [IdsPerIteration]
# Example: // @resolver: AlertLogs WorkspaceId data_itemId 5
# Placeholders {{workspaceId}} and {{ids}} are then substituted with a random
# workspace that has data and N comma-joined IDs from that workspace. This
# defeats Kusto result caching across iterations.
# ---------------------------------------------------------------------------
function Get-ResolverSpec {
    param([string]$Csl)
    if ($Csl -match '(?m)^\s*//\s*@resolver:\s*(\S+)\s+(\S+)\s+(\S+)(?:\s+(\d+))?') {
        return [pscustomobject]@{
            Table         = $Matches[1]
            WorkspaceCol  = $Matches[2]
            IdCol         = $Matches[3]
            IdsPerRun     = if ($Matches[4]) { [int]$Matches[4] } else { 5 }
        }
    }
    return $null
}

function Resolve-Placeholders {
    param([string]$Csl, [object]$Spec)
    if (-not $Spec) { return $Csl }
    # Pick a random workspace that actually has rows, then take N ids from it.
    $resolverKql = @"
['$($Spec.Table)']
| summarize Ids = make_list(tostring(['$($Spec.IdCol)']), $($Spec.IdsPerRun))
    by WorkspaceId = tostring(['$($Spec.WorkspaceCol)'])
| where array_length(Ids) >= 1
| sample 1
| project WorkspaceId, IdsCsv = strcat_array(Ids, ",")
"@
    try {
        $resp = Invoke-Kql -Csl $resolverKql -Endpoint query -TimeoutSec 60
        $primary = $resp.Tables | Where-Object {
            $_.TableName -eq 'Table_0' -or $_.Name -eq 'PrimaryResult'
        } | Select-Object -First 1
        if (-not $primary) { $primary = @($resp.Tables)[0] }
        $rows = @($primary.Rows)
        if ($rows.Count -eq 0) {
            Write-Warning "    resolver: no data found in $($Spec.Table); leaving placeholders unresolved"
            return $Csl
        }
        $wsId   = [string]$rows[0][0]
        $idsCsv = [string]$rows[0][1]
        return ($Csl -replace '\{\{workspaceId\}\}', $wsId) -replace '\{\{ids\}\}', $idsCsv
    } catch {
        Write-Warning "    resolver failed: $($_.Exception.Message)"
        return $Csl
    }
}

# ---------------------------------------------------------------------------
# Run all queries
# ---------------------------------------------------------------------------
Write-Host "`nRun: $runId  (label: $RunLabel)" -ForegroundColor Yellow
Write-Host "Queries: $($queryFiles.Count)  Iterations: $Iterations  Warmup: $WarmupIterations`n" -ForegroundColor Yellow

$startedAt = Get-Date
$plan      = New-Object System.Collections.Generic.List[object]

foreach ($qf in $queryFiles) {
    $queryName = [IO.Path]::GetFileNameWithoutExtension($qf.Name)
    $safeName  = ($queryName -replace '[^a-zA-Z0-9_-]', '_')
    $cslRaw    = Get-Content -Path $qf.FullName -Raw
    $spec      = Get-ResolverSpec -Csl $cslRaw

    if ($spec) {
        Write-Host "  [$queryName]  (resolver: $($spec.Table) $($spec.WorkspaceCol) $($spec.IdCol) x$($spec.IdsPerRun))" -ForegroundColor Cyan
    } else {
        Write-Host "  [$queryName]" -ForegroundColor Cyan
    }

    # Warmup
    for ($w = 1; $w -le $WarmupIterations; $w++) {
        try {
            $warmCrid = 'bench-warmup:{0}:{1}:{2}' -f $runId, $safeName, $w
            $cslWarm  = if ($spec) { Resolve-Placeholders -Csl $cslRaw -Spec $spec } else { $cslRaw }
            Invoke-Kql -Csl $cslWarm -Endpoint query `
                -ClientRequestId $warmCrid -TimeoutSec 600 | Out-Null
        } catch {
            Write-Warning "    warmup $w failed: $($_.Exception.Message)"
        }
    }

    # Timed iterations - re-resolve every iteration so each run uses different IDs
    for ($i = 1; $i -le $Iterations; $i++) {
        $crid = 'bench:{0}:{1}:{2}' -f $runId, $safeName, $i
        $plan.Add([pscustomobject]@{ QueryName = $queryName; Iteration = $i; Crid = $crid })
        try {
            $cslRun = if ($spec) { Resolve-Placeholders -Csl $cslRaw -Spec $spec } else { $cslRaw }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-Kql -Csl $cslRun -Endpoint query -ClientRequestId $crid -TimeoutSec 600 | Out-Null
            $sw.Stop()
            Write-Host ("    iter {0,3}/{1}  {2,8} ms" -f $i, $Iterations, $sw.ElapsedMilliseconds)
        } catch {
            Write-Warning "    iter $i failed: $($_.Exception.Message)"
        }
    }
}

$endedAt = Get-Date
Write-Host "`nAll iterations submitted. Waiting 60s for engine to flush .show queries..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

# ---------------------------------------------------------------------------
# Collect server-side metrics from .show queries
# ---------------------------------------------------------------------------
$prefix = 'bench:{0}:' -f $runId
$startIso = $startedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$endIso   = $endedAt.AddMinutes(5).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$collect = @"
.show queries
| where ClientActivityId startswith '$prefix'
| where StartedOn between (datetime("$startIso") .. datetime("$endIso"))
| extend Parts     = split(ClientActivityId, ':')
| extend QueryName = tostring(Parts[2]),
         Iteration = toint(Parts[3])
| extend CacheJson    = parse_json(tostring(CacheStatistics))
| extend ScannedJson  = parse_json(tostring(ScannedExtentsStatistics))
| project ClientRequestId = ClientActivityId,
          QueryName,
          Iteration,
          StartedOn,
          DurationMs       = tolong(Duration / 1ms),
          CpuMs            = tolong(TotalCpu / 1ms),
          MemoryPeakMB     = todouble(MemoryPeak) / 1024.0 / 1024.0,
          TotalRows        = tolong(ScannedJson.TotalRowsCount),
          ScannedRows      = tolong(ScannedJson.ScannedRowsCount),
          CacheHotHitMB    = todouble(CacheJson.Shards.Hot.HitBytes)  / 1024.0 / 1024.0,
          CacheColdHitMB   = todouble(CacheJson.Shards.Cold.HitBytes) / 1024.0 / 1024.0,
          State,
          FailureReason
"@

Write-Host "Collecting metrics from .show queries..." -ForegroundColor Cyan
$resp = Invoke-Kql -Csl $collect -Endpoint mgmt -TimeoutSec 600 -MaxAttempts 4
$primary = $resp.Tables | Where-Object {
    $_.TableName -eq 'Table_0' -or $_.Name -eq 'PrimaryResult'
} | Select-Object -First 1

if (-not $primary -or $primary.Rows.Count -eq 0) {
    Write-Warning "No metrics returned. Increase the wait time or check ClientRequestId prefix."
    return
}

$colNames = $primary.Columns | ForEach-Object { $_.ColumnName }
function Get-Cell { param($row, [string]$name) $idx = $colNames.IndexOf($name); if ($idx -lt 0) { $null } else { $row[$idx] } }

# ---------------------------------------------------------------------------
# Persist to BenchmarkResults via .ingest inline
# ---------------------------------------------------------------------------
function Esc { param($s) if ($null -eq $s) { '' } else { ($s -replace '"','""') } }

$capturedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$rowsCsv = New-Object System.Collections.Generic.List[string]
$detailObjects = New-Object System.Collections.Generic.List[object]
foreach ($row in $primary.Rows) {
    $rec = [pscustomobject]@{
        RunId            = $runId
        RunLabel         = $RunLabel
        QueryName        = (Get-Cell $row 'QueryName')
        Iteration        = (Get-Cell $row 'Iteration')
        ClientRequestId  = (Get-Cell $row 'ClientRequestId')
        StartedOn        = (Get-Cell $row 'StartedOn')
        DurationMs       = (Get-Cell $row 'DurationMs')
        CpuMs            = (Get-Cell $row 'CpuMs')
        MemoryPeakMB     = (Get-Cell $row 'MemoryPeakMB')
        TotalRows        = (Get-Cell $row 'TotalRows')
        ScannedRows      = (Get-Cell $row 'ScannedRows')
        CacheHotHitMB    = (Get-Cell $row 'CacheHotHitMB')
        CacheColdHitMB   = (Get-Cell $row 'CacheColdHitMB')
        State            = (Get-Cell $row 'State')
        FailureReason    = (Get-Cell $row 'FailureReason')
        CapturedAt       = $capturedAt
    }
    $detailObjects.Add($rec)
    $vals = @(
        $rec.RunId, $rec.RunLabel, $rec.QueryName, $rec.Iteration, $rec.ClientRequestId,
        $rec.StartedOn, $rec.DurationMs, $rec.CpuMs, $rec.MemoryPeakMB,
        $rec.TotalRows, $rec.ScannedRows,
        $rec.CacheHotHitMB, $rec.CacheColdHitMB, $rec.State, $rec.FailureReason, $rec.CapturedAt
    )
    $quoted = $vals | ForEach-Object { '"' + (Esc $_) + '"' }
    $rowsCsv.Add( ($quoted -join ',') )
}

$ingestCmd = ".ingest inline into table BenchmarkResults with (format='csv') <|`n" + ($rowsCsv -join "`n")
Invoke-Kql -Csl $ingestCmd -Endpoint mgmt -TimeoutSec 600 | Out-Null
Write-Host "Persisted $($rowsCsv.Count) rows to BenchmarkResults." -ForegroundColor Green

# ---------------------------------------------------------------------------
# Export detail CSV
# ---------------------------------------------------------------------------
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}
$detailCsvPath = Join-Path $OutputFolder ("benchmark_detail_{0}.csv" -f $runId)
$detailObjects | Export-Csv -Path $detailCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Detail CSV: $detailCsvPath" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Console summary
# ---------------------------------------------------------------------------
$summary = @"
BenchmarkResults
| where RunId == '$runId'
| summarize Runs=count(),
            P50=percentile(DurationMs,50),
            P95=percentile(DurationMs,95),
            Max=max(DurationMs),
            AvgCpuMs=avg(CpuMs),
            AvgMemMB=avg(MemoryPeakMB),
            AvgTotalRows=avg(TotalRows),
            AvgScannedRows=avg(ScannedRows)
  by QueryName
| order by P95 desc
"@
$resp2 = Invoke-Kql -Csl $summary -Endpoint query
$primary2 = $resp2.Tables | Where-Object { $_.TableName -eq 'Table_0' -or $_.Name -eq 'PrimaryResult' } | Select-Object -First 1
if ($primary2) {
    Write-Host "`nSummary for run '$runId':" -ForegroundColor Yellow
    $cols = $primary2.Columns | ForEach-Object { $_.ColumnName }

    # Build typed objects so Format-Table can autosize and right-align numbers
    $summaryObjects = New-Object System.Collections.Generic.List[object]
    foreach ($r in $primary2.Rows) {
        $obj = [ordered]@{ RunId = $runId; RunLabel = $RunLabel }
        for ($k = 0; $k -lt $cols.Count; $k++) { $obj[$cols[$k]] = $r[$k] }
        $summaryObjects.Add([pscustomobject]$obj)
    }

    # Display with autosized columns; drop RunId/RunLabel from console (already shown above)
    $summaryObjects |
        Select-Object -Property ($cols) |
        Format-Table -AutoSize -Wrap |
        Out-String |
        Write-Host

    $summaryCsvPath = Join-Path $OutputFolder ("benchmark_summary_{0}.csv" -f $runId)
    $summaryObjects | Export-Csv -Path $summaryCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Summary CSV: $summaryCsvPath" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Comparison helper (only if multiple labels exist)
# ---------------------------------------------------------------------------
$compare = @"
BenchmarkResults
| summarize P50=percentile(DurationMs,50), P95=percentile(DurationMs,95), Runs=count() by RunLabel, QueryName
| order by QueryName asc, RunLabel asc
"@
$respC = Invoke-Kql -Csl $compare -Endpoint query
$primaryC = $respC.Tables | Where-Object { $_.TableName -eq 'Table_0' -or $_.Name -eq 'PrimaryResult' } | Select-Object -First 1
if ($primaryC -and $primaryC.Rows.Count -gt $primary2.Rows.Count) {
    Write-Host "`nCross-run comparison:" -ForegroundColor Yellow
    $cols = $primaryC.Columns | ForEach-Object { $_.ColumnName }
    $compareObjects = foreach ($r in $primaryC.Rows) {
        $obj = [ordered]@{}
        for ($k = 0; $k -lt $cols.Count; $k++) { $obj[$cols[$k]] = $r[$k] }
        [pscustomobject]$obj
    }
    $compareObjects | Format-Table -AutoSize -Wrap | Out-String | Write-Host
}

Write-Host "`nDone." -ForegroundColor Green
