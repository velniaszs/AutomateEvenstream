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
$url = 'https://api.powerbi.com/v1.0/myorg/admin/groups?$filter=isOnDedicatedCapacity eq true&$top=1'
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        Write-Host $response
    }
    catch {
        Write-Error "Failed to fetch workspaces. Error: $_"
        return
    }