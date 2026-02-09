[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AuthToken ='eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IlBjWDk4R1g0MjBUMVg2c0JEa3poUW1xZ3dNVSIsImtpZCI6IlBjWDk4R1g0MjBUMVg2c0JEa3poUW1xZ3dNVSJ9.eyJhdWQiOiJodHRwczovL2FwaS5mYWJyaWMubWljcm9zb2Z0LmNvbSIsImlzcyI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzllOTI5NzkwLTI3MmQtNDk3Ny1hMmFiLTMwMTQ0M2MxMWVjZS8iLCJpYXQiOjE3NzAwMTQ3NjksIm5iZiI6MTc3MDAxNDc2OSwiZXhwIjoxNzcwMDE4NjY5LCJhaW8iOiJrMlpnWU9nM3EvdkV2dnlrZU1ZeTY3S0xGM3ZGQUE9PSIsImFwcGlkIjoiYjVjMDRjOWMtMDU4OC00MThmLThmNjAtMmQ4M2QzOGNiNjM1IiwiYXBwaWRhY3IiOiIxIiwiaWRwIjoiaHR0cHM6Ly9zdHMud2luZG93cy5uZXQvOWU5Mjk3OTAtMjcyZC00OTc3LWEyYWItMzAxNDQzYzExZWNlLyIsImlkdHlwIjoiYXBwIiwib2lkIjoiYzdhYmI4MGEtMGYzZS00YmIyLWEwN2EtZWNiYTA5MGIxYmQyIiwicmgiOiIxLkFXRUJrSmVTbmkwbmQwbWlxekFVUThFZXpna0FBQUFBQUFBQXdBQUFBQUFBQUFBQUFBQmhBUS4iLCJzdWIiOiJjN2FiYjgwYS0wZjNlLTRiYjItYTA3YS1lY2JhMDkwYjFiZDIiLCJ0aWQiOiI5ZTkyOTc5MC0yNzJkLTQ5NzctYTJhYi0zMDE0NDNjMTFlY2UiLCJ1dGkiOiJuTnNoVmJtM1JFR0FLclNZYW5pRkFBIiwidmVyIjoiMS4wIiwieG1zX2FjdF9mY3QiOiIzIDkiLCJ4bXNfZnRkIjoiMUZ5QjY3czBBUmxybXdCVy1sVXliQVhSc3lleHA4cmNjMWZ5QjlKc1FZSUJkWE51YjNKMGFDMWtjMjF6IiwieG1zX2lkcmVsIjoiNyAxNiIsInhtc19yZCI6IjAuNDJMallCSmllc2drSk1MQkxpVHd3Y2s3el96SER2ZS1DRS1KNnpjc2hJQ2luRUlDa1hsTkNfYnJuWE5vMDVsdzFjUER1QndveWlFa3dNa0FBUWVnTkZDVVcwamc2OFZ6Vi1WaWI5eXlQT0d6TEZ2YjV5RUEiLCJ4bXNfc3ViX2ZjdCI6IjMgOSJ9.W-YMKJL0fHxfbwRlH2VAmyksLKBdrzcilwJa7A1Pxkp1h-Gz4qDCsfFLhhg0ZnDItX5D2y2NFXkEP5mDLcRXiE9oJ4VVN_jCQSPJ5tsRN93223d709oPwUHteN0MvLT3V0qWcjtzffayzOKfJ0AdYMhCJtitFK50rQECg8UrW31IKjSkTrmVjgXNTnqa72hwsdvkBl2uKmoSVpWmKZyUJXAALQoW7GopjuGCt8rryfh_7047HpZx74z5J_wNCzNF_jPWcRyr0fIAJF1q4XrZsSQksG-2skAwythBLoZFgGKDHJeM2HJdPrEehCqiYevFNpqhOnF3E_BnPgcGIRzXQ',

    [Parameter(Mandatory = $false)]
    [string]$StartDateTime ="'2026-01-26T22:00:00.000Z'",

    [Parameter(Mandatory = $false)]
    [string]$EndDateTime ="'2026-01-26T23:59:59.999Z'"
)

$ErrorActionPreference = "Stop"

# Get existing Eventstreams in the workspace
$filter2 = "Activity eq 'EnableWorkspaceOutboundAccessProtection'"
$filter = "Activity eq 'DisableWorkspaceOutboundAccessProtection'"
$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}

$filters = @($filter, $filter2)
$allActivityEvents = @()

foreach ($f in $filters) {
    # Skip if filter is empty
    if ([string]::IsNullOrWhiteSpace($f)) { continue }
    #
    $url = "https://api.powerbi.com/v1.0/myorg/admin/activityevents?startDateTime=$StartDateTime&endDateTime=$EndDateTime&`$filter=$f"
    Write-Host $url
    try {
        do {
            #Write-Host "Fetching URL: $url"
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
            
            if ($response.activityEventEntities) {
                $allActivityEvents += $response.activityEventEntities
            } elseif ($response.value) {
                $allActivityEvents += $response.value
            }
            
            if ($response.continuationUri) {
                $url = $response.continuationUri
            } else {
                $url = $null
            }

        } while ($null -ne $url)
    }
    catch {
        Write-Warning "Error processing filter '$f': $_"
    }
}

$allActivityEvents | ConvertTo-Json -Depth 10