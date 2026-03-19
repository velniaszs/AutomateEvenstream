[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$EventstreamId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [string]$DefinitionFile = "$PSScriptRoot\eventstream.json"
)

$ErrorActionPreference = "Stop"

# Ensure paths are absolute or relative to script location if not specified
if (-not [System.IO.Path]::IsPathRooted($DefinitionFile)) {
    $DefinitionFile = Join-Path $PSScriptRoot $DefinitionFile
}

# 1. Validate Access Token
if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    Write-Error "AuthToken is empty."
    return
}

# 2. Read and encode Definition
if (-not (Test-Path $DefinitionFile)) {
    Write-Error "Definition file not found: $DefinitionFile"
    return
}

$definitionContent = Get-Content -Path $DefinitionFile -Raw -Encoding UTF8
$definitionBytes = [System.Text.Encoding]::UTF8.GetBytes($definitionContent)
$definitionBase64 = [System.Convert]::ToBase64String($definitionBytes)

# 3. Construct Payload
$payload = @{
    definition = @{
        parts = @(
            @{
                path = "eventstream.json"
                payload = $definitionBase64
                payloadType = "InlineBase64"
            }
        )
    }
}

$jsonPayload = $payload | ConvertTo-Json -Depth 10

# 4. Send Request
$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams/$EventstreamId/updateDefinition"
$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

#Write-Host "Updating Eventstream..."
#Write-Host "URI: $uri"

$maxRetries = 5
$attempt = 0
while ($attempt -le $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $jsonPayload -UseBasicParsing
        #Write-Host "Eventstream updated successfully."
        #Write-Output $response
        break
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 429 -and $attempt -lt $maxRetries) {
            $retryAfter = $_.Exception.Response.Headers["Retry-After"]
            if (-not $retryAfter) { $retryAfter = 60 }
            Write-Warning "Rate limit hit (429). Waiting $retryAfter seconds before retry (attempt $($attempt + 1)/$maxRetries)..."
            Start-Sleep -Seconds ([int]$retryAfter)
            $attempt++
        }
        else {
            Write-Error "Failed to update Eventstream. Error: $_"
            break
        }
    }
}