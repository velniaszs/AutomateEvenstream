[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [Parameter(Mandatory = $false)]
    [string]$KqlAuthToken,

    [Parameter(Mandatory = $false)]
    [string]$EventhouseName = "MyEventhouse"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AuthToken)) {
    Write-Error "AuthToken is empty."
    return
}

if ([string]::IsNullOrWhiteSpace($KqlAuthToken)) {
    Write-Error "KqlAuthToken is empty."
    return 
}

if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
    Write-Error "WorkspaceId is empty."
    return
}

$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

# 1. Check if Eventhouse exists
Write-Host "Checking for Eventhouse '$EventhouseName'..."
$eventhousesUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses"
try {
    $eventhousesResponse = Invoke-RestMethod -Uri $eventhousesUri -Method Get -Headers $headers
}
catch {
    Write-Error "Failed to list eventhouses. Error: $_"
    return
}

$eventhouse = $eventhousesResponse.value | Where-Object { $_.displayName -eq $EventhouseName }

if ($null -eq $eventhouse) {
    Write-Error "Eventhouse '$EventhouseName' not found in workspace '$WorkspaceId'."
    return
}

Write-Host "Found Eventhouse: $($eventhouse.displayName) (ID: $($eventhouse.id))"

# 2. Find the KQL Database
# We assume the default database has the same name as the Eventhouse.
Write-Host "Looking for KQL Database '$EventhouseName'..."
$kqlDbsUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/kqlDatabases"
try {
    $kqlDbsResponse = Invoke-RestMethod -Uri $kqlDbsUri -Method Get -Headers $headers
}
catch {
    Write-Error "Failed to list KQL databases. Error: $_"
    return
}

$targetDb = $kqlDbsResponse.value | Where-Object { $_.displayName -eq $EventhouseName }

if ($null -eq $targetDb) {
    Write-Error "KQL Database with name '$EventhouseName' not found. Please ensure the database exists."
    return
}

Write-Host "Found KQL Database: $($targetDb.displayName) (ID: $($targetDb.id))"

# 3. Get KQL Database Details to find Query URI
Write-Host "Retrieving connection details..."
$dbDetailsUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/kqlDatabases/$($targetDb.id)"
try {
    $dbDetails = Invoke-RestMethod -Uri $dbDetailsUri -Method Get -Headers $headers
}
catch {
    Write-Error "Failed to get KQL database details. Error: $_"
    return
}

# The property for query URI is usually in 'properties.queryServiceUri'
$queryUri = $dbDetails.properties.queryServiceUri

if ([string]::IsNullOrWhiteSpace($queryUri)) {
    Write-Error "Could not determine Query URI for database. Properties found: $($dbDetails.properties | ConvertTo-Json -Depth 2)"
    return
}

Write-Host "Query URI: $queryUri"

# 4. Execute the Command
$command1 = @'
.create-merge table WorkspaceLogs (type:string, datacontenttype:string, id:guid, ['time']:datetime, dataschemaversion:real, subject:string, source:guid, specversion:real, data_workspaceId:guid, data_workspaceName:string, data_itemName:string, data_itemId:guid, data_itemKind:string, data_executingPrincipalId:guid, data_executingPrincipalType:string)
'@

$command2 = @'
.create-or-alter table WorkspaceLogs ingestion json mapping 'WorkspaceLogs_mapping' 
```
[{"Properties":{"Path":"$['type']"},"column":"type","datatype":""},{"Properties":{"Path":"$['datacontenttype']"},"column":"datacontenttype","datatype":""},{"Properties":{"Path":"$['id']"},"column":"id","datatype":""},{"Properties":{"Path":"$['time']"},"column":"time","datatype":""},{"Properties":{"Path":"$['dataschemaversion']"},"column":"dataschemaversion","datatype":""},{"Properties":{"Path":"$['subject']"},"column":"subject","datatype":""},{"Properties":{"Path":"$['source']"},"column":"source","datatype":""},{"Properties":{"Path":"$['specversion']"},"column":"specversion","datatype":""},{"Properties":{"Path":"$['data']['workspaceId']"},"column":"data_workspaceId","datatype":""},{"Properties":{"Path":"$['data']['workspaceName']"},"column":"data_workspaceName","datatype":""},{"Properties":{"Path":"$['data']['itemName']"},"column":"data_itemName","datatype":""},{"Properties":{"Path":"$['data']['itemId']"},"column":"data_itemId","datatype":""},{"Properties":{"Path":"$['data']['itemKind']"},"column":"data_itemKind","datatype":""},{"Properties":{"Path":"$['data']['executingPrincipalId']"},"column":"data_executingPrincipalId","datatype":""},{"Properties":{"Path":"$['data']['executingPrincipalType']"},"column":"data_executingPrincipalType","datatype":""}]
```
'@

$command3 = @'
.create-merge table WorkspaceOutboundAccessProtection (Activity:string, BillingType:long, ClientIP:string, CreationTime:string, Experience:string, Id:string, ObjectDisplayName:string, ObjectId:string, ObjectType:string, Operation:string, OrganizationId:string, RecordType:long, RefreshEnforcementPolicy:long, RequestId:string, ResultStatus:string, UserAgent:string, UserId:string, UserKey:string, UserType:long, WorkSpaceName:string, Workload:string, WorkspaceId:string) 
'@

$mgmtUri = "$queryUri/v1/rest/mgmt"

$body = @{
    csl = $command1
    db  = $targetDb.displayName
} | ConvertTo-Json

$body2 = @{
    csl = $command2
    db  = $targetDb.displayName
} | ConvertTo-Json

$body3 = @{
    csl = $command3
    db  = $targetDb.displayName
} | ConvertTo-Json

$kqlHeaders = @{
    "Authorization" = "Bearer $KqlAuthToken"
    "Content-Type"  = "application/json"
}

try {
    Write-Host "Creating table 'WorkspaceLogs' in database '$($targetDb.displayName)'..."
    $response = Invoke-RestMethod -Uri $mgmtUri -Method Post -Headers $kqlHeaders -Body $body
    Write-Host "Table created successfully."
    # Write-Output $response
}
catch {
    Write-Error "Failed to create table. Error: $_"
}

try {
    Write-Host "Creating or altering ingestion mapping 'WorkspaceLogs_mapping' in database '$($targetDb.displayName)'..."
    $response2 = Invoke-RestMethod -Uri $mgmtUri -Method Post -Headers $kqlHeaders -Body $body2
    Write-Host "Ingestion mapping created or altered successfully."
    # Write-Output $response2
}
catch {
    Write-Error "Failed to create or alter ingestion mapping. Error: $_"
}

try {
    Write-Host "Altering table policy ingestionbatching for 'WorkspaceLogs' in database '$($targetDb.displayName)'..."
    $response3 = Invoke-RestMethod -Uri $mgmtUri -Method Post -Headers $kqlHeaders -Body $body3
    Write-Host "Table policy ingestionbatching altered successfully."
    # Write-Output $response3
}
catch {
    Write-Error "Failed to alter table policy. Error: $_"
}

return $targetDb.id
