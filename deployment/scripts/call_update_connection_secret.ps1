$env:NEW_CLIENT_SECRET = "your-new-client-secret-here" # Replace with your actual new client secret

# Use the venv interpreter (it has requests / azure-identity installed)
$python = Join-Path $PSScriptRoot "..\venv-py312\Scripts\python.exe"

& $python (Join-Path $PSScriptRoot "update_connection_secret.py") `
    --tenant-id 'ttt' `
    --client-id 'ccc' `
    --connection-name "connection-name" `