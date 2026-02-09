[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$EventstreamId,

    [string]$OutputFile = "$PSScriptRoot\eventstream.json",
    [string]$AccessTokenFile = "$PSScriptRoot\access_token.txt"
)

$ErrorActionPreference = "Stop"

# Ensure paths are absolute or relative to script location if not specified
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
    $OutputFile = Join-Path $PSScriptRoot $OutputFile
}
if (-not [System.IO.Path]::IsPathRooted($AccessTokenFile)) {
    $AccessTokenFile = Join-Path $PSScriptRoot $AccessTokenFile
}

# 1. Read and validate Access Token
if (-not (Test-Path $AccessTokenFile)) {
    Write-Error "Access token file not found: $AccessTokenFile"
    return
}
$token = Get-Content -Path $AccessTokenFile -Raw
$token = $token.Trim().Trim("'").Trim('"')

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Access token is empty."
    return
}

# 2. Send Request
$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams/$EventstreamId/getDefinition"
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

Write-Host "Retrieving Eventstream Definition..."
Write-Host "URI: $uri"

try {
    # The API requires a POST request, even though we are retrieving data.
    # Some APIs might require an empty body for POST requests if no parameters are needed.
    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body "{}" -UseBasicParsing
    
    if ($response.StatusCode -eq 200) {
        Write-Host "Request successful (200)." -ForegroundColor Green
        
        $jsonResponse = $response.Content | ConvertFrom-Json
        
        # 3. Extract and Decode Definition
        $parts = $jsonResponse.definition.parts
        $eventstreamPart = $parts | Where-Object { $_.path -eq "eventstream.json" }

        if ($eventstreamPart) {
            $base64Payload = $eventstreamPart.payload
            $decodedBytes = [System.Convert]::FromBase64String($base64Payload)
            $decodedContent = [System.Text.Encoding]::UTF8.GetString($decodedBytes)

            # 4. Write to File
            Set-Content -Path $OutputFile -Value $decodedContent -Encoding UTF8
            Write-Host "Eventstream definition saved to: $OutputFile" -ForegroundColor Green
        }
        else {
            Write-Error "Could not find 'eventstream.json' part in the response definition."
            Write-Host "Available parts: $($parts.path -join ', ')"
        }
    }
    else {
        Write-Host "Unexpected status code: $($response.StatusCode)"
        Write-Host $response.Content
    }
}
catch {
    Write-Host "Request failed." -ForegroundColor Red
    Write-Host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode
        $statusDescription = $_.Exception.Response.StatusDescription
        Write-Host "Status: $statusCode $statusDescription" -ForegroundColor Red

        $stream = $_.Exception.Response.GetResponseStream()
        if ($stream) {
            $reader = New-Object System.IO.StreamReader($stream)
            $body = $reader.ReadToEnd()
            Write-Host "Response Body: $body" -ForegroundColor Yellow
        }
    }
}
