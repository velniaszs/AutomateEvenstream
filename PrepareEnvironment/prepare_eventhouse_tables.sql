.create-merge table WorkspaceOutboundAccessProtection (Activity:string, BillingType:long, ClientIP:string, CreationTime:datetime, Experience:string, Id:guid, ObjectDisplayName:string, ObjectId:string, ObjectType:string, Operation:string, OrganizationId:string, RecordType:long, RefreshEnforcementPolicy:long, RequestId:string, ResultStatus:string, UserAgent:string, UserId:string, UserKey:string, UserType:long, WorkSpaceName:string, Workload:string, WorkspaceId:guid) 

.create-merge table WorkspaceOutboundAccessProtection_Staging (Activity:string, BillingType:long, ClientIP:string, CreationTime:datetime, Experience:string, Id:guid, ObjectDisplayName:string, ObjectId:string, ObjectType:string, Operation:string, OrganizationId:string, RecordType:long, RefreshEnforcementPolicy:long, RequestId:string, ResultStatus:string, UserAgent:string, UserId:string, UserKey:string, UserType:long, WorkSpaceName:string, Workload:string, WorkspaceId:guid) 

.create-merge table AllowedItemKind (ItemKind:string, ModifiedAt:datetime)

.create-merge table MonitoringLastRunTime (LastRunTime:datetime)

.create-merge table AlertLogs (WorkspaceName:string, WorkspaceId:guid, wstime:datetime, data_itemKind:string, data_itemName:string, data_itemId:guid, AlertStatus:string) 

.set-or-replace MonitoringLastRunTime <| 
print LastRunTime = ago(4d)

.append AllowedItemKind <|
datatable(ItemKind:string) [
    "VariableLibrary",
    "KQLDashboard",
    "Eventstream",
    "cosmosdb",
    "azuredb",
    "MirroredAzureDatabricksCatalog",
    "SqlAnalyticsEndpoint",
    "MountedDataFactory"
]
| extend ModifiedAt = now()






# CopytoAlerts
@concat('.append AlertLogs <| 
    let lastRunParam = toscalar(MonitoringLastRunTime | summarize max(LastRunTime));
    let startTimeFilter = iff(isnull(lastRunParam) or lastRunParam > ago(1h), ago(1h), lastRunParam);
    let ak = AllowedItemKind;
    let wl = WorkspaceLogs
    | where [''time''] > startTimeFilter
    | where [''time''] < todatetime("', variables('now'), '")
    | where type == "Microsoft.Fabric.ItemCreateSucceeded"
    | extend IngestionTime = ingestion_time()
    | project WorkspaceName = data_workspaceName, data_workspaceId, wstime = [''time''], data_itemName, data_itemId, data_itemKind, type, IngestionTime;
    let aop =
    WorkspaceOutboundAccessProtection
    | extend IngestionTime = ingestion_time()
    | order by WorkspaceId, CreationTime asc
    | serialize 
    | extend NextCreationTime = next(CreationTime)
    | extend NextActivity = next(Activity)
    | extend NextWorkspaceId = next(WorkspaceId)
    | extend endTime = iff(WorkspaceId == NextWorkspaceId and Activity != NextActivity, NextCreationTime, datetime(2999-01-01))
    | where Activity == ''DisableWorkspaceOutboundAccessProtection''
    | project WorkspaceId, Activity, startTime = CreationTime, endTime, IngestionTime;
    wl
    | join kind = inner 
        aop
        on  $left.data_workspaceId == $right.WorkspaceId
    | join kind = leftanti 
        ak
        on $left.data_itemKind == $right.ItemKind
    | where wstime > startTime and wstime <= endTime
    | project WorkspaceName, WorkspaceId, wstime, data_itemKind, data_itemName, data_itemId
    | extend AlertStatus = ''Initial''
    // 3. Filter out records that already exist in the destination table
    | join kind=leftanti (
        AlertLogs 
    ) on WorkspaceId, data_itemId')



#List alerts workspaces
AlertLogs
| where AlertStatus != 'EmailSent'
| extend ItemDetail = strcat("Name: ", data_itemName, " (", data_itemKind, ")")
| summarize 
    AggregatedItems = strcat_array(make_list(ItemDetail), ", "),
    ItemIds = strcat_array(make_list(data_itemId),", ")
    by WorkspaceName, WorkspaceId


# update status 
@concat('.set-or-replace AlertLogs <| 
let targetWorkspaceId = toguid("', item().WorkspaceId,'");
let targetItemIdsString = "', item().ItemIds,'";
let targetItemIds = split(replace_string(targetItemIdsString, " ", ""), ",");
AlertLogs
| extend AlertStatus = iff(
    WorkspaceId == targetWorkspaceId and data_itemId in (targetItemIds), 
    "EmailSent", 
    AlertStatus
)')

# update monitoring config time 
@concat('.set-or-replace MonitoringLastRunTime <| print LastRunTime = todatetime("', variables('now'), '")')

# set email list 
@join(
    xpath(
        xml(
            json(
                concat(
                    '{"Root": {"Item": ', 
                    string(activity('Web1').output.accessDetails), 
                    '}}'
                )
            )
        ), 
        '/Root/Item[principal/type="User" and workspaceAccessDetails/workspaceRole="Admin"]/principal/userDetails/userPrincipalName/text()'
    ), 
    '; '
)











-------------------------------------------TESTING KQL QUERIES-------------------------------------------------

AlertLogs
| where AlertStatus != 'EmailSent'
| extend ItemDetail = strcat("Name: ", data_itemName, " (", data_itemKind, ")")
| summarize 
    AggregatedItems = strcat_array(make_list(ItemDetail), ", "),
    ItemIds = strcat_array(make_list(data_itemId),", ")
    by WorkspaceName, WorkspaceId

workspace_owner | summarize arg_max(ingestion_time(), *) by workspaceId

// Version 1: Workspaces with Valid Emails (Ready to Send)
let latestWorkspaceEmail = workspace_owner 
    | summarize arg_max(ingestion_time(), *) by workspaceId
    | where isnotempty(trim(" ", PrimaryEmail)) or isnotempty(trim(" ", SecondaryEmail));
AlertLogs
| where AlertStatus != 'EmailSent'
| extend ItemDetail = strcat("Name: ", data_itemName, " (", data_itemKind, ")")
| summarize 
    AggregatedItems = strcat_array(make_list(ItemDetail), ", "),
    ItemIds = strcat_array(make_list(data_itemId),", ")
    by WorkspaceName, WorkspaceId
| join kind=inner (
    latestWorkspaceEmail
) on $left.WorkspaceId == $right.workspaceId


// Version 2: Workspaces Missing Emails (Need Dataverse Lookup)
let latestWorkspaceEmail = workspace_owner | summarize arg_max(ingestion_time(), *) by workspaceId;
AlertLogs
| where AlertStatus != 'EmailSent'
| extend ItemDetail = strcat("Name: ", data_itemName, " (", data_itemKind, ")")
| summarize 
    AggregatedItems = strcat_array(make_list(ItemDetail), ", "),
    ItemIds = strcat_array(make_list(data_itemId),", ")
    by WorkspaceName, WorkspaceId
| join kind=leftouter (
    latestWorkspaceEmail
) on $left.WorkspaceId == $right.workspaceId
| where (isnull(PrimaryEmail) or isempty(trim(" ", PrimaryEmail))) and (isnull(SecondaryEmail) or isempty(trim(" ", SecondaryEmail)))


// Version 3: Update AlertStatus to 'NoEmail' for Missing Emails (Version 2 condition)
.set-or-append AlertLogs <|
    let latestWorkspaceEmail = workspace_owner | summarize arg_max(ingestion_time(), *) by workspaceId;
    AlertLogs
    | where AlertStatus != 'EmailSent' and AlertStatus != 'NoEmail'
    | join kind=leftouter (
        latestWorkspaceEmail
    ) on $left.WorkspaceId == $right.workspaceId
    | where (isnull(PrimaryEmail) or isempty(trim(" ", PrimaryEmail))) and (isnull(SecondaryEmail) or isempty(trim(" ", SecondaryEmail)))
    | project WorkspaceName, WorkspaceId, wstime, data_itemKind, data_itemName, data_itemId, AlertStatus = 'NoEmail'


// Version 4: Find Active Items (Created but not Deleted)
WorkspaceLogs
| where type in ("Microsoft.Fabric.ItemCreateSucceeded", "Microsoft.Fabric.ItemDeleteSucceeded")
| summarize 
    Created = countif(type == "Microsoft.Fabric.ItemCreateSucceeded"),
    Deleted = countif(type == "Microsoft.Fabric.ItemDeleteSucceeded")
    by data_workspaceId, data_itemId, data_itemName, data_itemKind
| where Created > 0 and Deleted == 0

----------------------------------------------------------------------------------

@concat('.append AlertLogs <| 
let lastRunParam = toscalar(MonitoringLastRunTime | summarize max(LastRunTime));
let startTimeFilter = iff(isnull(lastRunParam) or lastRunParam > ago(1h), ago(1h), lastRunParam);
let ak = AllowedItemKind;
let aop = WorkspaceOutboundAccessProtection
| extend ingestionTime = ingestion_time()
| summarize arg_max(ingestionTime, *) by WorkspaceId
| where CreationTime > startTimeFilter
| where CreationTime < todatetime("', variables('now'), '")
| where Activity == "DisableWorkspaceOutboundAccessProtection";
let wl = WorkspaceLogs
| where type in ("Microsoft.Fabric.ItemCreateSucceeded", "Microsoft.Fabric.ItemDeleteSucceeded")
| summarize 
    Created = countif(type == "Microsoft.Fabric.ItemCreateSucceeded"),
    Deleted = countif(type == "Microsoft.Fabric.ItemDeleteSucceeded"),
    wstime = max([''time''])
    by data_workspaceId, data_workspaceName, data_itemId, data_itemName, data_itemKind
| where Created > 0 and Deleted == 0;
wl
| join kind = inner 
    aop
    on  $left.data_workspaceId == $right.WorkspaceId
| join kind = leftanti 
    ak
    on $left.data_itemKind == $right.ItemKind
| join kind=leftanti (
    AlertLogs 
) on WorkspaceId, data_itemId
| project WorkspaceName = data_workspaceName, WorkspaceId, wstime, data_itemKind, data_itemName, data_itemId
| extend AlertStatus = "Initial2"  
')