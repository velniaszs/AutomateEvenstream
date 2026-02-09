param(
    [string]$tenantId,
    [string]$clientId,
    [string]$client_secret,
    [ValidateSet("kusto", "fabric")]
    [string]$scope_type = "fabric"
)

$ErrorActionPreference = "Stop"

# --- Authenticate ---

if ($scope_type -eq "kusto") {
    $scope = "https://kusto.kusto.windows.net/.default"
}
else {
    $scope = "https://api.fabric.microsoft.com/.default"
}

$tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $client_secret
    scope         = $scope
}

#Write-Host "Authenticating to Azure AD ($tokenUrl)..."
try {
    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body
    $token = $response.access_token
    return $token
}
catch {
    Write-Error "Authentication failed. $_"
    exit 1
}