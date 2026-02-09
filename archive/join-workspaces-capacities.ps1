param(
    [int]$GroupSize = 5
)

$workspacesPath = Join-Path $PSScriptRoot "\input\workspaces.json"
$capacitiesPath = Join-Path $PSScriptRoot "\input\capacities.json"
$outputPath = Join-Path $PSScriptRoot "\input\workspace_capacity_details.json"

# Check if files exist
if (-not (Test-Path $workspacesPath)) { Write-Error "workspaces.json not found at $workspacesPath"; exit }
if (-not (Test-Path $capacitiesPath)) { Write-Error "capacities.json not found at $capacitiesPath"; exit }

# Read JSON files
$workspaces = Get-Content $workspacesPath | ConvertFrom-Json
$capacities = Get-Content $capacitiesPath | ConvertFrom-Json

# Perform Left Join (Workspaces -> Capacities)
$capacityCounters = @{}

$joinedData = foreach ($ws in $workspaces) {
    $capacity = $capacities | Where-Object { $_.id -eq $ws.capacityId }

    # Skip if capacity not found
    if (-not $capacity) {
        continue
    }

    # Filter out workspaces on PP or FT capacities
    if ($capacity.sku -match "^(PP|FT)") {
        continue
    }

    # Calculate Grouping
    $capId = $ws.capacityId
    if (-not $capacityCounters.ContainsKey($capId)) {
        $capacityCounters[$capId] = 0
    }
    $capacityCounters[$capId]++
    
    $count = $capacityCounters[$capId]
    $groupIndex = [math]::Floor(($count - 1) / $GroupSize)
    
    $capacityName = $capacity.displayName
    
    $workspaceGroup = $capacityName
    if ($groupIndex -gt 0) {
        $workspaceGroup = "${capacityName}___${groupIndex}"
    }

    [PSCustomObject]@{
        RegionName        = $capacity.region
        CapacityName      = $capacityName
        workspaceGroup    = $workspaceGroup
        CapacityId        = $ws.capacityId
        WorkspaceName     = $ws.name
        WorkspaceId       = $ws.id
    }
}

# Save joined data to new file
$joinedData | ConvertTo-Json -Depth 10 | Set-Content -Path $outputPath
Write-Host "Joined data saved to: $outputPath"

# Read the new file and calculate workspaces per capacity
#Write-Host "`n--- Workspaces per Capacity ---"
#$readData = Get-Content $outputPath | ConvertFrom-Json

#$stats = $readData | Group-Object CapacityId | Select-Object @{N='CapacityId';E={$_.Name}}, Count
#$stats | Format-Table -AutoSize

#Write-Host "`n--- Workspaces per Group (Max 5) ---"
#$groupStats = $readData | Group-Object "workspaceGroup" | Select-Object @{N='workspaceGroup';E={$_.Name}}, Count
#$groupStats | Format-Table -AutoSize
