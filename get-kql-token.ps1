param(
    [string]$tenantId ,
    [string]$clientId ,
    [string]$client_secret
)

$ErrorActionPreference = "Stop"

# --- Authenticate to KQL ---
# The resource URI for Kusto/KQL is typically https://kusto.kusto.windows.net
$scope = "https://kusto.kusto.windows.net/.default"
$tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $client_secret
    scope         = $scope
}

#Write-Host "Authenticating to Azure AD for KQL ($tokenUrl)..."
try {
    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body
    $token = $response.access_token
    Write-Output $token
}
catch {
    Write-Error "Failed to authenticate. Error: $_"
}
