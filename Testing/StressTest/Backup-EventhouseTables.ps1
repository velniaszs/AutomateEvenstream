<#
.SYNOPSIS
    Backs up or restores Eventhouse tables before/after stress testing.

.DESCRIPTION
    Creates point-in-time copies of the monitoring tables into sibling tables
    suffixed with _bak_<timestamp> (or a fixed suffix you provide).
    Restore deletes current rows and re-populates from the backup snapshot.

    Modes:
        Backup   - copy each table to <Table>_bak_<Suffix>
        Restore  - replace current data with backup snapshot
        List     - show all backup tables present
        Drop     - drop a specific backup snapshot

    Tables backed up by default:
        WorkspaceLogs
        WorkspaceOutboundAccessProtection
        WorkspaceOutboundAccessProtection_Staging
        DataverseWorkspace
        DataverseWorkspace_Staging
        workspace_owner
        workspace_owner_staging
        AlertLogs
        AOPAlertLogs
        AllowedItemKind
        OAPEnabledAllowedItemKind
        MonitoringLastRunTime
        DeleteLastRunTime
        DeleteException

    Restore strategy uses .set-or-replace which atomically swaps the data extents,
    so it is fast even on large tables and avoids partial states.

.PARAMETER QueryUri
    Eventhouse query URI.

.PARAMETER DatabaseName
    Eventhouse database name.

.PARAMETER KqlAuthToken
    Bearer token (use authenticate\get-kql-token.ps1).

.PARAMETER Mode
    Backup | Restore | List | Drop

.PARAMETER Suffix
    Backup snapshot suffix. Default: yyyyMMddHHmmss timestamp.
    For Restore/Drop you MUST pass the suffix of the snapshot to use.

.PARAMETER Tables
    Optional override of which tables to back up / restore.

.EXAMPLE
    # Take a snapshot before stress test
    .\Testing\StressTest\Backup-EventhouseTables.ps1 @common -Mode Backup
    # ... run stress tests ...
    # Restore using the snapshot suffix printed above
    .\Testing\StressTest\Backup-EventhouseTables.ps1 @common -Mode Restore -Suffix '20260428_140512'

.NOTES
    Backups live in the same database. Disk cost = full copy of source data.
    For very large tables, consider using `.export` to ADLS instead.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $QueryUri,
    [Parameter(Mandatory = $true)] [string] $DatabaseName,
    [Parameter(Mandatory = $true)] [string] $KqlAuthToken,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Backup','Restore','List','Drop')]
    [string] $Mode,

    [string] $Suffix,

    [string[]] $Tables = @(
        'WorkspaceLogs',
        'WorkspaceOutboundAccessProtection',
        'DataverseWorkspace',
        'workspace_owner',
        'AlertLogs',
        'AOPAlertLogs',
        'MonitoringLastRunTime',
        'DeleteLastRunTime'
    )
)

$ErrorActionPreference = 'Stop'

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
        [int] $TimeoutSec = 1800
    )
    $uri = if ($Endpoint -eq 'mgmt') { $mgmtUri } else { $queryUri2 }
    $body = @{ csl = $Csl; db = $DatabaseName } | ConvertTo-Json -Depth 4
    return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec $TimeoutSec
}

function Get-PrimaryRows {
    param($Response)
    if (-not $Response) { return @() }
    # Force into an array - PowerShell sometimes unwraps single-element arrays.
    $tables = @($Response.Tables)
    if ($tables.Count -eq 0) { return @() }
    $primary = $tables | Where-Object {
        $_.TableName -eq 'Table_0' -or $_.Name -eq 'PrimaryResult'
    } | Select-Object -First 1
    if (-not $primary) { $primary = $tables[0] }
    if (-not $primary) { return @() }
    $rowsRaw = @($primary.Rows)
    if ($rowsRaw.Count -eq 0) { return @() }
    $cols = @($primary.Columns | ForEach-Object { $_.ColumnName })
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rowsRaw) {
        $obj = [ordered]@{}
        for ($i = 0; $i -lt $cols.Count; $i++) { $obj[$cols[$i]] = $row[$i] }
        $out.Add([pscustomobject]$obj)
    }
    return ,$out.ToArray()
}

function Test-TableExists {
    param([string]$Name)
    $resp = Invoke-Kql -Csl ".show tables | where TableName == '$Name' | project TableName" -Endpoint mgmt
    $rows = @(Get-PrimaryRows $resp)
    Write-Verbose "Test-TableExists '$Name' -> $($rows.Count) rows"
    return ($rows.Count -gt 0)
}

function Get-RowCount {
    param([string]$Name)
    try {
        $resp = Invoke-Kql -Csl "['$Name'] | count" -Endpoint query
        $rows = Get-PrimaryRows $resp
        if ($rows.Count -gt 0) { return [int64]$rows[0].Count } else { return 0 }
    } catch {
        return -1
    }
}

# ---------------------------------------------------------------------------
# List mode
# ---------------------------------------------------------------------------
if ($Mode -eq 'List') {
    Write-Host "Backup snapshots in '$DatabaseName':" -ForegroundColor Cyan
    $resp = Invoke-Kql -Csl ".show tables | where TableName contains '_bak_' | project TableName | order by TableName asc" -Endpoint mgmt
    $rows = Get-PrimaryRows $resp
    if ($rows.Count -eq 0) {
        Write-Host "  (no backup tables found)" -ForegroundColor Yellow
        return
    }
    # Group by suffix
    $bySuffix = @{}
    foreach ($r in $rows) {
        if ($r.TableName -match '_bak_(.+)$') {
            $suf = $Matches[1]
            if (-not $bySuffix.ContainsKey($suf)) { $bySuffix[$suf] = @() }
            $bySuffix[$suf] += $r.TableName
        }
    }
    foreach ($suf in ($bySuffix.Keys | Sort-Object -Descending)) {
        Write-Host "`n  Suffix: $suf  ($($bySuffix[$suf].Count) tables)" -ForegroundColor Green
        foreach ($t in $bySuffix[$suf]) { Write-Host "    $t" }
    }
    return
}

# ---------------------------------------------------------------------------
# Drop mode
# ---------------------------------------------------------------------------
if ($Mode -eq 'Drop') {
    if (-not $Suffix) { throw "Drop mode requires -Suffix." }
    Write-Host "Dropping backup snapshot '$Suffix'..." -ForegroundColor Yellow
    foreach ($t in $Tables) {
        $bak = "${t}_bak_${Suffix}"
        if (Test-TableExists $bak) {
            Invoke-Kql -Csl ".drop table ['$bak'] ifexists" -Endpoint mgmt | Out-Null
            Write-Host "  dropped $bak"
        }
    }
    Write-Host "Done." -ForegroundColor Green
    return
}

# ---------------------------------------------------------------------------
# Resolve suffix
# ---------------------------------------------------------------------------
if ($Mode -eq 'Backup') {
    if (-not $Suffix) { $Suffix = Get-Date -Format 'yyyyMMdd_HHmmss' }
    Write-Host "Backup suffix: $Suffix" -ForegroundColor Yellow
}
if ($Mode -eq 'Restore') {
    if (-not $Suffix) { throw "Restore mode requires -Suffix (use -Mode List to find available snapshots)." }
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------
if ($Mode -eq 'Backup') {
    $manifest = New-Object System.Collections.Generic.List[object]
    foreach ($t in $Tables) {
        if (-not (Test-TableExists $t)) {
            Write-Warning "  skipping '$t' (does not exist)"
            continue
        }
        $bak = "${t}_bak_${Suffix}"
        $srcCount = Get-RowCount $t
        Write-Host ("  backup {0,-45} -> {1}  ({2} rows)" -f $t, $bak, $srcCount) -ForegroundColor Cyan
        # .set creates the new table from the source schema and data in one step
        # async ensures large tables don't block the REST call
        $cmd = ".set ['$bak'] <| ['$t']"
        Invoke-Kql -Csl $cmd -Endpoint mgmt -TimeoutSec 3600 | Out-Null
        $bakCount = Get-RowCount $bak
        $ok       = ($bakCount -eq $srcCount)
        $manifest.Add([pscustomobject]@{
            Table     = $t
            Backup    = $bak
            SrcRows   = $srcCount
            BakRows   = $bakCount
            Ok        = $ok
        })
        if (-not $ok) { Write-Warning "    row count mismatch ($srcCount vs $bakCount)" }
    }
    Write-Host "`nBackup manifest:" -ForegroundColor Yellow
    $manifest | Format-Table -AutoSize
    Write-Host "`nTo restore: -Mode Restore -Suffix '$Suffix'" -ForegroundColor Green
    return
}

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------
if ($Mode -eq 'Restore') {
    Write-Host "Restoring from snapshot '$Suffix'..." -ForegroundColor Yellow
    Write-Host "WARNING: this will REPLACE current data in the listed tables." -ForegroundColor Red
    $confirm = Read-Host "Type 'YES' to continue"
    if ($confirm -ne 'YES') { Write-Host "Aborted." -ForegroundColor Yellow; return }

    $manifest = New-Object System.Collections.Generic.List[object]
    foreach ($t in $Tables) {
        $bak = "${t}_bak_${Suffix}"
        if (-not (Test-TableExists $bak)) {
            Write-Warning "  skipping '$t' (no backup '$bak')"
            continue
        }
        $bakCount = Get-RowCount $bak
        Write-Host ("  restore {0,-45} <- {1}  ({2} rows)" -f $t, $bak, $bakCount) -ForegroundColor Cyan
        # .set-or-replace atomically swaps extents - no partial state
        $cmd = ".set-or-replace ['$t'] <| ['$bak']"
        Invoke-Kql -Csl $cmd -Endpoint mgmt -TimeoutSec 3600 | Out-Null
        $newCount = Get-RowCount $t
        $manifest.Add([pscustomobject]@{
            Table    = $t
            Backup   = $bak
            BakRows  = $bakCount
            NewRows  = $newCount
            Ok       = ($newCount -eq $bakCount)
        })
    }
    Write-Host "`nRestore manifest:" -ForegroundColor Yellow
    $manifest | Format-Table -AutoSize
    Write-Host "`nRestore complete. Backup tables retained - drop with -Mode Drop -Suffix '$Suffix' when no longer needed." -ForegroundColor Green
    return
}
