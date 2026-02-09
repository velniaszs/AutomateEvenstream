[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AuthToken ='eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IlBjWDk4R1g0MjBUMVg2c0JEa3poUW1xZ3dNVSIsImtpZCI6IlBjWDk4R1g0MjBUMVg2c0JEa3poUW1xZ3dNVSJ9.eyJhdWQiOiJodHRwczovL2FwaS5mYWJyaWMubWljcm9zb2Z0LmNvbSIsImlzcyI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzllOTI5NzkwLTI3MmQtNDk3Ny1hMmFiLTMwMTQ0M2MxMWVjZS8iLCJpYXQiOjE3Njk2OTAzMDQsIm5iZiI6MTc2OTY5MDMwNCwiZXhwIjoxNzY5Njk0MjA0LCJhaW8iOiJrMlpnWURqOWM1bDdic0NhaTBsYk00NXVtdUZnQmdBPSIsImFwcGlkIjoiYjVjMDRjOWMtMDU4OC00MThmLThmNjAtMmQ4M2QzOGNiNjM1IiwiYXBwaWRhY3IiOiIxIiwiaWRwIjoiaHR0cHM6Ly9zdHMud2luZG93cy5uZXQvOWU5Mjk3OTAtMjcyZC00OTc3LWEyYWItMzAxNDQzYzExZWNlLyIsImlkdHlwIjoiYXBwIiwib2lkIjoiYzdhYmI4MGEtMGYzZS00YmIyLWEwN2EtZWNiYTA5MGIxYmQyIiwicmgiOiIxLkFXRUJrSmVTbmkwbmQwbWlxekFVUThFZXpna0FBQUFBQUFBQXdBQUFBQUFBQUFES0FRQmhBUS4iLCJzdWIiOiJjN2FiYjgwYS0wZjNlLTRiYjItYTA3YS1lY2JhMDkwYjFiZDIiLCJ0aWQiOiI5ZTkyOTc5MC0yNzJkLTQ5NzctYTJhYi0zMDE0NDNjMTFlY2UiLCJ1dGkiOiJMNEwxWU9hODEwaTBSUG93cXFva0FBIiwidmVyIjoiMS4wIiwieG1zX2FjdF9mY3QiOiIzIDkiLCJ4bXNfZnRkIjoiRFVvUGNiMWVBbUtwcl8tRWFyVnhsUmZKNHlXcDZHdTI1SEVNOVR0cGRSc0JkWE56YjNWMGFDMWtjMjF6IiwieG1zX2lkcmVsIjoiNyAyMiIsInhtc19yZCI6IjAuNDJMallCSmllc2drSk1MQkxpVHd3Y2s3el96SER2ZS1DRS1KNnpjc2hJQ2luRUlDa1hsTkNfYnJuWE5vMDVsdzFjUER1QndveWlFa3dNa0FBUWVnTkZDVVcwamdfNk90SzU1cjdOb2NOX1BxMFhBejNaOEEiLCJ4bXNfc3ViX2ZjdCI6IjMgOSJ9.WzZ9yohm6kXSnTO2cuh6xzzS3ZB529dpBW32EIHZCi9bJkl5tfcD15k5ZtKv9Dq_Mmjb1oPKPJyqrsmu3useCyVIo_5dhYqyrJjOkyR3RUqfvcfG9imbzzHzxBlqPcD5bwYAJX2iR1uA5_bOudfMSUG5jAwA3IMRsG0X8eSXXtvenkL_6gQqeQYuiUeRB7KmJevMDGD6Wt7lPuPeeovjl4DyidA69WEFI4HfPrzF4S_ZKNVdB3tf1zLzawb7tqccoTYQ-EnyHe6kKXvEbl5hz1x2bZd3F0g7JlCGR6AeYphG7cIv1QDY53lOlmHBD5Z9H7tSg62PBYTX7p94xAf93g',

    [Parameter(Mandatory = $false)]
    [string]$StartDateTime ="'2026-01-23T11:55:00.000Z'",

    [Parameter(Mandatory = $false)]
    [string]$EndDateTime ="'2026-01-23T13:55:00.000Z'"
)

$ErrorActionPreference = "Stop"


$headers = @{
    "Authorization" = "Bearer $AuthToken"
    "Content-Type"  = "application/json"
}



$url = "https://api.powerbi.com/v1.0/myorg/admin/activityevents?startDateTime=$StartDateTime&endDateTime=$EndDateTime"
Write-Host $url

try {
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
    Write-Host $response
}
catch {
    Write-Error $_
}
