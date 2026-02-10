.create-merge table WorkspaceOutboundAccessProtection (Activity:string, BillingType:long, ClientIP:string, CreationTime:datetime, Experience:string, Id:guid, ObjectDisplayName:string, ObjectId:string, ObjectType:string, Operation:string, OrganizationId:string, RecordType:long, RefreshEnforcementPolicy:long, RequestId:string, ResultStatus:string, UserAgent:string, UserId:string, UserKey:string, UserType:long, WorkSpaceName:string, Workload:string, WorkspaceId:guid) 

.create-merge table WorkspaceOutboundAccessProtection_Staging (Activity:string, BillingType:long, ClientIP:string, CreationTime:datetime, Experience:string, Id:guid, ObjectDisplayName:string, ObjectId:string, ObjectType:string, Operation:string, OrganizationId:string, RecordType:long, RefreshEnforcementPolicy:long, RequestId:string, ResultStatus:string, UserAgent:string, UserId:string, UserKey:string, UserType:long, WorkSpaceName:string, Workload:string, WorkspaceId:guid) 

.create-merge table AllowedItemKind (ItemKind:string, ModifiedAt:datetime)

.create-merge table MonitoringLastRunTime (LastRunTime:datetime)

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


//add missing data
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
    Activity = "DisableWorkspaceOutboundAccessProtection",
    BillingType = 0,
    ClientIP = "1.1.1.1", 
    CreationTime = datetime(2026-01-01),
    Experience = "",
    Id = new_guid(),
    ObjectDisplayName = "",
    ObjectId = "00000000-0000-0000-0000-000000000000",
    ObjectType = "",
    Operation = "DisableWorkspaceOutboundAccessProtection",
    OrganizationId = "9e929790-272d-4977-a2ab-301443c11ece", 
    RecordType = 20,
    RefreshEnforcementPolicy = 0,
    RequestId = tostring(new_guid()),
    ResultStatus = "Succeeded",
    UserAgent = "initial entry",
    UserId = "initial entry",
    UserKey = "initial entry", 
    UserType = 0,
    Workload = "PowerBI"
| project Activity, BillingType, ClientIP, CreationTime, Experience, Id, ObjectDisplayName, ObjectId, ObjectType, Operation, OrganizationId, RecordType, RefreshEnforcementPolicy, RequestId, ResultStatus, UserAgent, UserId, UserKey, UserType, WorkSpaceName, Workload, WorkspaceId


WorkspaceOutboundAccessProtection