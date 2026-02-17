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