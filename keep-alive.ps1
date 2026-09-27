<#
.SYNOPSIS
    Harden an Android phone so the OpenCode server survives in the background.

.DESCRIPTION
    Android (and Samsung especially) kills long-running background processes
    three different ways. This script fixes all three over ADB, which is the
    only way to reach two of them.

      1. phantom process killer - SIGKILLs proot's child processes
      2. battery optimisation   - doze suspends the app
      3. standby bucket         - restricts background work

    Requires: platform-tools (adb) and wireless debugging enabled on the phone
    (Settings -> Developer options -> Wireless debugging).

.EXAMPLE
    .\keep-alive.ps1

.EXAMPLE
    .\keep-alive.ps1 -Serial 100.111.9.102:5555
#>

[CmdletBinding()]
param(
    [string] $Serial = "",
    [string] $Adb    = ""
)

$ErrorActionPreference = "Stop"

function Find-Adb {
    if ($Adb -and (Test-Path $Adb)) { return $Adb }
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ProgramFiles\Android\Sdk\platform-tools\adb.exe",
        "${env:ProgramFiles(x86)}\Android\Sdk\platform-tools\adb.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "adb.exe not found. Install Android platform-tools or pass -Adb <path>."
}

function Adb-Sh {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Args2)
    $full = @()
    if ($Serial) { $full += @("-s", $Serial) }
    $full += @("shell") + $Args2
    return (& $script:adbPath @full 2>&1 | Out-String).Trim()
}

function Step($n, $text) { Write-Host "`n==> $n  $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "    [ok] $text" -ForegroundColor Green }
function Warn($text) { Write-Host "    [!]  $text" -ForegroundColor Yellow }
function Bad($text)  { Write-Host "    [x]  $text" -ForegroundColor Red }

# ---------------------------------------------------------------------------
$script:adbPath = Find-Adb
Write-Host "adb: $script:adbPath" -ForegroundColor DarkGray

Step "0/3" "Finding the phone"
if ($Serial) {
    & $script:adbPath connect $Serial | Out-Null
    Start-Sleep -Seconds 2
}

$devices = & $script:adbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" }
if (-not $devices) {
    Bad "no device connected"
    Write-Host @"

  On the phone, enable:  Settings -> Developer options -> Wireless debugging
  Then run one of:

    .\keep-alive.ps1                                  # if already paired, USB, or mDNS
    .\keep-alive.ps1 -Serial <phone-ip>:<port>        # after: adb pair <ip>:<port>

  Your phone's tailnet address is usually reachable:
    adb connect 100.x.y.z:5555

"@
    exit 1
}
if (-not $Serial) { $Serial = ($devices[0] -split "\s+")[0] }
Ok "using device $Serial"
Ok "model: $(Adb-Sh getprop ro.product.model)"

# ---------------------------------------------------------------------------
Step "1/3" "Phantom process killer (the one that actually kills the server)"
& $script:adbPath -s $Serial shell settings put global settings_enable_monitor_phantom_procs false | Out-Null
$phantom = Adb-Sh settings get global settings_enable_monitor_phantom_procs
if ($phantom -eq "false") {
    Ok "disabled (server children will no longer be SIGKILLed)"
} else {
    Bad "still '$phantom' - needs Developer options / adb with sufficient privilege"
}

# ---------------------------------------------------------------------------
Step "2/3" "Battery optimisation"
$whitelist = Adb-Sh dumpsys deviceidle whitelist
foreach ($pkg in @("com.termux", "com.termux.boot", "com.tailscale.ipn")) {
    if ($whitelist -match [regex]::Escape($pkg)) {
        Ok "$pkg already unrestricted"
    } else {
        & $script:adbPath -s $Serial shell cmd deviceidle whitelist "+$pkg" | Out-Null
        Ok "$pkg added to whitelist"
    }
}

# ---------------------------------------------------------------------------
Step "3/3" "Standby buckets and global battery saver"
foreach ($pkg in @("com.termux", "com.tailscale.ipn")) {
    & $script:adbPath -s $Serial shell am set-standby-bucket $pkg active | Out-Null
    $bucket = Adb-Sh am get-standby-bucket $pkg
    if ($bucket -eq "5") { Ok "$pkg is ACTIVE (bucket 5)" }
    else { Warn "$pkg bucket is $bucket (want 5)" }
}

$saver = Adb-Sh settings get global low_power
if ($saver -eq "0") { Ok "battery saver off" } else { Warn "battery saver is ON" }

$adaptive = Adb-Sh settings get global adaptive_battery_management_enabled
if ($adaptive -eq "0") { Ok "adaptive battery off" } else { Warn "adaptive battery is ON - it may still throttle Termux" }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host " Done. Verify the server survives with:" -ForegroundColor Cyan
Write-Host ""
Write-Host "   1. lock the phone, wait 10 minutes"
Write-Host "   2. in Termux:  bash status.sh"
Write-Host ""
Write-Host " Re-check the setting any time:"
Write-Host "   .\keep-alive.ps1"
Write-Host ("=" * 70) -ForegroundColor Cyan
