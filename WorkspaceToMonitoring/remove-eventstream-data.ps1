param(
    [Parameter(Mandatory = $true)]
    [string]$sourceWorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$capacityName,
    
    [Parameter(Mandatory = $false)]
    [string]$jsonPath = (Join-Path $PSScriptRoot "eventstream.json"),

    [Parameter(Mandatory = $true)]
    [string]$destinationWorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken
)

$sourceWorkspaceName = $sourceWorkspaceName -replace '[^a-zA-Z0-9]', '-'

if (-not (Test-Path $jsonPath)) {
    Write-Error "File not found: $jsonPath"
    exit 1
}

try {
    $jsonContent = Get-Content -Path $jsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    
}
catch {
    Write-Error "Failed to parse JSON file. Error: $_"
    exit 1
}

if (-not $jsonContent) {
    Write-Warning "File is empty or invalid JSON structure."
    exit
}

# 3. Remove the source object by sourceWorkspaceName
$initialSourceCount = $jsonContent.sources.Count
$jsonContent.sources = @($jsonContent.sources | Where-Object { $_.name -ne $sourceWorkspaceName })
$finalSourceCount = $jsonContent.sources.Count

if ($finalSourceCount -eq 0) {
    #Write-Host "No sources remaining. Deleting Eventstream..."
    
    # Check if exists and get ID
    $getEvenstreamIdScript = Join-Path $PSScriptRoot "get-evenstream-id.ps1"
    $checkResult = & $getEvenstreamIdScript -WorkspaceId $destinationWorkspaceId -AuthToken $AuthToken -EventstreamName $capacityName
    
    if ($checkResult.Exists) {
        $esId = $checkResult.Id
        Write-Host "No sources left. Deleting Eventstream '$capacityName' (ID: $esId)..."
        
        $deleteUri = "https://api.fabric.microsoft.com/v1/workspaces/$destinationWorkspaceId/eventstreams/$esId"
        $headers = @{
            "Authorization" = "Bearer $AuthToken"
        }
        
        try {
            Invoke-RestMethod -Uri $deleteUri -Method Delete -Headers $headers -ErrorAction Stop
            #Write-Host "Successfully deleted Eventstream '$capacityName'."
            return $true
        }
        catch {
            Write-Error "Failed to delete Eventstream. Error: $_"
            return $false
        }
    } else {
        Write-Error "Eventstream '$capacityName' not found, cannot delete."
        return $false
    }
    
    # Exit to skip further processing / saving file as we deleted the resource
    return

} else {
    if ($finalSourceCount -lt $initialSourceCount) {
        #Write-Host "Removed source '$sourceWorkspaceName' from 'sources'."
    } else {
        Write-Error "Source '$sourceWorkspaceName' not found in 'sources'."
        exit 1
    }

    # 5. Remove the source from the stream's inputNodes
    #    Find the stream by name (e.g., "LoadWorkspaceChanges-stream")
    $stream = $jsonContent.streams | Where-Object { $_.name -eq "$capacityName-stream" }

    if ($stream) {
        # Filter out the node with the matching name
        $initialNodeCount = $stream.inputNodes.Count
        $stream.inputNodes = @($stream.inputNodes | Where-Object { $_.name -ne $sourceWorkspaceName })
        $finalNodeCount = $stream.inputNodes.Count
        
        if ($finalNodeCount -lt $initialNodeCount) {
            #Write-Host "Removed '$sourceWorkspaceName' from stream '$capacityName-stream'."
        } else {
            Write-Error "'$sourceWorkspaceName' not found in stream '$capacityName-stream' inputNodes."
            exit 1
        }
    } else {
        Write-Error "Stream '$capacityName-stream' not found."
        exit 1
    }
    # 6. Save the file
    #    IMPORTANT: -Depth 10 is required to preserve nested properties
    $outputjsonPath = "$PSScriptRoot\Output\$capacityName.json"
    $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $outputjsonPath -Encoding UTF8

    #Write-Host "Successfully updated $outputjsonPath"
    return $false

}
