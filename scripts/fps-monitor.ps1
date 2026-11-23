<#
    fps-monitor.ps1 - Always-on-top FPS overlay (NVIDIA Alt+R style), for any game.

    Reads system-level frame events through Intel PresentMon (ETW) - it never
    injects into the game, and it works on any GPU (NVIDIA / AMD / Intel).

    Shows: current FPS, 1% low, frame time. Drag to move, right-click -> Exit.

    Opacity / size / corner come from %LOCALAPPDATA%\star-rail-120fps\overlay.json,
    which the GUI (fps-gui.ps1) writes when you move the opacity slider or pick a
    size. Missing file => 90% opacity, medium (210x84), top-right.

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

# Per-monitor DPI awareness so the panel stays sharp on scaled displays.
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class DpiUtil {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
try { [void][DpiUtil]::SetProcessDPIAware() } catch { }

# --- Overlay preferences (written by the GUI) ----------------------------
$script:ovOpacity = 0.90
$script:ovW       = 210
$script:ovH       = 84
$script:ovPos     = 'topright'
$ovFile = Join-Path $env:LOCALAPPDATA 'star-rail-120fps\overlay.json'
if (Test-Path $ovFile) {
    try {
        $o = Get-Content $ovFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $o.opacity) {
            $v = [double]$o.opacity
            if ($v -ge 0.3 -and $v -le 1.0) { $script:ovOpacity = $v }
        }
        if ($o.size -eq 'small') { $script:ovW = 160; $script:ovH = 64 }
        if ($o.size -eq 'large') { $script:ovW = 260; $script:ovH = 104 }
        if (@('topright', 'topleft', 'bottomright') -contains $o.position) { $script:ovPos = [string]$o.position }
    } catch { }
}

# A position the user dragged the overlay to wins over the preset corner.
$script:ovXY  = $null
$script:posFile = Join-Path $env:LOCALAPPDATA 'star-rail-120fps\position.json'
if (Test-Path $script:posFile) {
    try {
        $q = Get-Content $script:posFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $q.x -and $null -ne $q.y) { $script:ovXY = @([int]$q.x, [int]$q.y) }
    } catch { }
}

# Everything inside the panel scales with its width (base design is 210x84).
$script:sc = $script:ovW / 210.0
function V([double]$p)  { return [int][Math]::Round($p * $script:sc) }
function VF([double]$p) { $v = $p * $script:sc; if ($v -lt 8) { $v = 8 }; return [single]$v }

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
$script:lineBuf = New-Object System.Text.StringBuilder
$script:ftIndex = -1                       # CSV column holding msBetweenPresents
$script:ftQueue = New-Object System.Collections.Generic.Queue[double]
$script:ftCap = 1200                       # ~10 s of frames at 120 fps
$script:errReader = $script:proc.StandardError
try { $script:readTask = $script:proc.StandardOutput.ReadAsync($script:readBuf, 0, $script:readBuf.Length) } catch { }

# --- Feed one CSV line into the frame-time ring --------------------------
function Add-FrameLine([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    $cols = $line.Split(',')
    if ($script:ftIndex -lt 0) {
        for ($i = 0; $i -lt $cols.Count; $i++) {
            if ($cols[$i] -eq 'msBetweenPresents') { $script:ftIndex = $i; return }   # header row
        }
        $script:ftIndex = 4    # no header line: fall back to column 4
    }
    if ($cols.Count -le $script:ftIndex) { return }
    $v = 0.0
    if ([double]::TryParse($cols[$script:ftIndex], [ref]$v)) {
        if ($v -gt 0.01 -and $v -lt 2000.0) {
            $script:ftQueue.Enqueue($v)
            while ($script:ftQueue.Count -gt $script:ftCap) { [void]$script:ftQueue.Dequeue() }
        }
    }
}

# --- The overlay window (Alt+R style, size/opacity from preferences) -----
$script:form = New-Object System.Windows.Forms.Form
$script:form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$script:form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$script:form.Size = New-Object System.Drawing.Size($script:ovW, $script:ovH)
$script:form.TopMost = $true
$script:form.ShowInTaskbar = $false
$script:form.Opacity = $script:ovOpacity
$script:form.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 10)
$script:form.Text = 'FPS Monitor'

# position from preferences (falls back to top-right)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$margin = V 20
switch ($script:ovPos) {
    'topleft'     { $px = $wa.Left + $margin;                        $py = $wa.Top + $margin }
    'bottomright' { $px = $wa.Right - $script:ovW - $margin;         $py = $wa.Bottom - $script:ovH - $margin }
    default       { $px = $wa.Right - $script:ovW - $margin;         $py = $wa.Top + $margin }
}
$script:form.Location = New-Object System.Drawing.Point($px, $py)
if ($script:ovXY) {
    # clamp: the monitor layout may have changed since the position was saved
    $cx = [Math]::Min([Math]::Max($script:ovXY[0], $wa.Left), [Math]::Max($wa.Left, $wa.Right - $script:ovW))
    $cy = [Math]::Min([Math]::Max($script:ovXY[1], $wa.Top),  [Math]::Max($wa.Top,  $wa.Bottom - $script:ovH))
    $script:form.Location = New-Object System.Drawing.Point($cx, $cy)
}

# rounded corners - looks like a modern overlay panel
$rr = [Math]::Max(4, (V 8))
$gp = New-Object System.Drawing.Drawing2D.GraphicsPath
$gp.AddArc(0, 0, $rr, $rr, 180, 90)
$gp.AddArc(($script:ovW - $rr - 1), 0, $rr, $rr, 270, 90)
$gp.AddArc(($script:ovW - $rr - 1), ($script:ovH - $rr - 1), $rr, $rr, 0, 90)
$gp.AddArc(0, ($script:ovH - $rr - 1), $rr, $rr, 90, 90)
$gp.CloseFigure()
$script:form.Region = New-Object System.Drawing.Region($gp)

# big FPS number, unit, and the info line (all scaled together)
$script:fpsVal = New-Object System.Windows.Forms.Label
$script:fpsVal.AutoSize = $true
$script:fpsVal.Location = New-Object System.Drawing.Point((V 14), (V 4))
$script:fpsVal.Font = New-Object System.Drawing.Font('Segoe UI', (VF 30), [System.Drawing.FontStyle]::Bold)
$script:fpsVal.ForeColor = [System.Drawing.Color]::FromArgb(110, 230, 140)
$script:fpsVal.BackColor = [System.Drawing.Color]::Transparent
$script:fpsVal.Text = '--'
$script:fpsVal.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$script:form.Controls.Add($script:fpsVal)

$script:fpsUnit = New-Object System.Windows.Forms.Label
$script:fpsUnit.AutoSize = $true
$script:fpsUnit.Location = New-Object System.Drawing.Point((V 96), (V 30))
$script:fpsUnit.Font = New-Object System.Drawing.Font('Segoe UI', (VF 10.5), [System.Drawing.FontStyle]::Bold)
$script:fpsUnit.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
$script:fpsUnit.BackColor = [System.Drawing.Color]::Transparent
$script:fpsUnit.Text = 'FPS'
$script:fpsUnit.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$script:form.Controls.Add($script:fpsUnit)

$script:info = New-Object System.Windows.Forms.Label
$script:info.AutoSize = $false
$script:info.Location = New-Object System.Drawing.Point((V 14), (V 54))
$script:info.Size = New-Object System.Drawing.Size((V 182), (V 20))
$script:info.Font = New-Object System.Drawing.Font('Segoe UI', (VF 9.5))
$script:info.ForeColor = [System.Drawing.Color]::FromArgb(160, 165, 170)
$script:info.BackColor = [System.Drawing.Color]::Transparent
$script:info.Text = 'waiting ...'
$script:info.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$script:form.Controls.Add($script:info)

# drag anywhere; right-click -> Exit
$script:drag = $false
$script:dx = 0
$script:dy = 0
$script:dragables = @($script:form, $script:fpsVal, $script:fpsUnit, $script:info)
foreach ($c in $script:dragables) {
    $c.Add_MouseDown({ $script:drag = $true; $script:dx = $_.X; $script:dy = $_.Y })
    $c.Add_MouseMove({
        if ($script:drag) {
            $script:form.Left += ($_.X - $script:dx)
            $script:form.Top += ($_.Y - $script:dy)
            $script:dx = $_.X
            $script:dy = $_.Y
        }
    })
    $c.Add_MouseUp({
        $script:drag = $false
        try {
            $pair = '' + $script:form.Left + ',' + $script:form.Top
            if ($script:lastXY -ne $pair) {
                $script:lastXY = $pair
                $dir = Join-Path $env:LOCALAPPDATA 'star-rail-120fps'
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $json = '{"x":' + $script:form.Left + ',"y":' + $script:form.Top + '}'
                [System.IO.File]::WriteAllText((Join-Path $dir 'position.json'), $json,
                    (New-Object System.Text.UTF8Encoding $false))
            }
        } catch { }
    })
}

$script:menu = New-Object System.Windows.Forms.ContextMenuStrip
$null = $script:menu.Items.Add('Exit')
$script:menu.Items[0].Add_Click({ $script:form.Close() })
$script:form.ContextMenuStrip = $script:menu
foreach ($c in $script:dragables) { $c.ContextMenuStrip = $script:menu }

# --- Counting + UI refresh ------------------------------------------------
$script:total = 0
$script:lastTotal = 0
$script:prevDelta = 0
$script:startTime = Get-Date

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 500
$script:timer.Add_Tick({
    # 1) harvest completed async reads; feed complete lines to the CSV parser
    $guard = 0
    while ($null -ne $script:readTask -and $script:readTask.IsCompleted -and $guard -lt 64) {
        $guard++
        try {
            $n = $script:readTask.Result
            if ($n -le 0) { $script:stats['eof'] = $true; $script:readTask = $null; break }
            $chunk = [string]::new($script:readBuf, 0, $n)
            $parts = $chunk -split "`n"
            $last = $parts.Count - 1
            for ($pi = 0; $pi -lt $parts.Count; $pi++) {
                if ($pi -eq 0) {
                    $line = $script:lineBuf.ToString() + $parts[0]
                    [void]$script:lineBuf.Clear()
                } elseif ($pi -eq $last) {
                    [void]$script:lineBuf.Append($parts[$pi])
                    continue
                } else {
                    $line = $parts[$pi]
                }
                $line = $line.TrimEnd("`r")
                if ($line.Length -gt 0) {
                    Add-FrameLine $line
                    $script:stats['lines'] = $script:stats['lines'] + 1
                }
            }
            $script:readTask = $script:proc.StandardOutput.ReadAsync($script:readBuf, 0, $script:readBuf.Length)
        } catch { $script:readTask = $null; break }
    }
    $script:total = $script:stats['lines']

    $delta = $script:total - $script:lastTotal
    $script:lastTotal = $script:total
    $fps = $delta + $script:prevDelta          # frames in the last full second
    $script:prevDelta = $delta

    if ($script:total -gt 0) {
        $script:fpsVal.Text = [string]$fps
        $script:fpsUnit.Left = $script:fpsVal.Right + (V 8)
        if ($fps -ge 60)     { $script:fpsVal.ForeColor = [System.Drawing.Color]::FromArgb(110, 230, 140) }
        elseif ($fps -ge 30) { $script:fpsVal.ForeColor = [System.Drawing.Color]::FromArgb(240, 210, 90) }
        else                 { $script:fpsVal.ForeColor = [System.Drawing.Color]::FromArgb(240, 100, 100) }

        # 1% low and median frame time from the frame-time ring
        if ($script:ftQueue.Count -gt 20) {
            $sorted = $script:ftQueue.ToArray()
            [Array]::Sort($sorted)
            $lowCount = [Math]::Max(1, [int]($sorted.Length * 0.01))
            $sum = 0.0
            for ($i = 0; $i -lt $lowCount; $i++) { $sum += $sorted[$i] }
            $avgLow = $sum / $lowCount
            $lowFps = 0
            if ($avgLow -gt 0) { $lowFps = [int](1000.0 / $avgLow) }
            $median = $sorted[[int]($sorted.Length / 2)]
            if ($lowFps -gt 0) {
                $script:info.Text = ('1% Low  {0}      {1:0.0} ms' -f $lowFps, $median)
            } else {
                $script:info.Text = ('Frame  {0:0.0} ms' -f $median)
            }
        } else {
            $script:info.Text = ('Frame  {0:0.0} ms' -f (1000.0 / [Math]::Max(1, $fps)))
        }

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
        if ($waited -gt 3 -and $script:fpsVal.Text -eq '--') {
            $script:info.Text = 'waiting for ' + $ProcessName + ' ...'
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
