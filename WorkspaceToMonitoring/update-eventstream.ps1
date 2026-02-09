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

Write-Host "Updating Eventstream..."
Write-Host "URI: $uri"

try {
    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $jsonPayload -UseBasicParsing
    Write-Host "Eventstream updated successfully."
    #Write-Output $response
}
catch {
    Write-Error "Failed to update Eventstream. Error: $_"
}