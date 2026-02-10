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
| order by WorkspaceId, wstime







