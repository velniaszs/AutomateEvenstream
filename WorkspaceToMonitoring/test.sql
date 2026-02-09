let wl = WorkspaceLogs
| where ['time'] > ago(3h)
| where type == "Microsoft.Fabric.ItemCreateSucceeded"
| extend IngestionTime = ingestion_time()
| project data_workspaceName, data_workspaceId, wstime = ['time'], data_itemName, data_itemId, data_itemKind, type, IngestionTime;
let aop =
WorkspaceOutboundAccessProtection
| extend IngestionTime = ingestion_time()
//| where IngestionTime > ago(530h)
| order by WorkspaceId, CreationTime asc
| serialize 
| extend NextCreationTime = next(CreationTime)
| extend NextActivity = next(Activity)
| extend NextWorkspaceId = next(WorkspaceId)
| extend endTime = iff(WorkspaceId == NextWorkspaceId and Activity != NextActivity, NextCreationTime, datetime(2999-01-01))
| where Activity == 'DisableWorkspaceOutboundAccessProtection'
| project WorkspaceId , WorkSpaceName, Activity, startTime = CreationTime, endTime, IngestionTime;
wl
| join kind = inner
    aop
    on  $left.data_workspaceId == $right.WorkspaceId
| where wstime > startTime and wstime <= endTime
| order by wstime, startTime




WorkspaceLogs
//| where wstime > ago(530h)
//| where data_workspaceName in ('ab_test5','ab_test2')
| extend IngestionTime = ingestion_time()
//| project data_workspaceName, data_workspaceId, wstime = ['time'], data_itemName, data_itemId, data_itemKind, type, IngestionTime
| sort by IngestionTime desc


WorkspaceOutboundAccessProtection
| extend IngestionTime = ingestion_time()
//| where IngestionTime > ago(530h)
| order by WorkspaceId, CreationTime asc
| serialize 
| extend NextCreationTime = next(CreationTime)
| extend NextActivity = next(Activity)
| extend NextWorkspaceId = next(WorkspaceId)
| extend endTime = iff(WorkspaceId == NextWorkspaceId and Activity != NextActivity, NextCreationTime, datetime(2999-01-01))
| project WorkspaceId , WorkSpaceName, Activity, startTime = CreationTime, endTime, IngestionTime;


WorkspaceOutboundAccessProtection
| extend IngestionTime = ingestion_time()
//| where IngestionTime > ago(530h)
| order by WorkspaceId, CreationTime asc
| serialize 
| extend NextCreationTime = next(CreationTime)
| extend NextActivity = next(Activity)
| extend NextWorkspaceId = next(WorkspaceId)
| extend endTime = iff(WorkspaceId == NextWorkspaceId and Activity != NextActivity, NextCreationTime, datetime(2999-01-01))
| where Activity == 'DisableWorkspaceOutboundAccessProtection'
| project WorkspaceId , WorkSpaceName, Activity, startTime = CreationTime, endTime, IngestionTime;









#.create-merge table WorkspaceOutboundAccessProtection (Activity:string, BillingType:long, ClientIP:string, CreationTime:datetime, Experience:string, Id:guid, ObjectDisplayName:string, ObjectId:string, ObjectType:string, Operation:string, OrganizationId:string, RecordType:long, RefreshEnforcementPolicy:long, RequestId:string, ResultStatus:string, UserAgent:string, UserId:string, UserKey:string, UserType:long, WorkSpaceName:string, Workload:string, WorkspaceId:guid) 

#.create-merge table WorkspaceOutboundAccessProtection_Staging (Activity:string, BillingType:long, ClientIP:string, CreationTime:datetime, Experience:string, Id:guid, ObjectDisplayName:string, ObjectId:string, ObjectType:string, Operation:string, OrganizationId:string, RecordType:long, RefreshEnforcementPolicy:long, RequestId:string, ResultStatus:string, UserAgent:string, UserId:string, UserKey:string, UserType:long, WorkSpaceName:string, Workload:string, WorkspaceId:guid) 

#.create-merge table AllowedItemKind (ItemKind:string, ModifiedAt:datetime)

.append AllowedItemKind <|
datatable(ItemKind:string) [
    "VariableLibrary",
    "KQLDashboard",
    "Eventstream",
    "cosmosdb",
    "azuredb",
    "MirroredAzureDatabricksCatalog",
    "MountedDataFactory"
]
| extend ModifiedAt = now()

#.create-merge table MonitoringLastRunTime (LastRunTime:datetime)

.set-or-replace MonitoringLastRunTime <|
print LastRunTime = ago(1h)














.set-or-replace WorkspaceOutboundAccessProtection <|
let MinCreation = 
    WorkspaceOutboundAccessProtection
    | summarize MinTime = min(CreationTime) by WorkspaceId;
WorkspaceOutboundAccessProtection
| join kind=leftouter MinCreation on WorkspaceId
| extend CreationTime = iff(CreationTime == MinTime, datetime(2026-01-01), CreationTime)
| project-away MinTime, WorkspaceId1


.append WorkspaceOutboundAccessProtection <|
WorkspaceLogs
| where isnotempty(data_workspaceId)
| summarize arg_max(['time'], data_workspaceName) by data_workspaceId
| project WorkspaceId = data_workspaceId, WorkSpaceName = data_workspaceName
| join kind=leftanti (
    WorkspaceOutboundAccessProtection
    | distinct WorkspaceId
) on WorkspaceId
| extend 
    Activity = "EnableWorkspaceOutboundAccessProtection",
    BillingType = 0,
    ClientIP = "178.196.195.120", // From example
    CreationTime = datetime(2026-01-01),
    Experience = "",
    Id = new_guid(),
    ObjectDisplayName = "",
    ObjectId = "00000000-0000-0000-0000-000000000000",
    ObjectType = "",
    Operation = "EnableWorkspaceOutboundAccessProtection",
    OrganizationId = "9e929790-272d-4977-a2ab-301443c11ece", // From example
    RecordType = 20,
    RefreshEnforcementPolicy = 0,
    RequestId = tostring(new_guid()),
    ResultStatus = "Succeeded",
    UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0",
    UserId = "admin@MngEnvMCAP985281.onmicrosoft.com",
    UserKey = "1003200475F94C5D", // From example
    UserType = 0,
    Workload = "PowerBI"
// Verify column order matches target table schema if necessary, though Kusto usually matches by name.
| project Activity, BillingType, ClientIP, CreationTime, Experience, Id, ObjectDisplayName, ObjectId, ObjectType, Operation, OrganizationId, RecordType, RefreshEnforcementPolicy, RequestId, ResultStatus, UserAgent, UserId, UserKey, UserType, WorkSpaceName, Workload, WorkspaceId





//last query
let lastRunParam = toscalar(MonitoringLastRunTime | summarize max(LastRunTime));
// If last run was less than 1h ago (timestamp > ago(1h)), use ago(1h). Otherwise use the stored timestamp.
let startTimeFilter = iff(isnull(lastRunParam) or lastRunParam > ago(1h), ago(1h), lastRunParam);
let ak = AllowedItemKind;
let wl = WorkspaceLogs
| where ['time'] > startTimeFilter
| where type == "Microsoft.Fabric.ItemCreateSucceeded"
| extend IngestionTime = ingestion_time()
| project WorkspaceName = data_workspaceName, data_workspaceId, wstime = ['time'], data_itemName, data_itemId, data_itemKind, type, IngestionTime;
let aop =
WorkspaceOutboundAccessProtection
| extend IngestionTime = ingestion_time()
| order by WorkspaceId, CreationTime asc
| serialize 
| extend NextCreationTime = next(CreationTime)
| extend NextActivity = next(Activity)
| extend NextWorkspaceId = next(WorkspaceId)
| extend endTime = iff(WorkspaceId == NextWorkspaceId and Activity != NextActivity, NextCreationTime, datetime(2999-01-01))
| where Activity == 'DisableWorkspaceOutboundAccessProtection'
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
| order by wstime

// Update the configuration with the current time after effective run
.set-or-replace MonitoringLastRunTime <| 
print LastRunTime = ago(3d)

// Clear table
// .clear table MonitoringLastRunTime data