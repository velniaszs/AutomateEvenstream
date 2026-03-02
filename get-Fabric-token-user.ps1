# get-Fabric-token-user.ps1
# Retrieves a Fabric API token using the current logged-in user context (Azure PowerShell)
# Requires the Az module. Run Connect-AzAccount first if needed.

#do: Connect-AzAccount to login before running this script.
$ErrorActionPreference = "Stop"

try {
    # Resource URL for Fabric API
    $resource = "https://api.fabric.microsoft.com/"
    
    # Attempt to get the access token for the Fabric resource
    $tokenObject = Get-AzAccessToken -ResourceUrl $resource -ErrorAction Stop
    
    # Return just the token string to match the behavior of the original script
    return $tokenObject.Token
}
catch {
    Write-Error "Failed to retrieve Fabric token for user. Ensure you are logged in with 'Connect-AzAccount'. Error: $_"
    exit 1
}
