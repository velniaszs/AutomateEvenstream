$workspaceId = "af2b1ae0-5660-454c-9952-b01cffde1d2f"

for ($i = 1; $i -le 48; $i++) {
    # Generate a random alphanumeric string (10 chars)
    # ASCII ranges: 48-57 (0-9), 65-90 (A-Z), 97-122 (a-z)
    $chars = (48..57) + (65..90) + (97..122)
    $randomString = -join ($chars | Get-Random -Count 10 | ForEach-Object { [char]$_ })
    
    $uniqueName = "Source_$randomString"
    
    Write-Host "[$i/1000] Adding source: $uniqueName"
    
    # Call the add_sourceDummy.ps1 script
    & "$PSScriptRoot\add-source.ps1" -workspaceName $uniqueName -workspaceId $workspaceId -CheckWorkspace "no"

    # Add a small delay to prevent file locking issues
    Start-Sleep -Milliseconds 200
}
