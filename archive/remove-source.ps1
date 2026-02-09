param(
    [Parameter(Mandatory = $true)]
    [string]$workspaceName
)

# 1. Path to your JSON file
$jsonPath = Join-Path $PSScriptRoot "eventstream.json"

# 2. Read and parse the JSON
$jsonContent = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json

# 3. Remove the source from 'sources' array
$sourceToRemove = $jsonContent.sources | Where-Object { $_.name -eq $workspaceName }

if ($sourceToRemove) {
    # Rebuild the array excluding the item to remove
    $jsonContent.sources = @($jsonContent.sources | Where-Object { $_.name -ne $workspaceName })
    Write-Host "Removed source '$workspaceName'."
} else {
    Write-Warning "Source '$workspaceName' not found in sources."
}

# 4. Remove the source from the stream's inputNodes
$targetStreamName = "LoadWorkspaceChanges-stream"
$stream = $jsonContent.streams | Where-Object { $_.name -eq $targetStreamName }

if ($stream) {
    $nodeToRemove = $stream.inputNodes | Where-Object { $_.name -eq $workspaceName }
    if ($nodeToRemove) {
        # Rebuild the array excluding the item to remove
        $stream.inputNodes = @($stream.inputNodes | Where-Object { $_.name -ne $workspaceName })
        Write-Host "Removed '$workspaceName' from stream '$targetStreamName'."
    } else {
        Write-Warning "Source '$workspaceName' not found in stream '$targetStreamName' inputNodes."
    }
} else {
    Write-Warning "Stream '$targetStreamName' not found."
}

# 5. Save the file
#    IMPORTANT: -Depth 10 is required to preserve nested properties
$jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host "Successfully updated $jsonPath"
