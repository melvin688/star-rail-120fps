<#
    fps-monitor.ps1 - Minimal always-on-top FPS counter, for any game.

    Reads system-level frame events through Intel PresentMon (ETW) - it never
    injects into the game, and it works on any GPU (NVIDIA / AMD / Intel).

    Requires administrator rights (Windows restricts frame-event tracing);
    FPS-MONITOR.bat handles the elevation prompt for you.

    Distributed under the MIT License. See the LICENSE file in the repository root.

    Usage:
        fps-monitor.ps1 [-ProcessName StarRail.exe]
        FPS-MONITOR.bat -ProcessName OtherGame.exe     # monitor another game
#>
param(
    [string]$ProcessName = 'StarRail.exe'
)

$ErrorActionPreference = 'Stop'

# WinForms needs a single-threaded apartment (Windows PowerShell default).
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    Write-Host 'This script needs STA mode. Run it through FPS-MONITOR.bat instead.'
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Locate PresentMon ---------------------------------------------------
$toolsDir = Join-Path $PSScriptRoot '..\tools'
$script:presentMon = Get-ChildItem -Path $toolsDir -Filter 'PresentMon-*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $script:presentMon) {
    [System.Windows.Forms.MessageBox]::Show("PresentMon was not found in:`n$toolsDir`n`nPlease download the repository completely (including the tools folder).", 'FPS Monitor') | Out-Null
    exit 1
}

# --- Start PresentMon, streaming CSV on stdout ---------------------------
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $script:presentMon.FullName
$psi.Arguments = '--process_name "' + $ProcessName + '" --output_stdout --no_console_stats --stop_existing_session --terminate_on_proc_exit'
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

try {
    $script:proc = [System.Diagnostics.Process]::Start($psi)
} catch {
    [System.Windows.Forms.MessageBox]::Show('Could not start PresentMon: ' + $_.Exception.Message, 'FPS Monitor') | Out-Null
    exit 1
}
# Frame lines are harvested via non-blocking .NET ReadAsync calls issued from the UI
# timer (PowerShell events don't fire reliably inside the WinForms modal loop).
$script:stats = [hashtable]::Synchronized(@{ lines = 0; eof = $false })
$script:readBuf = New-Object char[] 8192
$script:readTask = $null
try { $script:readTask = $script:proc.StandardOutput.ReadAsync($script:readBuf, 0, $script:readBuf.Length) } catch { }
$script:errReader = $script:proc.StandardError

# --- The overlay window --------------------------------------------------
$script:form = New-Object System.Windows.Forms.Form
$script:form.FormBorderStyle = 'None'
$script:form.StartPosition = 'Manual'
$script:form.Location = New-Object System.Drawing.Point(60, 60)
$script:form.Size = New-Object System.Drawing.Size(160, 68)
$script:form.TopMost = $true
$script:form.ShowInTaskbar = $false
$script:form.Opacity = 0.82
$script:form.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 12)
$script:form.Text = 'FPS Monitor'

$script:label = New-Object System.Windows.Forms.Label
$script:label.Dock = 'Fill'
$script:label.TextAlign = 'MiddleCenter'
$script:label.Font = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
$script:label.ForeColor = [System.Drawing.Color]::FromArgb(110, 230, 140)
$script:label.Text = '-- FPS'
$script:label.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$script:form.Controls.Add($script:label)

# drag anywhere to move the window
$script:drag = $false
$script:dx = 0
$script:dy = 0
$script:label.Add_MouseDown({ $script:drag = $true; $script:dx = $_.X; $script:dy = $_.Y })
$script:label.Add_MouseMove({
    if ($script:drag) {
        $script:form.Left += ($_.X - $script:dx)
        $script:form.Top += ($_.Y - $script:dy)
        $script:dx = $_.X
        $script:dy = $_.Y
    }
})
$script:label.Add_MouseUp({ $script:drag = $false })

# right-click -> Exit
$script:menu = New-Object System.Windows.Forms.ContextMenuStrip
$null = $script:menu.Items.Add('Exit')
$script:menu.Items[0].Add_Click({ $script:form.Close() })
$script:label.ContextMenuStrip = $script:menu
$script:form.ContextMenuStrip = $script:menu

# --- Frame counting (two 0.5 s windows ~ fps) ----------------------------
$script:total = 0
$script:lastTotal = 0
$script:prevDelta = 0
$script:startTime = Get-Date

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 500
$script:timer.Add_Tick({
    # harvest completed async reads; each newline = one frame line from PresentMon
    $guard = 0
    while ($null -ne $script:readTask -and $script:readTask.IsCompleted -and $guard -lt 64) {
        $guard++
        try {
            $n = $script:readTask.Result
            if ($n -le 0) { $script:stats['eof'] = $true; $script:readTask = $null; break }
            for ($i = 0; $i -lt $n; $i++) { if ($script:readBuf[$i] -eq [char]10) { $script:stats['lines'] = $script:stats['lines'] + 1 } }
            $script:readTask = $script:proc.StandardOutput.ReadAsync($script:readBuf, 0, $script:readBuf.Length)
        } catch { $script:readTask = $null; break }
    }
    $script:total = $script:stats['lines']

    $delta = $script:total - $script:lastTotal
    $script:lastTotal = $script:total
    $fps = $delta + $script:prevDelta     # frames in the last full second
    $script:prevDelta = $delta

    if ($script:total -gt 0) {
        $script:label.Text = [string]$fps + ' FPS'
        if ($fps -ge 60)     { $script:label.ForeColor = [System.Drawing.Color]::FromArgb(110, 230, 140) }
        elseif ($fps -ge 30) { $script:label.ForeColor = [System.Drawing.Color]::FromArgb(240, 210, 90) }
        else                 { $script:label.ForeColor = [System.Drawing.Color]::FromArgb(240, 100, 100) }
        if ($script:proc.HasExited) {
            # target process exited (PresentMon ended) - close the overlay too
            $script:timer.Stop()
            $script:form.Close()
        }
    }
    elseif ($script:proc.HasExited) {
        $script:timer.Stop()
        $err = ''
        try { $err = $script:errReader.ReadToEnd() } catch { }
        if ($err.Length -gt 400) { $err = $err.Substring(0, 400) }
        [System.Windows.Forms.MessageBox]::Show("PresentMon exited before any frame data arrived.`n`n$err`n`n(If no administrator prompt appeared, close this and start via FPS-MONITOR.bat.)", 'FPS Monitor') | Out-Null
        $script:form.Close()
    }
    else {
        $waited = ((Get-Date) - $script:startTime).TotalSeconds
        if ($waited -gt 3 -and $script:label.Text -eq '-- FPS') {
            $script:label.Font = New-Object System.Drawing.Font('Segoe UI', 10)
            $script:label.Text = 'waiting for ' + $ProcessName + ' ...'
        }
    }
})

# --- Run -----------------------------------------------------------------
$script:form.Add_FormClosed({
    try { $script:timer.Stop() } catch { }
    try { if (-not $script:proc.HasExited) { $script:proc.Kill() } } catch { }
})

$script:timer.Start()
[void]$script:form.ShowDialog()

# window closed - make sure PresentMon is gone too
try { if (-not $script:proc.HasExited) { $script:proc.Kill() } } catch { }
exit 0
