<#
.SYNOPSIS
    Pack this desktop's OpenCode config and serve it to the phone.

.DESCRIPTION
    Collects the desktop's OpenCode configuration into a single tar.gz, then
    serves it over HTTP on the Tailscale IP so the phone can pull it with
    sync-from-desktop.sh.

    Included:
      - auth.json          provider credentials (the "logins")
      - opencode.json      providers, models, MCP servers, plugins
      - agents/*.md        custom agent definitions

    Excluded: backups (*.bak*, *.v1bak), service.json, and anything the phone
    already generates itself.

    Credentials are written ONLY into the tar served to the phone. Nothing is
    copied into the git repo.

.EXAMPLE
    .\serve-config.ps1

.EXAMPLE
    .\serve-config.ps1 -Port 8899 -NoServe
#>

[CmdletBinding()]
param(
    [string] $ConfigDir = "$env:USERPROFILE\.config\opencode",
    [string] $DataDir   = "$env:USERPROFILE\.local\share\opencode",
    [string] $Bind      = "",
    [int]    $Port      = 8899,
    [switch] $NoServe
)

$ErrorActionPreference = "Stop"

function Ok($t)   { Write-Host "    [ok] $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    [!]  $t" -ForegroundColor Yellow }
function Step($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }

$staging = Join-Path $env:TEMP ("oc-sync-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$outDir  = Join-Path $env:TEMP "opencode\phone-transfer"
$archive = Join-Path $outDir "opencode-config-sync.tar.gz"

New-Item -ItemType Directory -Force -Path $staging, $outDir | Out-Null

try {
    # ---------------------------------------------------------------- layout
    # Mirror the real layout inside the container:
    #   .config/opencode/{opencode.json,agents/}
    #   .local/share/opencode/auth.json
    Step "1/4  Collecting config"
    $cfgStage  = Join-Path $staging ".config\opencode"
    $dataStage = Join-Path $staging ".local\share\opencode"
    New-Item -ItemType Directory -Force -Path $cfgStage, $dataStage | Out-Null

    $opencodeJson = Join-Path $ConfigDir "opencode.json"
    if (Test-Path $opencodeJson) {
        Copy-Item $opencodeJson (Join-Path $cfgStage "opencode.json") -Force
        Ok "opencode.json ($([math]::Round((Get-Item $opencodeJson).Length/1KB,1)) KB)"
    } else {
        Warn "opencode.json not found in $ConfigDir"
    }

    $authJson = Join-Path $DataDir "auth.json"
    if (Test-Path $authJson) {
        Copy-Item $authJson (Join-Path $dataStage "auth.json") -Force
        $keys = (Get-Content $authJson -Raw | ConvertFrom-Json).PSObject.Properties.Name
        Ok "auth.json - $($keys.Count) providers: $($keys -join ', ')"
    } else {
        Warn "auth.json not found in $DataDir"
    }

    $agentsDir = Join-Path $ConfigDir "agents"
    if (Test-Path $agentsDir) {
        $destAgents = Join-Path $cfgStage "agents"
        New-Item -ItemType Directory -Force -Path $destAgents | Out-Null
        $n = 0
        Get-ChildItem $agentsDir -Filter *.md | ForEach-Object {
            Copy-Item $_.FullName (Join-Path $destAgents $_.Name) -Force
            $n++
        }
        Ok "$n agent definitions"
    } else {
        Warn "no agents directory"
    }

    # ---------------------------------------------------------------- pack
    Step "2/4  Packing"
    if (Test-Path $archive) { Remove-Item $archive -Force }
    # tar ships with Windows (bsdtar) and writes tar.gz natively.
    & tar -czf $archive -C $staging .
    if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }
    Ok "$archive ($([math]::Round((Get-Item $archive).Length/1KB,1)) KB)"

    # Show what is inside so nothing surprising ships.
    Step "3/4  Archive contents"
    & tar -tzf $archive | ForEach-Object { Write-Host "    $_" }

    if ($NoServe) {
        Step "4/4  Skipping server (-NoServe)"
        Write-Host "    Serve it yourself from: $outDir"
        return
    }

    # ---------------------------------------------------------------- serve
    Step "4/4  Starting the transfer server"

    if (-not $Bind) {
        # Prefer the Tailscale address so the phone can reach it.
        $ts = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -like "100.*" } |
              Select-Object -First 1
        $Bind = if ($ts) { $ts.IPAddress } else { "0.0.0.0" }
    }

    $existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-Process -Id $existing.OwningProcess -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    $server = Join-Path $env:TEMP "opencode\serve-transfer.js"
    if (-not (Test-Path $server)) { throw "serve-transfer.js not found at $server" }

    Start-Process node -ArgumentList @("`"$server`"") -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $env:TEMP "opencode\transfer.log") `
        -RedirectStandardError  (Join-Path $env:TEMP "opencode\transfer.err")
    Start-Sleep -Seconds 3

    try {
        $r = Invoke-WebRequest -Uri "http://${Bind}:${Port}/opencode-config-sync.tar.gz" `
                               -UseBasicParsing -TimeoutSec 10
        Ok "serving at http://${Bind}:${Port}"
        Ok "archive reachable ($($r.Content.Length) bytes)"
    } catch {
        Warn "could not verify over ${Bind}: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host " On the PHONE (Termux), run:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   curl -fsSL http://${Bind}:${Port}/sync-from-desktop.sh -o ~/sync-from-desktop.sh"
    Write-Host "   bash ~/sync-from-desktop.sh"
    Write-Host ""
    Write-Host " (or DESKTOP_IP=${Bind} if sync-from-desktop.sh is already on the phone)"
    Write-Host ("=" * 70) -ForegroundColor Cyan
}
finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}
