# =====================================================================================
# debug-eventstream-destination.ps1
# -------------------------------------------------------------------------------------
# Fetches an Eventstream definition via the Fabric REST API and inspects each
# destination for indicators of a "silent failure" during destination creation.
#
# What it checks per destination:
#   - properties.dataConnectionId    -> empty / all-zero GUID means KQL rejected create
#   - properties.connectionName
#   - properties.workspaceId / itemId / tableName
#   - inputNodes / inputSchemas presence and names
#   - status / state fields (when present in the payload)
#
# Usage:
#   .\debug-eventstream-destination.ps1 `
#       -WorkspaceId   '<ws-guid>' `
#       -EventstreamId '<es-guid>' `
#       -AuthToken     $fabricToken
#
#   # or let the script grab a token using the shared helper
#   .\debug-eventstream-destination.ps1 -WorkspaceId '<ws>' -EventstreamId '<es>'
#
# Optional:
#   -OutputFile  Path to dump the decoded eventstream.json (defaults to a temp file)
#   -Raw         Also print the full decoded JSON
# =====================================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId = '9e929790-272d-4977-a2ab-301443c11ece',

    [Parameter(Mandatory = $false)]
    [string]$ClientId = 'b5c04c9c-0588-418f-8f60-2d83d38cb635',

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = '',

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceId = '611585cb-6332-4849-995e-efce839973f1',

    [Parameter(Mandatory = $true)]
    [string]$EventstreamId,

    [string]$AuthToken,

    [string]$OutputFile,

    [switch]$Raw
)

$ErrorActionPreference = 'Stop'

# -------------------------------------------------------------------------------------
# 1. Acquire token if not provided (mirrors AddWorkspace.ps1 pattern)
# -------------------------------------------------------------------------------------
if (-not $AuthToken) {
    $tokenScript = Join-Path $PSScriptRoot '..\get-Fabric-token.ps1'
    if (-not (Test-Path $tokenScript)) {
        throw "AuthToken not provided and helper not found at: $tokenScript"
    }
    Write-Host "Acquiring Fabric token via $tokenScript ..." -ForegroundColor DarkGray
    $AuthToken = & $tokenScript -tenantId $TenantId -clientId $ClientId -client_secret $ClientSecret
}

if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    throw "Failed to obtain Fabric AuthToken."
}

# -------------------------------------------------------------------------------------
# 2. Resolve output file (default: WorkspaceToMonitoring\Output\debug-<id>.json)
# -------------------------------------------------------------------------------------
if (-not $OutputFile) {
    $debugFolder = Join-Path $PSScriptRoot 'Output'
    if (-not (Test-Path $debugFolder)) {
        New-Item -ItemType Directory -Path $debugFolder | Out-Null
    }
    $OutputFile = Join-Path $debugFolder "debug-$EventstreamId.json"
}
else {
    $parent = Split-Path $OutputFile -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
}

# -------------------------------------------------------------------------------------
# 3. Call getDefinition
# -------------------------------------------------------------------------------------
$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams/$EventstreamId/getDefinition"
$headers = @{
    'Authorization' = "Bearer $AuthToken"
    'Content-Type'  = 'application/json'
}

Write-Host ""
Write-Host "POST $uri" -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body '{}' -UseBasicParsing
}
catch {
    Write-Host ""
    Write-Host "REST call failed:" -ForegroundColor Red
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        Write-Host $reader.ReadToEnd() -ForegroundColor Red
    } else {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    throw
}

if ($response.StatusCode -ne 200) {
    Write-Error "Unexpected status code: $($response.StatusCode)"
    Write-Host $response.Content
    return
}

$jsonResponse = $response.Content | ConvertFrom-Json
$eventstreamPart = $jsonResponse.definition.parts | Where-Object { $_.path -eq 'eventstream.json' }

if (-not $eventstreamPart) {
    Write-Error "No 'eventstream.json' part in definition. Parts: $($jsonResponse.definition.parts.path -join ', ')"
    return
}

$decodedBytes   = [System.Convert]::FromBase64String($eventstreamPart.payload)
$decodedContent = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
# Write raw bytes so the file is byte-identical to what the API returned (no BOM, no EOL changes)
[System.IO.File]::WriteAllBytes($OutputFile, $decodedBytes)

Write-Host "Decoded definition saved to: $OutputFile" -ForegroundColor DarkGray

$definition = $decodedContent | ConvertFrom-Json

# -------------------------------------------------------------------------------------
# 4. Inspect destinations
# -------------------------------------------------------------------------------------
$emptyGuid = '00000000-0000-0000-0000-000000000000'

if (-not $definition.destinations -or $definition.destinations.Count -eq 0) {
    Write-Warning "No destinations found in eventstream definition."
    return
}

Write-Host ""
Write-Host "=== Destinations ($($definition.destinations.Count)) ===" -ForegroundColor Cyan

$problems = @()
$idx = 0
foreach ($destination in $definition.destinations) {
    $idx++
    Write-Host ""
    Write-Host ("[{0}] {1} ({2})" -f $idx, $destination.name, $destination.type) -ForegroundColor Yellow
    Write-Host "    id              : $($destination.id)"

    $props = $destination.properties
    if ($props) {
        $dataConnectionId = $props.dataConnectionId
        $connectionName   = $props.connectionName
        $tableName        = $props.tableName
        $itemId           = $props.itemId
        $destWsId         = $props.workspaceId
        $mappingRuleName  = $props.mappingRuleName

        Write-Host "    workspaceId     : $destWsId"
        Write-Host "    itemId          : $itemId"
        Write-Host "    tableName       : $tableName"
        Write-Host "    mappingRuleName : $mappingRuleName"
        Write-Host "    connectionName  : $connectionName"

        if ($null -eq $dataConnectionId -or $dataConnectionId -eq '') {
            Write-Host "    dataConnectionId: <missing>" -ForegroundColor Red
            $problems += "[$($destination.name)] dataConnectionId is missing -> destination creation likely failed silently."
        }
        elseif ($dataConnectionId -eq $emptyGuid) {
            Write-Host "    dataConnectionId: $dataConnectionId" -ForegroundColor Red
            $problems += "[$($destination.name)] dataConnectionId is the empty GUID -> KQL/Eventhouse rejected the create request."
        }
        else {
            Write-Host "    dataConnectionId: $dataConnectionId" -ForegroundColor Green
        }

        # Status / state hints (may not always be present)
        foreach ($field in 'status','state','provisioningState','lastError','errorMessage') {
            if ($props.PSObject.Properties.Name -contains $field) {
                $val = $props.$field
                $color = if ($field -in 'lastError','errorMessage' -and $val) { 'Red' } else { 'DarkGray' }
                Write-Host ("    {0,-15} : {1}" -f $field, $val) -ForegroundColor $color
            }
        }
    }
    else {
        Write-Host "    <no properties block>" -ForegroundColor Red
        $problems += "[$($destination.name)] destination has no properties."
    }

    # inputNodes
    if ($destination.inputNodes -and $destination.inputNodes.Count -gt 0) {
        Write-Host "    inputNodes      : $($destination.inputNodes.name -join ', ')"
    } else {
        Write-Host "    inputNodes      : <empty>" -ForegroundColor Red
        $problems += "[$($destination.name)] inputNodes is empty."
    }

    # inputSchemas
    if ($destination.inputSchemas -and $destination.inputSchemas.Count -gt 0) {
        $schemaNames = $destination.inputSchemas.name -join ', '
        Write-Host "    inputSchemas    : $schemaNames"
    } else {
        Write-Host "    inputSchemas    : <missing>" -ForegroundColor DarkYellow
    }
}

# -------------------------------------------------------------------------------------
# 5. Summary
# -------------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
if ($problems.Count -eq 0) {
    Write-Host "No silent-failure indicators detected." -ForegroundColor Green
} else {
    foreach ($p in $problems) {
        Write-Host " - $p" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Decoded definition saved to: $OutputFile" -ForegroundColor Green

if ($Raw) {
    Write-Host ""
    Write-Host "=== Decoded eventstream.json ===" -ForegroundColor Cyan
    Write-Host $decodedContent
}
