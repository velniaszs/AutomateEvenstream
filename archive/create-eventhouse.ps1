[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [Parameter(Mandatory = $false)]
    [string]$DisplayName = "MyEventhouse"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    Write-Error "AuthToken is empty."
    return
}

if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
    Write-Error "WorkspaceId is empty."
    return
}

$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses"

try {
    Write-Host "Checking if Eventhouse '$DisplayName' already exists..."
    $getResponse = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
    $existing = $getResponse.value | Where-Object { $_.displayName -eq $DisplayName }

    if ($existing) {
        Write-Host "Eventhouse '$DisplayName' already exists." -ForegroundColor Yellow
        #Write-Output $existing
        return
    }

    $body = @{
        displayName = $DisplayName
    } | ConvertTo-Json

    Write-Host "Creating Eventhouse '$DisplayName' in workspace '$WorkspaceId'..."
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
    Write-Host "Eventhouse created successfully."
    #Write-Output $response
}
catch {
    Write-Error "Failed to process Eventhouse.$responseDetails Error: $_"
}
