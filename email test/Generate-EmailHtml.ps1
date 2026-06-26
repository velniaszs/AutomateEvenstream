<#
.SYNOPSIS
    Renders a Fabric pipeline "Send email" @concat(...) expression into a
    viewable HTML file by substituting sample values for the dynamic variables.

.DESCRIPTION
    The Fabric expression builder stores the email body as:
        @concat('literal', item().Variable, utcNow('yyyy'), ...)
    A browser cannot render that. This script strips the @concat wrapper,
    replaces the dynamic tokens with sample data, joins the string literals,
    and writes a standalone .html file you can open in a browser.

.PARAMETER InputPath
    Path to the file containing the @concat(...) expression.

.PARAMETER OutputPath
    Path of the .html file to generate.

.PARAMETER OpenInBrowser
    If set, opens the generated HTML in the default browser.

.EXAMPLE
    .\Generate-EmailHtml.ps1 -OpenInBrowser
#>
[CmdletBinding()]
param(
    [string]$InputPath  = ".\email_body.backup.txt",
    [string]$OutputPath = ".\email_preview.html",
    [switch]$OpenInBrowser
)

$ErrorActionPreference = 'Stop'

# Resolve paths relative to this script's folder so it works from anywhere.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not [System.IO.Path]::IsPathRooted($InputPath))  { $InputPath  = Join-Path $scriptDir $InputPath }
if (-not [System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $scriptDir $OutputPath }

if (-not (Test-Path $InputPath)) {
    throw "Input file not found: $InputPath"
}

# ---- Sample values for the dynamic tokens -----------------------------------
# Edit these to preview different scenarios. The HtmlRows value mimics what your
# ForEach loop builds (one <tr> per detected artifact).
$sampleWorkspaceId = '11111111-aaaa-bbbb-cccc-222222222222'
$sampleYear        = (Get-Date).ToString('yyyy')
$sampleHtmlRows    = @"
<tr>
  <td style="padding:8px;">$sampleWorkspaceId</td>
  <td style="padding:8px;">33333333-dddd-eeee-ffff-444444444444</td>
  <td style="padding:8px;">Lakehouse</td>
  <td style="padding:8px;">john.doe@ubs.com</td>
  <td style="padding:8px;">2026-06-25T08:14:00Z</td>
</tr>
<tr>
  <td style="padding:8px;">$sampleWorkspaceId</td>
  <td style="padding:8px;">55555555-6666-7777-8888-999999999999</td>
  <td style="padding:8px;">Notebook</td>
  <td style="padding:8px;">jane.smith@ubs.com</td>
  <td style="padding:8px;">2026-06-25T09:02:00Z</td>
</tr>
"@

# ---- Read expression --------------------------------------------------------
$expr = Get-Content -Path $InputPath -Raw

# ---- Replace dynamic tokens with quoted sample literals ---------------------
# Order matters: replace utcNow(...) (contains quotes) before generic cleanup.
$expr = [regex]::Replace($expr, "utcNow\(\s*'[^']*'\s*\)", "'$sampleYear'")
$expr = $expr -replace [regex]::Escape("item().WorkspaceId"), "'$sampleWorkspaceId'"
# HtmlRows is multi-line HTML; inject as a single quoted literal.
$expr = $expr -replace [regex]::Escape("item().HtmlRows"), ("'" + ($sampleHtmlRows -replace "'", "''") + "'")

# ---- Strip the @concat( ... ) wrapper ---------------------------------------
$expr = $expr.Trim()
$expr = [regex]::Replace($expr, '^\s*@concat\s*\(', '')
$expr = [regex]::Replace($expr, '\)\s*$', '')

# ---- Extract every single-quoted literal and join it ------------------------
# Handles escaped '' inside literals.
$literals = [regex]::Matches($expr, "'((?:[^']|'')*)'")
$body = -join ($literals | ForEach-Object { $_.Groups[1].Value -replace "''", "'" })

# ---- Wrap in a minimal HTML document ----------------------------------------
$html = @"
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Email preview</title></head>
<body>
$body
</body>
</html>
"@

Set-Content -Path $OutputPath -Value $html -Encoding UTF8
Write-Host "Generated: $OutputPath" -ForegroundColor Green

if ($OpenInBrowser) {
    Start-Process $OutputPath
}
