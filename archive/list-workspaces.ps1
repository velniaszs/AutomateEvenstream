[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AuthToken,
    [string]$OutputFile = "$PSScriptRoot\input\workspaces.json",
    [bool]$VerifyOAP = $true,
    [string]$WorkspaceId
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

# 2. List Workspaces with Pagination
$url = "https://api.fabric.microsoft.com/v1/admin/workspaces?state=Active&type=Workspace"
$allWorkspaces = @()

Write-Host "Starting workspace discovery..."

do {
    #Write-Host "Fetching from: $url"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
    }
    catch {
        Write-Error "Failed to fetch workspaces. Error: $_"
        return
    }

    if ($response.workspaces) {
        $allWorkspaces += $response.workspaces
    }

    # Handle Pagination
    # The API returns 'continuationUri' for the next page if available
    if ($response.continuationUri) {
        $url = $response.continuationUri
    } else {
        $url = $null
    }

} while ($null -ne $url)

Write-Host "Total workspaces found: $($allWorkspaces.Count)"

if ($VerifyOAP) {
    # Filter by Network Communication Policy
    $validWorkspaces = @()
    Write-Host "Checking network policies..."

    foreach ($ws in $allWorkspaces) {
        $policyUrl = "https://api.fabric.microsoft.com/v1/workspaces/$($ws.id)/networking/communicationPolicy"
        
        # Default to keeping it unless explicitly disabled
        $keep = $true

        try {
            $policyResponse = Invoke-RestMethod -Uri $policyUrl -Method Get -Headers $headers -ErrorAction Stop
            if ($policyResponse.outbound.publicAccessRules.defaultAction -eq "Deny") {
                Write-Host "  [Excluded] '$($ws.displayName)': Outbound public access is Deny." -ForegroundColor Yellow
                $keep = $false
            }
        }
        catch {
            Write-Host "  [Warning] Could not check policy for '$($ws.displayName)': $($_.Exception.Message)" -ForegroundColor DarkGray
            #throw "Failed to check policy for '$($ws.displayName)': $($_.Exception.Message)"
        }

        if ($keep) {
            $validWorkspaces += $ws
        }
    }

    $allWorkspaces = $validWorkspaces
    Write-Host "Total workspaces after policy check: $($allWorkspaces.Count)"
}

if (-not [string]::IsNullOrWhiteSpace($WorkspaceId)) {
    $allWorkspaces = $allWorkspaces | Where-Object { $_.id -ne $WorkspaceId }
    Write-Host "Removed workspace with ID $WorkspaceId. Total workspaces: $($allWorkspaces.Count)"
}

# 3. Save Result
$allWorkspaces | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputFile -Encoding UTF8
Write-Host "Workspace list saved to: $OutputFile"

# 4. Output List to Console
#$allWorkspaces | Select-Object id, displayName, type | Format-Table -AutoSize
