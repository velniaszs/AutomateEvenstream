<#
.SYNOPSIS
    Generates 2 years of synthetic historical data into the Monitoring Eventhouse
    for stress / volume testing of the AutomateEventstream pipeline.

.DESCRIPTION
    All data is generated server-side via KQL (.set-or-append <| range ...) so no
    rows leave the engine. ingestion_time() is backdated per batch using
    .set-or-append ... with(creationTime='...') so the pipeline's
    "where ingestion_time() > startTimeFilter" clauses behave realistically.

    Tables populated (must already have schema from
    PrepareEnvironment\prepare_eventhouse_tables.kql):
        _TestWorkspacePool                   (helper - 20k workspaces + names)
        workspace_owner                      (1 row per workspace)
        DataverseWorkspace                   (state history, daily batches)
        WorkspaceOutboundAccessProtection    (OAP audit events, daily batches)
        WorkspaceLogs                        (item create/delete events, daily batches)

    Cross-table referential integrity: all WorkspaceId values in every table are
    drawn from _TestWorkspacePool, so the pipeline's inner joins return realistic
    row counts.

    Distributions:
        WorkspaceLogs.type:                       80% ItemCreateSucceeded / 20% ItemDeleteSucceeded
        WorkspaceOutboundAccessProtection.Activity: 70% Enable / 30% Disable
        DataverseWorkspace.OAPActivity:           70% Enable / 30% Disable

.PARAMETER QueryUri
    Eventhouse query URI, e.g. https://trd-xxxx.z1.kusto.fabric.microsoft.com

.PARAMETER DatabaseName
    Eventhouse database name, e.g. MonitoringEventhouse

.PARAMETER KqlAuthToken
    Bearer token (use authenticate\get-kql-token.ps1 to obtain).

.PARAMETER WorkspaceCount
    Distinct workspace cardinality. Default 20000.

.PARAMETER StartDate / EndDate
    Date range for backfilled events. Defaults: 2 years ending today.

.PARAMETER LogsPerDay / OAPPerDay / DataversePerDay
    Row volume per day per table. Defaults sized for 2M / 1M / 1M total over 2y.

.PARAMETER BatchSizeDays
    How many days per ingest command. 1 = daily granularity (most realistic
    ingestion_time, but ~730 commands/table). 7 = weekly batches (~104 cmds).
    Default 7.

.PARAMETER SkipPool
    Skip recreating the workspace pool (use when re-running and pool already exists).

.PARAMETER Phases
    Which phases to run. Default: All. Values: Pool, Owners, Dataverse, OAP, Logs, AlertLogs, AOPAlertLogs.

.EXAMPLE
    $token = & .\authenticate\get-kql-token.ps1 -tenantId $tid -clientId $cid -client_secret $cs
    .\Testing\StressTest\Run-StressTestBackfill.ps1 `
        -QueryUri 'https://trd-xxx.z1.kusto.fabric.microsoft.com' `
        -DatabaseName 'MonitoringEventhouseStress' `
        -KqlAuthToken $token

.NOTES
    Use a DEDICATED test eventhouse. Do not run against production.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]   $QueryUri,
    [Parameter(Mandatory = $true)] [string]   $DatabaseName,
    [Parameter(Mandatory = $true)] [string]   $KqlAuthToken,

    [int]      $WorkspaceCount   = 20000,
    [datetime] $StartDate        = (Get-Date).Date.AddYears(-2),
    [datetime] $EndDate          = (Get-Date).Date,
    [int]      $LogsPerDay       = 2740,   # ~ 2,000,000 / 730
    [int]      $OAPPerDay        = 1370,   # ~ 1,000,000 / 730
    [int]      $DataversePerDay  = 1370,   # ~ 1,000,000 / 730
    [int]      $AlertLogsPerDay  = 1370,   # ~ 1,000,000 / 730
    [int]      $AOPAlertsPerDay  = 137,    # ~   100,000 / 730
    [int]      $BatchSizeDays    = 7,

    [ValidateSet('All','Pool','Owners','Dataverse','OAP','Logs','AlertLogs','AOPAlertLogs')]
    [string[]] $Phases           = @('All'),

    [switch]   $SkipPool
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# REST helper
# ---------------------------------------------------------------------------
$mgmtUri  = "$QueryUri/v1/rest/mgmt"
$queryUri2 = "$QueryUri/v1/rest/query"
$headers  = @{
    Authorization  = "Bearer $KqlAuthToken"
    'Content-Type' = 'application/json'
}

function Invoke-Kql {
    param(
        [Parameter(Mandatory)] [string] $Csl,
        [ValidateSet('mgmt','query')] [string] $Endpoint = 'mgmt',
        [int] $TimeoutSec = 600
    )
    $uri  = if ($Endpoint -eq 'mgmt') { $mgmtUri } else { $queryUri2 }
    $body = @{ csl = $Csl; db = $DatabaseName } | ConvertTo-Json -Depth 4
    try {
        return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec $TimeoutSec
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        $detail = ''
        if ($resp) {
            try {
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $detail = $sr.ReadToEnd()
            } catch { }
        }
        Write-Host "KQL request failed. Body sent:" -ForegroundColor Red
        Write-Host $Csl -ForegroundColor DarkGray
        Write-Host "Server response:" -ForegroundColor Red
        Write-Host $detail -ForegroundColor DarkGray
        throw
    }
}

function Test-Phase {
    param([string]$Name)
    return ($Phases -contains 'All' -or $Phases -contains $Name)
}

# ---------------------------------------------------------------------------
# Phase 1: workspace pool
# ---------------------------------------------------------------------------
if ((Test-Phase 'Pool') -and -not $SkipPool) {
    Write-Host "[Pool] Creating _TestWorkspacePool with $WorkspaceCount workspaces..." -ForegroundColor Cyan

    $createPool = @"
.create-merge table _TestWorkspacePool (WorkspaceId:guid, WorkspaceName:string, OrganizationId:string, RowNum:long)
"@
    Invoke-Kql -Csl $createPool | Out-Null

    # Truncate so re-runs with -SkipPool:$false start fresh
    Invoke-Kql -Csl ".clear table _TestWorkspacePool data" | Out-Null

    $populatePool = @"
.set-or-append _TestWorkspacePool <|
range RowNum from 1 to $WorkspaceCount step 1
| extend WorkspaceId    = new_guid()
| extend WorkspaceName  = strcat('stress_ws_', tostring(RowNum))
| extend OrganizationId = '00000000-0000-0000-0000-000000000000'
| project WorkspaceId, WorkspaceName, OrganizationId, RowNum
"@
    Invoke-Kql -Csl $populatePool -TimeoutSec 1200 | Out-Null
    Write-Host "[Pool] Done." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Phase 2: workspace_owner (one row per workspace)
# ---------------------------------------------------------------------------
if (Test-Phase 'Owners') {
    Write-Host "[Owners] Populating workspace_owner..." -ForegroundColor Cyan
    $ownerCmd = @"
.set-or-append workspace_owner <|
_TestWorkspacePool
| project workspaceId   = WorkspaceId,
          PrimaryEmail   = strcat('primary_',   tostring(RowNum), '@stresstest.local'),
          SecondaryEmail = strcat('secondary_', tostring(RowNum), '@stresstest.local'),
          modifiedon     = now()
"@
    Invoke-Kql -Csl $ownerCmd -TimeoutSec 600 | Out-Null
    Write-Host "[Owners] Done." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Daily-batched generators
# ---------------------------------------------------------------------------
function Get-DateBatches {
    param([datetime]$Start, [datetime]$End, [int]$Size)
    $batches = New-Object System.Collections.Generic.List[object]
    $cur = $Start
    while ($cur -lt $End) {
        $next = $cur.AddDays($Size)
        if ($next -gt $End) { $next = $End }
        $batches.Add([pscustomobject]@{
            BatchStart = $cur
            BatchEnd   = $next                         # exclusive
            Days       = [int]([math]::Ceiling(($next - $cur).TotalDays))
            CreationTime = $next.AddSeconds(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        })
        $cur = $next
    }
    return ,$batches
}

$batches = Get-DateBatches -Start $StartDate -End $EndDate -Size $BatchSizeDays
Write-Host "Date range: $StartDate -> $EndDate  ($($batches.Count) batches of up to $BatchSizeDays days)" -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# Phase 3: DataverseWorkspace
# ---------------------------------------------------------------------------
if (Test-Phase 'Dataverse') {
    Write-Host "[Dataverse] Backfilling DataverseWorkspace ($DataversePerDay rows/day)..." -ForegroundColor Cyan
    $i = 0
    foreach ($b in $batches) {
        $i++
        $rows = $DataversePerDay * $b.Days
        $batchStartIso = $b.BatchStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $batchEndIso   = $b.BatchEnd.ToString('yyyy-MM-ddTHH:mm:ssZ')

        $cmd = @"
.set-or-append DataverseWorkspace with(creationTime='$($b.CreationTime)') <|
let pool = materialize(_TestWorkspacePool | project WorkspaceId, RowNum);
let poolCount = toscalar(pool | count);
let bStart = datetime($batchStartIso);
let bEnd   = datetime($batchEndIso);
let bSpanSec = (bEnd - bStart) / 1s;
range i from 1 to $rows step 1
| extend pick = toint(rand() * poolCount) + 1
| join kind=inner pool on `$left.pick == `$right.RowNum
| extend OAPActivity = iff(hash(tostring(WorkspaceId), 100) < 70, 'EnableWorkspaceOutboundAccessProtection', 'DisableWorkspaceOutboundAccessProtection')
| extend IsMonitored = true
| extend modifiedon  = bStart + totimespan(strcat(tostring(toint(rand() * bSpanSec)), 's'))
| extend createdon   = modifiedon - totimespan(strcat(tostring(toint(rand() * 2592000)), 's'))
| project WorkspaceId, OAPActivity, IsMonitored, createdon, modifiedon
"@
        Invoke-Kql -Csl $cmd -TimeoutSec 1200 | Out-Null
        Write-Progress -Activity "DataverseWorkspace" -Status "$i / $($batches.Count)" -PercentComplete (($i / $batches.Count) * 100)
    }
    Write-Progress -Activity "DataverseWorkspace" -Completed
    Write-Host "[Dataverse] Done." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Phase 4: WorkspaceOutboundAccessProtection
# ---------------------------------------------------------------------------
if (Test-Phase 'OAP') {
    Write-Host "[OAP] Backfilling WorkspaceOutboundAccessProtection ($OAPPerDay rows/day)..." -ForegroundColor Cyan
    $i = 0
    foreach ($b in $batches) {
        $i++
        $rows = $OAPPerDay * $b.Days
        $batchStartIso = $b.BatchStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $batchEndIso   = $b.BatchEnd.ToString('yyyy-MM-ddTHH:mm:ssZ')

        $cmd = @"
.set-or-append WorkspaceOutboundAccessProtection with(creationTime='$($b.CreationTime)') <|
let pool = materialize(_TestWorkspacePool | project WorkspaceId, WorkspaceName, OrganizationId, RowNum);
let poolCount = toscalar(pool | count);
let bStart = datetime($batchStartIso);
let bEnd   = datetime($batchEndIso);
let bSpanSec = (bEnd - bStart) / 1s;
range i from 1 to $rows step 1
| extend pick = toint(rand() * poolCount) + 1
| join kind=inner pool on `$left.pick == `$right.RowNum
| extend Activity      = iff(hash(tostring(WorkspaceId), 100) < 70, 'EnableWorkspaceOutboundAccessProtection', 'DisableWorkspaceOutboundAccessProtection')
| extend Operation     = Activity
| extend CreationTime  = bStart + totimespan(strcat(tostring(toint(rand() * bSpanSec)), 's'))
| extend Id            = new_guid()
| extend RequestId     = tostring(new_guid())
| extend UserId        = strcat('user_', tostring(toint(rand()*200)), '@stresstest.local')
| extend UserKey       = UserId
| extend ClientIP      = strcat(toint(rand()*255), '.', toint(rand()*255), '.', toint(rand()*255), '.', toint(rand()*255))
| project Activity,
          BillingType            = long(0),
          ClientIP,
          CreationTime,
          Experience             = 'Fabric',
          Id,
          ObjectDisplayName      = WorkspaceName,
          ObjectId               = tostring(WorkspaceId),
          ObjectType             = 'Workspace',
          Operation,
          OrganizationId,
          RecordType             = long(70),
          RefreshEnforcementPolicy = long(0),
          RequestId,
          ResultStatus           = 'Succeeded',
          UserAgent              = 'StressTest/1.0',
          UserId,
          UserKey,
          UserType               = long(0),
          WorkSpaceName          = WorkspaceName,
          Workload               = 'PowerBI',
          WorkspaceId
"@
        Invoke-Kql -Csl $cmd -TimeoutSec 1800 | Out-Null
        Write-Progress -Activity "WorkspaceOutboundAccessProtection" -Status "$i / $($batches.Count)" -PercentComplete (($i / $batches.Count) * 100)
    }
    Write-Progress -Activity "WorkspaceOutboundAccessProtection" -Completed
    Write-Host "[OAP] Done." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Phase 5: WorkspaceLogs
# ---------------------------------------------------------------------------
if (Test-Phase 'Logs') {
    Write-Host "[Logs] Backfilling WorkspaceLogs ($LogsPerDay rows/day)..." -ForegroundColor Cyan
    $i = 0
    foreach ($b in $batches) {
        $i++
        $rows = $LogsPerDay * $b.Days
        $batchStartIso = $b.BatchStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $batchEndIso   = $b.BatchEnd.ToString('yyyy-MM-ddTHH:mm:ssZ')

        $cmd = @"
.set-or-append WorkspaceLogs with(creationTime='$($b.CreationTime)') <|
let pool = materialize(_TestWorkspacePool | project WorkspaceId, WorkspaceName, RowNum);
let poolCount = toscalar(pool | count);
let bStart = datetime($batchStartIso);
let bEnd   = datetime($batchEndIso);
let bSpanSec = (bEnd - bStart) / 1s;
let kinds = dynamic(['Lakehouse','Notebook','SparkJobDefinition','Environment','Warehouse','DataFlow','DataPipeline','CopyJob','MirroredDatabase','SQLEndpoint','Report','SemanticModel','Dashboard','VariableLibrary','Eventstream']);
range i from 1 to $rows step 1
| extend pick     = toint(rand() * poolCount) + 1
| extend kindIdx  = toint(rand() * 15)
| extend typePick = rand()
| join kind=inner pool on `$left.pick == `$right.RowNum
| extend type = iff(typePick < 0.8, 'Microsoft.Fabric.ItemCreateSucceeded', 'Microsoft.Fabric.ItemDeleteSucceeded')
| extend data_itemKind = tostring(kinds[kindIdx])
| extend data_itemId   = new_guid()
| extend data_itemName = strcat('item_', tostring(data_itemId))
| extend ['time']      = bStart + totimespan(strcat(tostring(toint(rand() * bSpanSec)), 's'))
| extend id            = new_guid()
| extend data_executingPrincipalId = new_guid()
| project type,
          datacontenttype           = 'application/json',
          id,
          ['time'],
          dataschemaversion         = real(1.0),
          subject                   = strcat('/workspaces/', tostring(WorkspaceId), '/items/', tostring(data_itemId)),
          source                    = WorkspaceId,
          specversion               = real(1.0),
          data_workspaceId          = WorkspaceId,
          data_workspaceName        = WorkspaceName,
          data_itemName,
          data_itemId,
          data_itemKind,
          data_executingPrincipalId,
          data_executingPrincipalType = 'User'
"@
        Invoke-Kql -Csl $cmd -TimeoutSec 1800 | Out-Null
        Write-Progress -Activity "WorkspaceLogs" -Status "$i / $($batches.Count)" -PercentComplete (($i / $batches.Count) * 100)
    }
    Write-Progress -Activity "WorkspaceLogs" -Completed
    Write-Host "[Logs] Done." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Phase 6: AlertLogs
# ---------------------------------------------------------------------------
if (Test-Phase 'AlertLogs') {
    Write-Host "[AlertLogs] Backfilling AlertLogs ($AlertLogsPerDay rows/day)..." -ForegroundColor Cyan
    $i = 0
    foreach ($b in $batches) {
        $i++
        $rows = $AlertLogsPerDay * $b.Days
        $batchStartIso = $b.BatchStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $batchEndIso   = $b.BatchEnd.ToString('yyyy-MM-ddTHH:mm:ssZ')

        $cmd = @"
.set-or-append AlertLogs with(creationTime='$($b.CreationTime)') <|
let pool = materialize(_TestWorkspacePool | project WorkspaceId, WorkspaceName, RowNum);
let poolCount = toscalar(pool | count);
let bStart = datetime($batchStartIso);
let bEnd   = datetime($batchEndIso);
let bSpanSec = (bEnd - bStart) / 1s;
let kinds = dynamic(['Lakehouse','Notebook','SparkJobDefinition','Environment','Warehouse','DataFlow','DataPipeline','CopyJob','MirroredDatabase','SQLEndpoint']);
let statuses = dynamic(['Initial','EmailSent','NoEmail']);
range i from 1 to $rows step 1
| extend pick     = toint(rand() * poolCount) + 1
| extend kindIdx  = toint(rand() * 10)
| extend statIdx  = toint(rand() * 3)
| join kind=inner pool on `$left.pick == `$right.RowNum
| extend wstime         = bStart + totimespan(strcat(tostring(toint(rand() * bSpanSec)), 's'))
| extend data_itemKind  = tostring(kinds[kindIdx])
| extend data_itemId    = new_guid()
| extend data_itemName  = strcat('item_', tostring(data_itemId))
| extend AlertStatus    = tostring(statuses[statIdx])
| extend UserId         = new_guid()
| project WorkspaceName, WorkspaceId, wstime, data_itemKind, data_itemName, data_itemId, AlertStatus, UserId
"@
        Invoke-Kql -Csl $cmd -TimeoutSec 1800 | Out-Null
        Write-Progress -Activity "AlertLogs" -Status "$i / $($batches.Count)" -PercentComplete (($i / $batches.Count) * 100)
    }
    Write-Progress -Activity "AlertLogs" -Completed
    Write-Host "[AlertLogs] Done." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Phase 7: AOPAlertLogs
# ---------------------------------------------------------------------------
if (Test-Phase 'AOPAlertLogs') {
    Write-Host "[AOPAlertLogs] Backfilling AOPAlertLogs ($AOPAlertsPerDay rows/day)..." -ForegroundColor Cyan
    $i = 0
    foreach ($b in $batches) {
        $i++
        $rows = $AOPAlertsPerDay * $b.Days
        $batchStartIso = $b.BatchStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $batchEndIso   = $b.BatchEnd.ToString('yyyy-MM-ddTHH:mm:ssZ')

        $cmd = @"
.set-or-append AOPAlertLogs with(creationTime='$($b.CreationTime)') <|
let pool = materialize(_TestWorkspacePool | project WorkspaceId, RowNum);
let poolCount = toscalar(pool | count);
let bStart = datetime($batchStartIso);
let bEnd   = datetime($batchEndIso);
let bSpanSec = (bEnd - bStart) / 1s;
let statuses = dynamic(['Initial','EmailSent','NoEmail']);
range i from 1 to $rows step 1
| extend pick     = toint(rand() * poolCount) + 1
| extend statIdx  = toint(rand() * 3)
| extend enableAop = (rand() < 0.7)
| join kind=inner pool on `$left.pick == `$right.RowNum
| extend AOP            = iff(enableAop, 'EnableWorkspaceOutboundAccessProtection', 'DisableWorkspaceOutboundAccessProtection')
| extend AOPMustBe      = iff(enableAop, 'DisableWorkspaceOutboundAccessProtection', 'EnableWorkspaceOutboundAccessProtection')
| extend ToChangeAOP    = true
| extend CreationTime   = bStart + totimespan(strcat(tostring(toint(rand() * bSpanSec)), 's'))
| extend UserId         = strcat('user_', tostring(toint(rand()*200)), '@stresstest.local')
| extend AlertStatus    = tostring(statuses[statIdx])
| extend Id             = new_guid()
| extend UserKey        = UserId
| project WorkspaceId, ToChangeAOP, AOP, AOPMustBe, CreationTime, UserId, AlertStatus, Id, UserKey
"@
        Invoke-Kql -Csl $cmd -TimeoutSec 1800 | Out-Null
        Write-Progress -Activity "AOPAlertLogs" -Status "$i / $($batches.Count)" -PercentComplete (($i / $batches.Count) * 100)
    }
    Write-Progress -Activity "AOPAlertLogs" -Completed
    Write-Host "[AOPAlertLogs] Done." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`nVerifying row counts..." -ForegroundColor Yellow
$counts = @"
union
( _TestWorkspacePool                | summarize C=count() | extend T='_TestWorkspacePool' ),
( workspace_owner                   | summarize C=count() | extend T='workspace_owner' ),
( DataverseWorkspace                | summarize C=count() | extend T='DataverseWorkspace' ),
( WorkspaceOutboundAccessProtection | summarize C=count() | extend T='WorkspaceOutboundAccessProtection' ),
( WorkspaceLogs                     | summarize C=count() | extend T='WorkspaceLogs' ),
( AlertLogs                         | summarize C=count() | extend T='AlertLogs' ),
( AOPAlertLogs                      | summarize C=count() | extend T='AOPAlertLogs' )
| project T, C
"@
$resp = Invoke-Kql -Csl $counts -Endpoint query
$primary = $resp.Tables | Where-Object { $_.TableName -eq 'Table_0' -or $_.Name -eq 'PrimaryResult' } | Select-Object -First 1
if ($primary) {
    foreach ($row in $primary.Rows) { Write-Host ("  {0,-40} {1,12:N0}" -f $row[0], [int64]$row[1]) }
}
Write-Host "`nBackfill complete." -ForegroundColor Green
