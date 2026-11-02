<#
Deploy the built channel to a Roku dev server and report the real verdict.

Usage:
    powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -RokuHost 192.168.1.50
    $env:ROKU_HOST = "192.168.1.50"; powershell -File tools\deploy.ps1

The host is never hard-coded: pass -RokuHost or set ROKU_HOST. Credentials
default to the Roku developer defaults (rokudev / 1234) and can be overridden
with -User / -Pass.

Notes:
  - The installer is on PORT 80 with HTTP Digest auth.
  - Port 8060 is the unauthenticated ECP REST API (no /plugin_install).
  - The form field is mysubmit=Install (not "Replace").
  - The verdict is inside the response page's params.messages JSON, NOT in the
    HTTP status (the installer returns 200 on failure too).
#>
param(
    [string]$RokuHost = $env:ROKU_HOST,
    [string]$User = "rokudev",
    [string]$Pass = "1234",
    [string]$ZipPath = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RokuHost)) {
    throw "No Roku host supplied. Pass -RokuHost <ip> or set the ROKU_HOST environment variable."
}

$creds = "${User}:${Pass}"
$zip = $ZipPath
if ([string]::IsNullOrWhiteSpace($zip)) {
    $zip = Join-Path $PSScriptRoot '..\out\roku.zip'
}
if (-not (Test-Path $zip)) {
    $zip = Join-Path $PWD 'out\roku.zip'
}
if (-not (Test-Path $zip)) {
    throw "zip not found: $zip  (run: node tools\compile.js; node tools\package.js)"
}
$zip = (Resolve-Path $zip).Path

function Get-InstallVerdict([string]$html) {
    # params.messages is a JSON array of {text, type} entries.
    $m = [regex]::Match($html, 'params\.messages\s*=\s*(?<json>\[.*?\])\s*;?\s*</script>', 'Singleline')
    if (-not $m.Success) { return @() }
    $json = $m.Groups['json'].Value -replace '&quot;', '"' -replace '&amp;', '&' -replace '\s+', ' '
    try { return @($json | ConvertFrom-Json) } catch { return @() }
}

function Test-InstallSuccess($messages) {
    foreach ($x in $messages) {
        $text = [string]$x.text
        $type = [string]$x.type
        if ($type -eq 'error' -or $text -match '(?i)fail|error|invalid|not found|missing') {
            return $false
        }
    }
    # No explicit error: require positive confirmation when the page gives one.
    foreach ($x in $messages) {
        if ([string]$x.text -match '(?i)success') { return $true }
    }
    return $messages.Count -eq 0
}

Write-Host "Target : $RokuHost"
Write-Host "Package: $zip"
Write-Host "Deleting existing dev channel..."
$deleteCode = curl.exe --silent --digest -u $creds -X POST "http://$RokuHost/plugin_install" -F "mysubmit=Delete" -o NUL -w "%{http_code}"
Start-Sleep -Milliseconds 500

Write-Host "Installing..."
$html = (curl.exe --silent --digest -u $creds -X POST "http://$RokuHost/plugin_install" -F "mysubmit=Install" -F "archive=@$zip") -join ''

$msgs = @(Get-InstallVerdict $html)
if ($msgs.Count -eq 0) {
    Write-Host "  (no params.messages found in response)"
    $t = [regex]::Match($html, '<div[^>]*id="?msg"?[^>]*>([^<]*)').Groups[1].Value
    if ($t) { Write-Host "  fallback text: $t" }
    if ($html -notmatch '(?i)install success') {
        Write-Host "  INSTALL VERDICT: unknown/failed (no success marker in response)"
        exit 1
    }
} else {
    foreach ($x in $msgs) { Write-Host ("  [{0}] {1}" -f $x.type, $x.text) }
}

if (-not (Test-InstallSuccess $msgs)) {
    Write-Host "INSTALL FAILED - not launching."
    exit 1
}

Write-Host "Launching dev channel..."
$launch = (curl.exe --silent -X POST "http://$RokuHost`:8060/launch/dev" -o NUL -w "%{http_code}")
Write-Host "  LAUNCH=$launch"
Start-Sleep -Seconds 3

$active = (curl.exe --silent "http://$RokuHost`:8060/query/active-app") -join ''
$name = [regex]::Match($active, '<name>([^<]*)</name>').Groups[1].Value
$id   = [regex]::Match($active, '<id>([^<]*)</id>').Groups[1].Value
Write-Host "  active-app: name='$name' id='$id'"

if ($id -ne 'dev') {
    Write-Host "LAUNCH VERIFY FAILED: active app is not the dev channel."
    exit 1
}

Write-Host "OK: installed and launched the dev channel."
