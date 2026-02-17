[CmdletBinding()]
param(
    [string]$EnvironmentUrl = "https://orgd2bf3532.crm4.dynamics.com" # Replace with your actual environment URL
)

$ErrorActionPreference = "Stop"

# --- Authenticate ---
Write-Host "Retrieving Dataverse Token..."
$tokenScript = Join-Path $PSScriptRoot "get-Dataverse-token.ps1"
try {
    $token = & $tokenScript -environmentUrl $EnvironmentUrl
}
catch {
    Write-Error "Failed to retrieve token: $_"
    return
}

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Token is empty."
    return
}

# --- Query Dataverse (Accounts) ---
# Ensure environment URL doesn't end with slash strictly for constructing the URI
if ($EnvironmentUrl.EndsWith("/")) {
    $EnvironmentUrl = $EnvironmentUrl.TrimEnd("/")
}

$apiVersion = "v9.2"
$entityDetail = "accounts" 
# Example query: Select specific columns to reduce payload (name, accountnumber)
$query = "?`$select=name,accountnumber&`$top=5" 

$uri = "$EnvironmentUrl/api/data/$apiVersion/$entityDetail$query"

Write-Host "Querying Accounts from: $uri"

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
    "Prefer" = "odata.include-annotations=OData.Community.Display.V1.FormattedValue"
}

try {
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
    
    # Check if value property exists (OData standard response wrapper)
    if ($response.value -and $response.value.Count -gt 0) {
        Write-Host "Successfully retrieved $($response.value.Count) accounts."
        
        # Assign value from the first account
        $firstAccount = $response.value[0]
        $accountNumber = $firstAccount.accountnumber
        $accountName = $firstAccount.name
        
        Write-Host "First Account Number: $accountNumber"
        Write-Host "First Account Name: $accountName"

        # If you want to iterate through all
        # foreach ($acc in $response.value) { ... }
    } else {
        Write-Host "No accounts found or unexpected response structure."
        Write-Host "Response structure:"
        Write-Host ($response | ConvertTo-Json -Depth 2)
    }
}
catch {
    Write-Error "Failed to query Dataverse. $_"
    # Print detailed error if available from OData error
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $errorResponse = $reader.ReadToEnd()
        Write-Host "Detailed Error Response: $errorResponse" -ForegroundColor Red
    }
}
