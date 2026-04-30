$token = & .\authenticate\get-kql-token.ps1 -tenantId '9e929790-272d-4977-a2ab-301443c11ece' -clientId 'b5c04c9c-0588-418f-8f60-2d83d38cb635' -client_secret ''
$common = @{
    QueryUri     = 'https://trd-6uegjpfbf030eemxtw.z1.kusto.fabric.microsoft.com'
    DatabaseName = 'MonitoringEventhouse'
    KqlAuthToken = $token
}

# Snapshot before stress test (auto-generated suffix)
#.\Testing\StressTest\Backup-EventhouseTables.ps1 @common -Mode Backup
# -> prints e.g. "Backup suffix: 20260428_140512"

# See available snapshots
#.\Testing\StressTest\Backup-EventhouseTables.ps1 @common -Mode List

# Restore (requires typing YES at prompt)
.\Testing\StressTest\Backup-EventhouseTables.ps1 @common -Mode Restore -Suffix '20260428_094821'

# # Cleanup when no longer needed
# .\Testing\StressTest\Backup-EventhouseTables.ps1 @common -Mode Drop -Suffix '20260428_094821'