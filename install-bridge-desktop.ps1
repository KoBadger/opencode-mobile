<#
.SYNOPSIS
    Run the OpenCode V1<->V2 translation bridge on Windows.

.DESCRIPTION
    Starts v1v2-bridge.mjs so that V1-era clients (such as the OC Remote
    Android app) can talk to an OpenCode V2 server running on this machine.

    Defaults assume the local V2 server is on http://127.0.0.1:4096.

.EXAMPLE
    .\install-bridge-desktop.ps1

.EXAMPLE
    .\install-bridge-desktop.ps1 -Upstream http://127.0.0.1:4096 `
        -UpstreamUsername opencode -UpstreamPassword secret `
        -BridgeUsername opencode     -BridgePassword secret
#>

[CmdletBinding()]
param(
    [int]    $Port             = 4097,
    [string] $Upstream         = "http://127.0.0.1:4096",
    [string] $UpstreamUsername = "opencode",
    [string] $UpstreamPassword = "",
    [string] $BridgeUsername   = "opencode",
    [string] $BridgePassword   = "",
    [string] $Bind             = "0.0.0.0"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bridge    = Join-Path $scriptDir "v1v2-bridge.mjs"

if (-not (Test-Path $bridge)) { throw "v1v2-bridge.mjs not found next to this script." }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "Node.js is not on PATH." }

# Free the port if a previous bridge is still holding it.
$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Port $Port is in use (PID $($existing.OwningProcess)) - stopping it..."
    Stop-Process -Id $existing.OwningProcess -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

$env:PORT                = "$Port"
$env:HOST                = $Bind
$env:UPSTREAM            = $Upstream
$env:UPSTREAM_USERNAME   = $UpstreamUsername
$env:UPSTREAM_PASSWORD   = $UpstreamPassword
$env:BRIDGE_USERNAME     = $BridgeUsername
$env:BRIDGE_PASSWORD     = $BridgePassword

$logDir = "$env:LOCALAPPDATA\Temp\opencode"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Write-Host "Starting bridge on http://${Bind}:${Port}  ->  $Upstream"
Start-Process -FilePath "node" -ArgumentList @("`"$bridge`"") `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$logDir\bridge.log" `
    -RedirectStandardError  "$logDir\bridge.err"

Start-Sleep -Seconds 3

# --- verify ---------------------------------------------------------------
$cred = if ($BridgeUsername -or $BridgePassword) {
    [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${BridgeUsername}:${BridgePassword}"))
} else { $null }

$headers = @{}
if ($cred) { $headers["Authorization"] = "Basic $cred" }

Write-Host ""
Write-Host "--- bridge.log ---"
Get-Content "$logDir\bridge.log" -ErrorAction SilentlyContinue | Select-Object -Last 8

Write-Host ""
Write-Host "--- verification ---"
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/global/health" `
                           -Headers $headers -UseBasicParsing -TimeoutSec 10
    Write-Host "V1 /global/health : $($r.StatusCode) $($r.Content)"
} catch {
    Write-Host "V1 /global/health : FAILED - $($_.Exception.Message)"
    Get-Content "$logDir\bridge.err" -ErrorAction SilentlyContinue | Select-Object -Last 5
}

Write-Host ""
Write-Host "Point V1-era clients (e.g. OC Remote) at:"
Write-Host "    URL      http://<this-machine-ip>:${Port}"
Write-Host "    Username ${BridgeUsername}"
Write-Host "    Password ${BridgePassword}"
