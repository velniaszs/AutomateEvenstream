[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$AOPSetting,

    [Parameter(Mandatory = $true)]
    [string]$KqlAuthToken,

    [Parameter(Mandatory = $true)]
    [string]$QueryUri,

    [Parameter(Mandatory = $true)]
    [string]$DatabaseName
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($KqlAuthToken)) {
    Write-Error "KqlAuthToken is empty."
    return
}

if ([string]::IsNullOrWhiteSpace($DatabaseName)) {
    Write-Error "DatabaseName parameter is empty."
    return
}

if ([string]::IsNullOrWhiteSpace($QueryUri)) {
    Write-Error "QueryUri parameter is empty."
    return
}

$kqlHeaders = @{
    "Authorization" = "Bearer $KqlAuthToken"
    "Content-Type"  = "application/json"
}

$escapedWorkspaceName = $WorkspaceName -replace "'", "''"

# 4. Create Table if not exists (using .create-merge)
$createTableQuery = ".create-merge table WorkspaceOutboundAccessProtection (Activity:string, BillingType:long, ClientIP:string, CreationTime:datetime, Experience:string, Id:guid, ObjectDisplayName:string, ObjectId:string, ObjectType:string, Operation:string, OrganizationId:string, RecordType:long, RefreshEnforcementPolicy:long, RequestId:string, ResultStatus:string, UserAgent:string, UserId:string, UserKey:string, UserType:long, WorkSpaceName:string, Workload:string, WorkspaceId:guid)"

$createTableBody = @{
    csl = $createTableQuery
    db  = $databaseName
} | ConvertTo-Json

try {
    #Write-Host "Ensuring table 'WorkspaceOutboundAccessProtection' exists..."
    $null = Invoke-RestMethod -Uri "$queryUri/v1/rest/mgmt" -Method Post -Headers $kqlHeaders -Body $createTableBody
    #Write-Host "Table 'WorkspaceOutboundAccessProtection' ensured."
}
catch {
    Write-Error "Failed to create/merge table. Error: $_"
    return
}

# 5. Check if record exists
$queryEndpoint = "$queryUri/v1/rest/query"
$checkQuery = "WorkspaceOutboundAccessProtection | where WorkspaceId == '$WorkspaceId' | count as RwCnt"

$queryBody = @{
    csl = $checkQuery
    db  = $databaseName
} | ConvertTo-Json

try {
    #Write-Host "Checking if WorkspaceId '$WorkspaceId' exists in table 'WorkspaceOutboundAccessProtection'..."
    $queryResponse = Invoke-RestMethod -Uri $queryEndpoint -Method Post -Headers $kqlHeaders -Body $queryBody
    
    # queryResponse usually has structure { tables: [ { name: "PrimaryResult", columns: [...], rows: [[0]] } ] }
    $count = 0
    if ($queryResponse.Tables) {
        $primaryTable = $queryResponse.Tables | Where-Object { 
            ($_.Name -eq "PrimaryResult" -or $_.TableName -eq "PrimaryResult" -or $_.Name -eq "Table_0" -or $_.TableName -eq "Table_0") 
        } | Select-Object -First 1

        if ($primaryTable -and $primaryTable.Rows.Count -gt 0) {
            # Try flexible access to get the first value of the first row
            $row = $primaryTable.Rows[0]
            if ($row -is [System.Collections.IList] -and $row.Count -gt 0) {
                 $count = $row[0]
            } elseif ($row.PSObject.Properties['RwCnt']) {
                 $count = $row.RwCnt
            } else {
                 # Fallback: take the value of the first property found
                 $props = $row.PSObject.Properties.Name
                 if ($props) {
                     $firstProp = ($props | Select-Object -First 1)
                     $count = $row.$firstProp
                 } else {
                     $count = $row
                 }
            }
        }
    }
    #Write-Host "Found $count records for WorkspaceId '$WorkspaceId'."
}
catch {
    Write-Error "Failed to query table. Error: $_"
    return
}

if ($count -gt 0) {
    Write-Host "Record already exists, skipping insertion."
    return
}

# 5. Insert record if not exists
$mgmtUri = "$queryUri/v1/rest/mgmt"

# Constructing the ingestion command
$insertQuery = ".set-or-append WorkspaceOutboundAccessProtection <| print Activity='{2}', BillingType=long(null), ClientIP='', CreationTime=now(), Experience='', Id=guid(null), ObjectDisplayName='', ObjectId='', ObjectType='', Operation='{2}', OrganizationId='', RecordType=long(null), RefreshEnforcementPolicy=long(null), RequestId='', ResultStatus='', UserAgent='', UserId='', UserKey='', UserType=long(null), WorkSpaceName='{0}', Workload='', WorkspaceId=guid('{1}')"

$formattedQuery = $insertQuery -f $escapedWorkspaceName, $WorkspaceId, $AOPSetting

$insertBody = @{
    csl = $formattedQuery
    db  = $databaseName
} | ConvertTo-Json

try {
    #Write-Host "Inserting initial record for WorkspaceId '$WorkspaceId'..."
    $insertResponse = Invoke-RestMethod -Uri $mgmtUri -Method Post -Headers $kqlHeaders -Body $insertBody
    #Write-Host "Record inserted successfully."
}
catch {
    Write-Error "Failed to insert record. Error: $_"
}