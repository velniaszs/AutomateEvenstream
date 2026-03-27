# Azure Key Vault Secret Retrieval Script
# Authenticates using Service Principal (Client ID + Secret)

# Configuration
$tenantId = "<YOUR_TENANT_ID>"
$clientId = "<YOUR_CLIENT_ID>"
$clientSecret = "<YOUR_CLIENT_SECRET>"
$keyVaultName = "<YOUR_KEYVAULT_NAME>"
$secretName = "<YOUR_SECRET_NAME>"

# Convert client secret to secure string
$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force

# Create PSCredential object
$credential = New-Object System.Management.Automation.PSCredential($clientId, $secureSecret)

try {
    Write-Host "Connecting to Azure using Service Principal..." -ForegroundColor Cyan
    
    # Connect to Azure using Service Principal
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId -ErrorAction Stop
    
    Write-Host "Successfully authenticated!" -ForegroundColor Green
    
    # Retrieve the secret from Key Vault
    Write-Host "Retrieving secret '$secretName' from Key Vault '$keyVaultName'..." -ForegroundColor Cyan
    
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -AsPlainText -ErrorAction Stop
    
    Write-Host "Secret retrieved successfully!" -ForegroundColor Green
    Write-Host "Secret Value: $secret" -ForegroundColor Yellow
    
    # If you don't want to display the secret, uncomment this instead:
    # Write-Host "Secret retrieved successfully (value hidden for security)" -ForegroundColor Green
    # return $secret
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} finally {
    # Disconnect from Azure
    Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Disconnected from Azure" -ForegroundColor Gray
}
