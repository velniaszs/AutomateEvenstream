$TenantId          = ""
$ClientId          = ""
$ClientSecret      = ""

# 4 workspace IDs to target
$WorkspaceIds      = @(
    ""
)

# Total items to create per workspace
$ItemsPerWorkspace = 500

# Item type -- Notebook is instant (no provisioning delay)
# Other fast options: Lakehouse, Warehouse (slower to provision)
$ItemType          = "Notebook"

# Prefix for generated item names
$NamePrefix        = "stress-test"

$ErrorActionPreference = "Stop"

# --- Auth ---
$tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "https://api.fabric.microsoft.com/.default"
}
Write-Host "Authenticating..."
$token = (Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody).access_token
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}


$totalCreated = 0
$totalFailed  = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($wsId in $WorkspaceIds) {
    Write-Host "`n-- Workspace $wsId -- ($ItemsPerWorkspace items of type '$ItemType')"
    $wsCreated = 0
    $wsFailed  = 0

    for ($i = 1; $i -le $ItemsPerWorkspace; $i++) {
        $name = "$NamePrefix-$($ItemType.ToLower())-$(Get-Date -Format 'yyyyMMddHHmmss')-$i"

        $payload = @{
            displayName = $name
            type        = $ItemType
        } | ConvertTo-Json

        $uri = "https://api.fabric.microsoft.com/v1/workspaces/$wsId/items"

        $maxRetries = 5
        $attempt    = 0
        $success    = $false
        while (-not $success -and $attempt -lt $maxRetries) {
            try {
                Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $payload | Out-Null
                $success = $true
                $wsCreated++
                $totalCreated++
                if ($wsCreated % 50 -eq 0) {
                    Write-Host "  [$wsId] $wsCreated created so far... ($([math]::Round($sw.Elapsed.TotalMinutes,1)) min)"
                }
            }
            catch {
                $attempt++
                $statusCode = $_.Exception.Response.StatusCode.value__
                if ($statusCode -eq 429) {
                    $retryAfter = 10  # fallback seconds
                    try { $retryAfter = [int]$_.Exception.Response.Headers["Retry-After"] } catch {}
                    Write-Host "  [429] Throttled -- waiting ${retryAfter}s (attempt $attempt/$maxRetries)..."
                    Start-Sleep -Seconds $retryAfter
                }
                elseif ($statusCode -eq 409) {
                    # Name already exists -- skip, no retry
                    $wsFailed++
                    $totalFailed++
                    Write-Warning "  SKIP $name -- already exists (HTTP 409)"
                    break
                }
                else {
                    # Non-throttle error -- no point retrying
                    $wsFailed++
                    $totalFailed++
                    Write-Warning "  FAILED $name (HTTP $statusCode) : $_"
                    break
                }
            }
        }
        if (-not $success -and $attempt -ge $maxRetries) {
            $wsFailed++
            $totalFailed++
            Write-Warning "  FAILED $name --- exhausted $maxRetries retries"
        }
    }

    Write-Host "  [$wsId] Done -- created: $wsCreated  failed: $wsFailed"
}

$sw.Stop()
Write-Host ""
Write-Host "======================================"
Write-Host ("Total created : " + $totalCreated)
Write-Host ("Total failed  : " + $totalFailed)
Write-Host ("Elapsed       : " + [math]::Round($sw.Elapsed.TotalMinutes, 1) + " min")
