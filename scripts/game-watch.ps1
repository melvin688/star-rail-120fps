<#
    game-watch.ps1 - "start the FPS overlay automatically when the game starts".

    Runs invisibly in the background (started by GAME-WATCH.vbs, which the GUI
    registers in your Startup folder when you turn the option on). Every few
    seconds it checks for the game process; the first time the game appears it
    launches the FPS overlay, which closes itself again when the game exits.

    It does NOT touch the registry, does NOT write to the game, and never needs
    administrator rights itself - the overlay's own launcher asks for the
    elevation prompt when it starts.

    Stopping it:
        game-watch.ps1 -Stop        (or turn the option off in the GUI)

    Distributed under the MIT License. See the LICENSE file in the repository root.
#>
param(
    [switch]$Stop,
    [string]$ProcessName = 'StarRail',
    [int]$IntervalSeconds = 3
)

$ErrorActionPreference = 'Stop'

$stateDir = Join-Path $env:LOCALAPPDATA 'star-rail-120fps'
$pidFile  = Join-Path $stateDir 'agent.pid'
$logFile  = Join-Path $stateDir 'agent.log'
$root     = Split-Path -Parent $PSScriptRoot
$monBat   = Join-Path $root 'FPS-MONITOR.bat'

if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

function Write-Log([string]$msg) {
    try {
        $line = ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $msg)
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
        # keep the log small: trim to the last 200 lines
        $all = @(Get-Content -LiteralPath $logFile -Encoding UTF8 -ErrorAction SilentlyContinue)
        if ($all.Count -gt 200) {
            $all[-200..-1] | Set-Content -LiteralPath $logFile -Encoding UTF8
        }
    } catch { }
}

function Get-AgentPid {
    if (-not (Test-Path -LiteralPath $pidFile)) { return 0 }
    $raw = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue)
    $n = 0
    if ([int]::TryParse(($raw -as [string]).Trim(), [ref]$n)) { return $n }
    return 0
}

# --- -Stop -----------------------------------------------------------------
if ($Stop) {
    $existing = Get-AgentPid
    if ($existing -gt 0) {
        $p = Get-Process -Id $existing -ErrorAction SilentlyContinue
        if ($p) {
            try { Stop-Process -Id $existing -Force -ErrorAction Stop; Write-Log "stopped by request (pid $existing)" } catch { }
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Host 'game-watch stopped.'
    exit 0
}

# --- single instance -------------------------------------------------------
$existing = Get-AgentPid
if ($existing -gt 0 -and $existing -ne $PID) {
    if (Get-Process -Id $existing -ErrorAction SilentlyContinue) {
        exit 0        # already running; nothing to do
    }
}
Set-Content -LiteralPath $pidFile -Value $PID -Encoding Ascii

if (-not (Test-Path -LiteralPath $monBat)) {
    Write-Log "FPS-MONITOR.bat missing at $monBat - exiting"
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    exit 1
}

function Test-OverlayRunning {
    # The overlay runs as an elevated powershell.exe; its command line carries
    # the script name. If we cannot read command lines, fall back to "assume it
    # is not running" so a single overlay still gets launched.
    try {
        $procs = Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop
        foreach ($p in $procs) {
            if ($p.CommandLine -and $p.CommandLine -like '*fps-monitor.ps1*') { return $true }
        }
        return $false
    } catch {
        return $false
    }
}

Write-Log "agent started (pid $PID, watching $ProcessName, every ${IntervalSeconds}s)"

$launched = $false
try {
    while ($true) {
        $game = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

        if ($game) {
            if (-not $launched) {
                if (-not (Test-OverlayRunning)) {
                    Write-Log "game detected - launching FPS overlay"
                    try {
                        Start-Process -FilePath $monBat
                    } catch {
                        Write-Log ("overlay launch failed: " + $_.Exception.Message)
                    }
                } else {
                    Write-Log 'game detected, overlay already running'
                }
                $launched = $true
            }
        } else {
            if ($launched) { Write-Log 'game exited - overlay should close itself' }
            $launched = $false
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Log 'agent stopped'
}
