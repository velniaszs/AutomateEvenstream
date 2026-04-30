$token = & .\authenticate\get-kql-token.ps1 -tenantId '9e929790-272d-4977-a2ab-301443c11ece' -clientId 'b5c04c9c-0588-418f-8f60-2d83d38cb635' -client_secret ''
$common = @{
    QueryUri     = 'https://trd-6uegjpfbf030eemxtw.z1.kusto.fabric.microsoft.com'
    DatabaseName = 'MonitoringEventhouse'
    KqlAuthToken = $token
}

# 1. Baseline (current data, no backfill yet)
 #.\Testing\StressTest\Run-Benchmarks.ps1 @common -RunLabel 'baseline'

# 2. Backfill 2 years
# .\Testing\StressTest\Run-StressTestBackfill.ps1 @common

# 3. Post-load benchmark
#.\Testing\StressTest\Run-Benchmarks.ps1 @common -RunLabel 'postload' -Iterations 2 -WarmupIterations 1

# # 4. Streaming load test (separate terminal, runs 1h soak)
# .\Testing\StressTest\Run-StreamingLoad.ps1 @common -LoadProfile steady -RatePerSecond 100 -DurationMinutes 60

# # 5. While streaming runs, in another terminal, take an under-stream measurement
 .\Testing\StressTest\Run-Benchmarks.ps1 @common -RunLabel 'understream-100' -Iterations 2 -WarmupIterations 1