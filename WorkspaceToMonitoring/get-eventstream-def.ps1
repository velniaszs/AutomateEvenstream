[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [Parameter(Mandatory = $true)]
    [string]$EventstreamId,
    [string]$OutputFile = "$PSScriptRoot\input\eventstream.json"
)

$ErrorActionPreference = "Stop"


$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventstreams/$EventstreamId/getDefinition"
$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

try {
    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body "{}" -UseBasicParsing
    
    if ($response.StatusCode -eq 200) {
        
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
            #Write-Host "Eventstream definition saved to: $OutputFile"
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
    throw "Failed to create eventstream json '$EventstreamId'. Error: $_"
}