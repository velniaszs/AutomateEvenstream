[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Fabric", "PowerBI")]
    [string]$Scope = "Fabric",

    [Parameter(Mandatory = $false)]
    [string]$ClientId # Optional: for User Assigned Managed Identity
)

$resource = ""
switch ($Scope) {
    "Fabric"  { $resource = "https://api.fabric.microsoft.com" }
    "PowerBI" { $resource = "https://analysis.windows.net/powerbi/api" }
}

Write-Host "Getting Managed Identity token for $Scope ($resource)..."

try {
    # Using the local Instance Metadata Service (IMDS) available on Azure VMs, Automation, etc.
    $uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$resource"
    
    if (-not [string]::IsNullOrWhiteSpace($ClientId)) {
        $uri += "&client_id=$ClientId"
    }

    $response = Invoke-RestMethod -Method GET `
        -Uri $uri `
        -Headers @{Metadata="true"} -ErrorAction Stop

    return $response.access_token
}
catch {
    Write-Warning "Failed to get token via IMDS (http://169.254.169.254). If you are running locally, try 'Get-AzAccessToken'."
    Write-Error "Error details: $_"
}
