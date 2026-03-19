[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AuthToken
)

$ErrorActionPreference = "Stop"

# 1. Validate Access Token
if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    Write-Error "AuthToken is empty."
    return
}

$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

# 2. List Capacities with Pagination
$url = "https://api.powerbi.com/v1.0/myorg/admin/capacities"
$allCapacities = @()

do {
    #Write-Host "Fetching from: $url"
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
    
    if ($response.value) {
        $allCapacities += $response.value
    }
    
    if ($response.continuationUri) {
        $url = $response.continuationUri
    } else {
        $url = $null
    }
} while ($null -ne $url)

$outputFile = "$PSScriptRoot\input\capacities.json"
$allCapacities | ConvertTo-Json -Depth 5 | Out-File $outputFile
Write-Host "Saved $($allCapacities.Count) capacities to $outputFile"
