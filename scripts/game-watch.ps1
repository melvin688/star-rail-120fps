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

# Read the FPS tier the game currently has stored. Read-only: the watcher never
# writes the registry, it only notices when the cap falls back to 60.
function Get-CurrentFps {
    foreach ($k in @('Software\Cognosphere\Star Rail', 'Software\miHoYo\崩坏：星穹铁道')) {
        $psPath = 'HKCU:\' + $k
        if (-not (Test-Path -LiteralPath $psPath)) { continue }
        try {
            $item = Get-Item -LiteralPath $psPath
            $names = @($item.GetValueNames() | Where-Object { $_ -like 'GraphicsSettings_Model_h*' })
            if ($names.Count -eq 0) { continue }
            $raw = $item.GetValue($names[0])
            if ($raw -isnot [byte[]]) { continue }
            $text = [System.Text.Encoding]::UTF8.GetString($raw)
            if ($text -match '"FPS":(\d+)') { return [int]$Matches[1] }
        } catch { }
    }
    return -1
}

# One-shot tray balloon. The watcher runs windowless, so this is the only way to
# tell the user something without stealing focus mid-game.
function Show-Toast([string]$title, [string]$text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Information
        $ni.Visible = $true
        $ni.BalloonTipTitle = $title
        $ni.BalloonTipText = $text
        $ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
        $ni.ShowBalloonTip(8000)
        Start-Sleep -Milliseconds 3000
        $ni.Visible = $false
        $ni.Dispose()
    } catch { }
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
$lastFps  = -1
$tick     = 0
try {
    while ($true) {
        $game = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        $tick++

        if ($game) {
            # check the stored cap about every 30 s; the game rewrites it to 60
            # whenever you change a graphics option in-game
            if (($tick % 10) -eq 0) {
                $now = Get-CurrentFps
                if ($now -gt 0) {
                    if ($lastFps -ge 120 -and $now -lt 120) {
                        Write-Log "FPS cap fell back: $lastFps -> $now"
                        Show-Toast 'Star Rail 120 FPS' ('The FPS cap fell back to ' + $now + ' - the game rewrote it after a graphics-setting change. Open the tool and click unlock again.')
                    }
                    $lastFps = $now
                }
            }
        }

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
