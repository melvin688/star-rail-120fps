# Star Rail 120 FPS tool - bilingual dark GUI (layout A: card flow + overlay settings)
# PowerShell 5.1, dependency-free. Wraps scripts\fps-cap.ps1.
# DPI-aware: every coordinate goes through S()/FS() so the layout holds at 100/125/150/200%.
# Small screens: the window shrinks to the working area and scrolls instead of clipping.
param(
    [ValidateSet('zh', 'en')]
    [string]$Lang = 'zh'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# DPI awareness must be declared before the first window is created
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class DpiUtil {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
try { [void][DpiUtil]::SetProcessDPIAware() } catch { }

$ErrorActionPreference = 'Stop'

# --- paths ---------------------------------------------------------------
$script:root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path (Join-Path $script:root 'scripts\fps-cap.ps1'))) {
    $script:root = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:capScript = Join-Path $script:root 'scripts\fps-cap.ps1'
$script:monBat    = Join-Path $script:root 'FPS-MONITOR.bat'
$script:lang      = $Lang
$script:ovDir     = Join-Path $env:LOCALAPPDATA 'star-rail-120fps'
$script:ovFile    = Join-Path $script:ovDir 'overlay.json'

# --- DPI helpers ---------------------------------------------------------
$script:g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$script:S = [Math]::Round($script:g0.DpiX / 96.0, 3)
$script:g0.Dispose()
if ($script:S -lt 1) { $script:S = 1 }
function S([double]$v)  { return [int][Math]::Round($v * $script:S) }
function FS([double]$v) { return [single]($v * $script:S) }

# --- Display refresh rate (EnumDisplaySettings, primary monitor) ---------
# WMI reports one row per adapter and its numbers can disagree (iGPU vs dGPU),
# so ask Windows for the primary display's actual mode instead.
if (-not ('DispHz' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class DispHz {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet=CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    static DEVMODE Blank() {
        DEVMODE d = new DEVMODE();
        d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        return d;
    }
    public static int Current() {
        DEVMODE d = Blank();
        if (EnumDisplaySettings(null, -1, ref d)) return d.dmDisplayFrequency;
        return 0;
    }
    // highest refresh rate available at the current resolution
    public static int Max() {
        DEVMODE cur = Blank();
        if (!EnumDisplaySettings(null, -1, ref cur)) return 0;
        int best = cur.dmDisplayFrequency;
        for (int i = 0; i < 500; i++) {
            DEVMODE d = Blank();
            if (!EnumDisplaySettings(null, i, ref d)) break;
            if (d.dmPelsWidth != cur.dmPelsWidth || d.dmPelsHeight != cur.dmPelsHeight) continue;
            if (d.dmDisplayFrequency > best) best = d.dmDisplayFrequency;
        }
        return best;
    }
}
'@
}

# --- string tables -------------------------------------------------------
$script:L = @{}
$script:L.zh = @{
    winTitle   = 'Star Rail 120 FPS 工具'
    title      = '星穹铁道 120 帧工具'
    subtitle   = '解锁官方隐藏的 120 FPS 档位 · 只修改游戏自己的设置值'
    st120      = '已解锁 120 FPS'
    st60       = '官方默认 60 FPS'
    stUnknown  = '检测到未知值 {0}'
    stNone     = '未找到游戏设置'
    clientLine = '客户端：{0} · 原值已备份（可还原）'
    clientNA   = '客户端：未检测到（运行过游戏后出现）'
    clientGlobal = '国际服'
    clientCN   = '国服'
    clientBoth = '国际服 · 国服'
    heroUnlocked = '已解锁'
    heroDefault  = '官方默认'
    heroMismatch = '需同步'
    heroUnknown  = '当前上限'
    heroNone     = '未检测到设置'
    factClient = '客户端'
    factHz     = '显示器'
    factGame   = '游戏'
    factBackup = '备份'
    valGameOn    = '运行中'
    valGameOff   = '未运行'
    valBackupOk  = '可还原'
    valBackupNo  = '无备份'
    valHz        = '{0} Hz'
    valClientNA  = '未检测到'
    gameOn     = '游戏正在运行 · 请先完全退出再操作'
    gameOff    = '游戏未运行 · 显示器 {0} Hz'
    hzUnknown  = '游戏未运行 · 显示器 -- Hz'
    tierTitle  = '目标帧率'
    tier120    = '120'
    tierAuto   = '跟随屏幕'
    btnOn      = '开启 120 FPS'
    btnOff     = '恢复 60 FPS'
    ovTitle    = '帧率小窗'
    ovLaunch   = '启动小窗 →'
    ovClose    = '关闭小窗 ✕'
    autoTitle  = '开游戏时自动启动'
    autoOn     = '已开启'
    autoOff    = '已关闭'
    autoRunning = '守护进程运行中'
    autoFail   = '无法创建启动项。请确认工具文件夹完整（含 GAME-WATCH.vbs），并且你没有禁用启动文件夹。'
    opacity    = '不透明度'
    size       = '尺寸'
    position   = '位置'
    szS        = '小'
    szM        = '中'
    szL        = '大'
    posTR      = '右上'
    posTL      = '左上'
    posBR      = '右下'
    preview    = '预览 {0} × {1} · {2}% 不透明 · {3}'
    notesTitle = '注意事项'
    notes      = @(
        '· 操作前请先完全退出游戏（运行中修改会被覆盖）',
        '· 解锁后请勿再动游戏内画面/帧率设置，否则会重置回 60',
        '· 游戏设置界面显示 30/60 是正常现象，以帧率小窗为准',
        '· 想还原官方默认：随时点「恢复 60 FPS」',
        '· 小窗可拖动；Ctrl+Alt+L 锁定（锁定后鼠标穿透，不挡游戏操作）',
        '· Ctrl+Alt+H 隐藏/显示小窗，Ctrl+Alt+F 关闭',
        '· 「开游戏时自动启动」会在启动文件夹放一个快捷方式，随时可关',
        '· 备份保存在本机 %LOCALAPPDATA%\star-rail-120fps\'
    )
    footer     = 'v1.0 · MIT License · 状态实时读取注册表'
    errTitle   = '操作未完成'
}
$script:L.en = @{
    winTitle   = 'Star Rail 120 FPS Tool'
    title      = 'Star Rail 120 FPS Tool'
    subtitle   = 'Unlocks the hidden 120 FPS option - safe & reversible'
    st120      = 'Unlocked - 120 FPS'
    st60       = 'Official default - 60 FPS'
    stUnknown  = 'Unknown value {0}'
    stNone     = 'Game settings not found'
    clientLine = 'Client: {0} - original value backed up (restorable)'
    clientNA   = 'Client: not detected (appears after you run the game once)'
    clientGlobal = 'Global'
    clientCN   = 'China'
    clientBoth = 'Global · China'
    heroUnlocked = 'Unlocked'
    heroDefault  = 'Official default'
    heroMismatch = 'Out of sync'
    heroUnknown  = 'Current cap'
    heroNone     = 'No settings found'
    factClient = 'Client'
    factHz     = 'Display'
    factGame   = 'Game'
    factBackup = 'Backup'
    valGameOn    = 'Running'
    valGameOff   = 'Not running'
    valBackupOk  = 'Restorable'
    valBackupNo  = 'None'
    valHz        = '{0} Hz'
    valClientNA  = 'Not found'
    gameOn     = 'Game is running - exit it before unlock/restore'
    gameOff    = 'Game not running - display {0} Hz'
    hzUnknown  = 'Game not running - display -- Hz'
    tierTitle  = 'FPS cap'
    tier120    = '120'
    tierAuto   = 'Follow display'
    btnOn      = 'Unlock 120 FPS'
    btnOff     = 'Restore 60 FPS'
    ovTitle    = 'FPS overlay'
    ovLaunch   = 'Launch →'
    ovClose    = 'Close ✕'
    autoTitle  = 'Start with the game'
    autoOn     = 'On'
    autoOff    = 'Off'
    autoRunning = 'Watcher running'
    autoFail   = 'Could not create the startup entry. Make sure the tool folder is complete (GAME-WATCH.vbs present) and the Startup folder is not disabled.'
    opacity    = 'Opacity'
    size       = 'Size'
    position   = 'Position'
    szS        = 'Small'
    szM        = 'Medium'
    szL        = 'Large'
    posTR      = 'Top-right'
    posTL      = 'Top-left'
    posBR      = 'Bottom-right'
    preview    = 'Preview {0} × {1} · {2}% opacity · {3}'
    notesTitle = 'Notes'
    notes      = @(
        '· Exit the game fully first (in-game changes overwrite this)',
        '· Do not touch in-game graphics/FPS settings after unlocking',
        '· In-game menu still showing 30/60 is normal; trust the counter',
        '· Restore the official default anytime: "Restore 60 FPS"',
        '· Drag the overlay anywhere; Ctrl+Alt+L locks it (clicks pass through)',
        '· Ctrl+Alt+H hides/shows it, Ctrl+Alt+F closes it',
        '· "Start with the game" adds a Startup shortcut, removable here',
        '· Backup kept in %LOCALAPPDATA%\star-rail-120fps\'
    )
    footer     = 'v1.0 · MIT License · live status from the registry'
    errTitle   = 'Action not completed'
}

# --- registry helpers ----------------------------------------------------
function Get-FpsInfo {
    $candidates = @(
        @{ path = 'Software\Cognosphere\Star Rail';        key = 'global' },
        @{ path = 'Software\miHoYo\崩坏：星穹铁道';         key = 'cn' }
    )
    # Collect every installed client instead of stopping at the first one; a
    # machine can have both, and reporting only one would hide that the other
    # is still capped. @() keeps a single result from unrolling to a scalar.
    $found = @()
    foreach ($c in $candidates) {
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($c.path)
        if ($null -eq $k) { continue }
        $cap = $null
        foreach ($v in $k.GetValueNames()) {
            if ($v -like 'GraphicsSettings_Model_h*') {
                $b = $k.GetValue($v)
                if ($null -eq $b) { continue }
                $t = [System.Text.Encoding]::UTF8.GetString($b)
                $m = [regex]::Match($t, '"FPS"\s*:\s*(\d+)')
                if ($m.Success) { $cap = [int]$m.Groups[1].Value; break }
            }
        }
        $found += @{ key = $c.key; fps = $cap }
    }
    if ($found.Count -eq 0) { return @{ fps = $null; client = $null; clients = @() } }

    # Report the lowest cap across clients: the UI calls it unlocked only when
    # every installed client really is.
    $caps = @($found | Where-Object { $null -ne $_.fps } | ForEach-Object { $_.fps })
    $worst = if ($caps.Count -gt 0) { ($caps | Measure-Object -Minimum).Minimum } else { $null }
    $keys = @($found | ForEach-Object { $_.key })
    $label = if ($keys.Count -gt 1) { 'both' } else { $keys[0] }
    return @{ fps = $worst; client = $label; clients = $found }
}
function Test-GameRunning { return [bool](Get-Process StarRail -ErrorAction SilentlyContinue) }

# --- overlay settings (shared with fps-monitor.ps1) ----------------------
$script:sliderVal = 90
$script:sizeKey   = 'medium'
$script:posKey    = 'topright'
# '120' = the verified hidden tier; 'auto' = highest tier the display can show
$script:tierKey   = '120'

# auto-start ("start the overlay with the game") is backed by a real shortcut
# in the Startup folder - the shortcut is the single source of truth, so if the
# user deletes it by hand the GUI simply shows the option as off.
$script:startupDir  = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$script:startupLnk  = Join-Path $script:startupDir 'StarRail120FPS-Agent.lnk'
$script:watchVbs    = Join-Path $script:root 'GAME-WATCH.vbs'
$script:watchScript = Join-Path $script:root 'scripts\game-watch.ps1'
$script:autoStart   = $false
$script:hzRef       = -1

function Get-MaxHz {
    if ($script:hzRef -ge 0) { return $script:hzRef }
    $hz = 0
    try { $hz = [DispHz]::Max() } catch { }
    if ($hz -le 0) {
        try {
            $hz = (Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                   Measure-Object -Property CurrentRefreshRate -Maximum).Maximum
        } catch { }
    }
    $script:hzRef = [int]$hz
    return $script:hzRef
}
function Sync-AutoStart {
    $script:autoStart = Test-Path -LiteralPath $script:startupLnk
}
function Stop-Overlay {
    # Closing from the main window: the overlay itself also closes via
    # Ctrl+Alt+F or its right-click menu.
    $stopped = $false
    try {
        $pidFile = Join-Path $env:LOCALAPPDATA 'star-rail-120fps\overlay.pid'
        if (Test-Path $pidFile) {
            $ovPid = 0
            if ([int]::TryParse((Get-Content $pidFile -Raw -ErrorAction Stop).Trim(), [ref]$ovPid)) {
                Stop-Process -Id $ovPid -Force -ErrorAction SilentlyContinue
                $stopped = $true
            }
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    if ($stopped) { return }
    # Fallback for an overlay started before the PID file existed. This is the
    # slow WMI path, so it only runs on an explicit click, never from the timer.
    try {
        Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -and $_.CommandLine -like '*fps-monitor.ps1*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Sync-OverlayButton {
    $L = $script:L[$script:lang]
    if (-not $btnOvLaunch) { return }
    if (Test-OverlayRunning) {
        $btnOvLaunch.Text = $L.ovClose
        $btnOvLaunch.ForeColor = [System.Drawing.Color]::FromArgb(210, 120, 120)
    } else {
        $btnOvLaunch.Text = $L.ovLaunch
        $btnOvLaunch.ForeColor = $green
    }
}

function Test-OverlayRunning {
    # Hot path: called from the 2s UI timer, so it must never block. Reading one
    # small file and doing a Get-Process lookup costs microseconds, whereas the
    # Win32_Process WMI sweep it used to do froze the whole window.
    try {
        $pidFile = Join-Path $env:LOCALAPPDATA 'star-rail-120fps\overlay.pid'
        if (Test-Path $pidFile) {
            $ovPid = 0
            if ([int]::TryParse((Get-Content $pidFile -Raw -ErrorAction Stop).Trim(), [ref]$ovPid)) {
                $p = Get-Process -Id $ovPid -ErrorAction SilentlyContinue
                if ($p -and -not $p.HasExited) { return $true }
            }
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    return $false
}
function Enable-AutoStart {
    if (-not (Test-Path -LiteralPath $script:watchVbs)) { return $false }
    if (-not (Test-Path -LiteralPath $script:startupDir)) { return $false }
    try {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($script:startupLnk)
        $lnk.TargetPath       = 'wscript.exe'
        $lnk.Arguments        = '"' + $script:watchVbs + '"'
        $lnk.WorkingDirectory = $script:root
        $lnk.Description      = 'Star Rail 120 FPS - FPS overlay watcher'
        $lnk.WindowStyle      = 7
        $icoPath = Join-Path $script:root 'docs\app.ico'
        if (Test-Path -LiteralPath $icoPath) { $lnk.IconLocation = "$icoPath,0" }
        $lnk.Save()
        # start it right away so the user does not have to reboot
        Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $script:watchVbs + '"') -WindowStyle Hidden
        return $true
    } catch { return $false }
}
function Disable-AutoStart {
    try {
        Remove-Item -LiteralPath $script:startupLnk -Force -ErrorAction SilentlyContinue
        $stopScript = $script:watchScript
        if (Test-Path -LiteralPath $stopScript) {
            Start-Process -FilePath 'powershell.exe' `
                -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $stopScript + '" -Stop') `
                -WindowStyle Hidden
        }
        return $true
    } catch { return $false }
}

function Load-Overlay {
    if (-not (Test-Path $script:ovFile)) { return }
    try {
        $o = Get-Content $script:ovFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $o.opacity) {
            $v = [int][Math]::Round([double]$o.opacity * 100)
            if ($v -ge 50 -and $v -le 100) { $script:sliderVal = $v }
        }
        if (@('small', 'medium', 'large') -contains $o.size)         { $script:sizeKey = [string]$o.size }
        if (@('topright', 'topleft', 'bottomright') -contains $o.position) { $script:posKey = [string]$o.position }
        if (@('120', 'auto') -contains $o.tier)                      { $script:tierKey = [string]$o.tier }
    } catch { }
}
function Save-Overlay {
    try {
        if (-not (Test-Path $script:ovDir)) { New-Item -ItemType Directory -Path $script:ovDir -Force | Out-Null }
        $o = [ordered]@{
            opacity  = [Math]::Round($script:sliderVal / 100.0, 2)
            size     = $script:sizeKey
            position = $script:posKey
            tier     = $script:tierKey
        }
        $json = $o | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($script:ovFile, $json, (New-Object System.Text.UTF8Encoding $false))
    } catch { }
}

# --- palette -------------------------------------------------------------
$bg     = [System.Drawing.Color]::FromArgb(18, 18, 18)
$card   = [System.Drawing.Color]::FromArgb(28, 28, 31)
$fg     = [System.Drawing.Color]::FromArgb(236, 236, 236)
$dim    = [System.Drawing.Color]::FromArgb(150, 150, 150)
$dim2   = [System.Drawing.Color]::FromArgb(108, 108, 114)
$green  = [System.Drawing.Color]::FromArgb(110, 230, 140)
$greenBg = [System.Drawing.Color]::FromArgb(30, 48, 36)
$greenBrd = [System.Drawing.Color]::FromArgb(60, 140, 90)
$amber  = [System.Drawing.Color]::FromArgb(240, 210, 90)
$btnBg  = [System.Drawing.Color]::FromArgb(40, 40, 44)
$btnBrd = [System.Drawing.Color]::FromArgb(80, 80, 86)
$selBg  = [System.Drawing.Color]::FromArgb(70, 70, 78)
$selBrd = [System.Drawing.Color]::FromArgb(138, 138, 150)
$trackC = [System.Drawing.Color]::FromArgb(56, 56, 62)
$F = 'Microsoft YaHei UI'

# --- widgets -------------------------------------------------------------
function New-Lbl([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [double]$size, $color, [bool]$bold) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $st = [System.Drawing.FontStyle]::Regular
    if ($bold) { $st = [System.Drawing.FontStyle]::Bold }
    $l.Font = New-Object System.Drawing.Font($F, (FS $size), $st)
    $l.ForeColor = $color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize = $false
    $l.UseMnemonic = $false
    return $l
}
function New-FlatBtn([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [double]$size, [bool]$bold) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = $btnBg
    $b.ForeColor = $fg
    $b.FlatAppearance.BorderColor = $btnBrd
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(50, 50, 55)
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(34, 34, 38)
    $st = [System.Drawing.FontStyle]::Regular
    if ($bold) { $st = [System.Drawing.FontStyle]::Bold }
    $b.Font = New-Object System.Drawing.Font($F, (FS $size), $st)
    $b.UseVisualStyleBackColor = $false
    return $b
}
function New-Pill([int]$x, [int]$y, [int]$w, [int]$h) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(44, 44, 50)
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(34, 34, 38)
    $b.Font = New-Object System.Drawing.Font($F, (FS 8.5))
    $b.UseVisualStyleBackColor = $false
    return $b
}
function Style-Pill($btn, [bool]$on) {
    if ($on) {
        $btn.BackColor = $greenBg
        $btn.ForeColor = $green
        $btn.FlatAppearance.BorderColor = $greenBrd
    } else {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(36, 36, 40)
        $btn.ForeColor = $dim
        $btn.FlatAppearance.BorderColor = $btnBrd
    }
}

# --- form + layout -------------------------------------------------------
# Geometry follows the 002 two-column sketch: a wide left column holding the
# status hero and both primary actions, and a right column stacking the overlay
# settings above the notes. Column widths are design pixels, scaled by S().
$colL    = 300    # left column: status + actions
$colR    = 360    # right column: overlay settings + notes. Wider than the
                  # sketch's 317 because the English "Bottom-right" needs an
                  # 87px cell and a shared 66px label column.
$padX    = 18
$colGap  = 14
$cardGap = 14
$cardPad = 16
$desWpx  = $padX * 2 + $colL + $colGap + $colR      # 687
$ix      = $cardPad                                  # inner x inside a card
$iwL     = $colL - ($cardPad * 2)                    # 268
$iwR     = $colR - ($cardPad * 2)                    # 305
$cardTop = 70

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $bg
$form.ForeColor = $fg
$form.Font = New-Object System.Drawing.Font($F, (FS 10))

$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$desW = S $desWpx
$desH = S 556
# Keep the window inside the work area on BOTH axes; scroll instead of clipping.
$maxW = $wa.Width - (S 60)
$maxH = $wa.Height - (S 70)
$script:scrollMode = ($desH -gt $maxH)
if ($script:scrollMode) { $desW = [Math]::Min($desW + (S 20), $maxW) }   # width for the 17px scrollbar
if ($desW -gt $maxW) { $desW = $maxW }
if ($desH -gt $maxH) { $desH = $maxH }
$form.ClientSize = New-Object System.Drawing.Size($desW, $desH)
$form.AutoScroll = $script:scrollMode

# header
$lblTitle = New-Lbl '' (S 22) (S 14) (S 320) (S 28) 16 $fg $true; $form.Controls.Add($lblTitle)
$lblSub   = New-Lbl '' (S 22) (S 44) (S 460) (S 16) 8.5 $dim $false; $form.Controls.Add($lblSub)
$btnZh = New-Pill (S ($desWpx - $padX - 94)) (S 16) (S 44) (S 26); $btnZh.Text = '中文'; $form.Controls.Add($btnZh)
$btnEn = New-Pill (S ($desWpx - $padX - 46)) (S 16) (S 42) (S 26); $btnEn.Text = 'EN';   $form.Controls.Add($btnEn)

# --- left card: status hero, facts, tier, actions ------------------------
$card1 = New-Object System.Windows.Forms.Panel
$card1.Location = New-Object System.Drawing.Point((S $padX), (S $cardTop))
$card1.Size = New-Object System.Drawing.Size((S $colL), (S 392))
$card1.BackColor = $card
$form.Controls.Add($card1)

# the hero is a plain number: state in words goes on the small line above it,
# because "120 / 60" at 30pt would not fit and reads ambiguously anyway
$lblHeroLabel = New-Lbl '' (S $ix) (S 14) (S $iwL) (S 16) 8.5 $dim $false; $card1.Controls.Add($lblHeroLabel)
$lblState     = New-Lbl '' (S $ix) (S 30) (S 150) (S 58) 30 $green $true;  $card1.Controls.Add($lblState)
$lblStateUnit = New-Lbl '' (S ($ix + 112)) (S 56) (S 90) (S 22) 11 $dim $false; $card1.Controls.Add($lblStateUnit)

# facts: label left, value right, one row each
$factsY = 104
$factsH = 22
$factRows = @('Client', 'Hz', 'Game', 'Backup')
$script:factK = @{}
$script:factV = @{}
for ($i = 0; $i -lt $factRows.Count; $i++) {
    $y = $factsY + ($i * $factsH)
    $k = New-Lbl '' (S $ix) (S $y) (S 70) (S 18) 8.5 $dim $false
    $v = New-Lbl '' (S ($ix + 74)) (S $y) (S ($iwL - 74)) (S 18) 8.5 $fg $false
    $v.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $card1.Controls.Add($k); $card1.Controls.Add($v)
    $script:factK[$factRows[$i]] = $k
    $script:factV[$factRows[$i]] = $v
}

# target frame-rate tier: only 30/60/120 exist in the client, so "follow the
# display" means picking the highest tier the monitor can actually show.
$tierY = 212
$lblTier      = New-Lbl '' (S $ix) (S ($tierY + 4)) (S 66) (S 18) 8.5 $dim $false; $card1.Controls.Add($lblTier)
$segW         = $iwL - 66
$pillTier120  = New-Pill (S ($ix + 66)) (S $tierY) (S 60) (S 26);  $card1.Controls.Add($pillTier120)
$pillTierAuto = New-Pill (S ($ix + 66 + 60)) (S $tierY) (S ($segW - 60)) (S 26); $card1.Controls.Add($pillTierAuto)

# action buttons: full width of the card, stacked
$btnY = 270
$btnOn  = New-FlatBtn '' (S $ix) (S $btnY) (S $iwL) (S 48) 11 $true;   $card1.Controls.Add($btnOn)
$btnOff = New-FlatBtn '' (S $ix) (S ($btnY + 56)) (S $iwL) (S 48) 10.5 $false; $card1.Controls.Add($btnOff)
$btnOn.BackColor = [System.Drawing.Color]::FromArgb(30, 48, 36)
$btnOn.ForeColor = $green
$btnOn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 120, 80)
$btnOn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 62, 46)
$btnOn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(24, 40, 30)

# --- right card 1: overlay settings --------------------------------------
$colRx = $padX + $colL + $colGap
$card2 = New-Object System.Windows.Forms.Panel
$card2.Location = New-Object System.Drawing.Point((S $colRx), (S $cardTop))
$card2.Size = New-Object System.Drawing.Size((S $colR), (S 237))
$card2.BackColor = $card
$form.Controls.Add($card2)

$lblOvTitle = New-Lbl '' (S $ix) (S 14) (S 140) (S 22) 11 $fg $true; $card2.Controls.Add($lblOvTitle)
$btnOvLaunch = New-FlatBtn '' (S ($ix + $iwR - 130)) (S 12) (S 130) (S 26) 9 $false
$btnOvLaunch.BackColor = $card
$btnOvLaunch.ForeColor = $green
$btnOvLaunch.FlatAppearance.BorderColor = $card
$btnOvLaunch.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(36, 36, 40)
$card2.Controls.Add($btnOvLaunch)

# rows share one grid: 66px label, then whatever is left
$rowKeyW = 66
$rowValW = 42
$rowCtlX = $ix + $rowKeyW
$rowCtlW = $iwR - $rowKeyW - $rowValW

$row1Y = 50
$lblOpacity    = New-Lbl '' (S $ix) (S ($row1Y + 4)) (S $rowKeyW) (S 18) 8.5 $dim $false; $card2.Controls.Add($lblOpacity)
$lblOpacityVal = New-Lbl '' (S ($ix + $iwR - $rowValW)) (S ($row1Y + 2)) (S $rowValW) (S 18) 9 $fg $true
$lblOpacityVal.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$card2.Controls.Add($lblOpacityVal)

$slider = New-Object System.Windows.Forms.Panel
$slider.Location = New-Object System.Drawing.Point((S $rowCtlX), (S $row1Y))
$slider.Size = New-Object System.Drawing.Size((S $rowCtlW), (S 26))
$slider.BackColor = $card
$card2.Controls.Add($slider)

$row2Y = 86
$lblSize = New-Lbl '' (S $ix) (S ($row2Y + 4)) (S $rowKeyW) (S 18) 8.5 $dim $false; $card2.Controls.Add($lblSize)
$rowCtlWFull = $iwR - $rowKeyW          # no value column on these two rows
$sw = [int]($rowCtlWFull / 3)
$pillS = New-Pill (S $rowCtlX) (S $row2Y) (S $sw) (S 26); $card2.Controls.Add($pillS)
$pillM = New-Pill (S ($rowCtlX + $sw)) (S $row2Y) (S $sw) (S 26); $card2.Controls.Add($pillM)
$pillL = New-Pill (S ($rowCtlX + $sw * 2)) (S $row2Y) (S ($rowCtlWFull - $sw * 2)) (S 26); $card2.Controls.Add($pillL)

$row3Y = 122
$lblPos = New-Lbl '' (S $ix) (S ($row3Y + 4)) (S $rowKeyW) (S 18) 8.5 $dim $false; $card2.Controls.Add($lblPos)
$pillTR = New-Pill (S $rowCtlX) (S $row3Y) (S $sw) (S 26); $card2.Controls.Add($pillTR)
$pillTL = New-Pill (S ($rowCtlX + $sw)) (S $row3Y) (S $sw) (S 26); $card2.Controls.Add($pillTL)
$pillBR = New-Pill (S ($rowCtlX + $sw * 2)) (S $row3Y) (S ($rowCtlWFull - $sw * 2)) (S 26); $card2.Controls.Add($pillBR)

$lblPreview = New-Lbl '' (S $ix) (S 156) (S $iwR) (S 18) 8 $dim2 $false; $card2.Controls.Add($lblPreview)

$lblAuto  = New-Lbl '' (S $ix) (S 186) (S 150) (S 22) 8.5 $dim $false; $card2.Controls.Add($lblAuto)
$pillAuto = New-Pill (S ($ix + $iwR - 76)) (S 184) (S 76) (S 26); $card2.Controls.Add($pillAuto)

# --- right card 2: notes -------------------------------------------------
$card3 = New-Object System.Windows.Forms.Panel
$card3.Location = New-Object System.Drawing.Point((S $colRx), (S ($cardTop + 237 + $cardGap)))
$card3.Size = New-Object System.Drawing.Size((S $colR), (S 141))
$card3.BackColor = $card
$form.Controls.Add($card3)

$lblNotesTitle = New-Lbl '' (S $ix) (S 14) (S 200) (S 22) 11 $fg $true; $card3.Controls.Add($lblNotesTitle)
$lblNotes = New-Lbl '' (S $ix) (S 42) (S $iwR) (S 88) 8.5 $dim $false; $card3.Controls.Add($lblNotes)
$lblNotes.AutoSize = $false

$lblFooter = New-Lbl '' (S $padX) (S 522) (S ($desWpx - $padX * 2)) (S 18) 8 $dim2 $false
$lblFooter.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($lblFooter)

# --- slider painting -----------------------------------------------------
$script:sliderDrag = $false
$script:drawSlider = {
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $pad = S 8
    $w = $s.Width - $pad * 2
    $cy = [int]($s.Height / 2)
    $th = [Math]::Max(3, (S 4))
    $p = ($script:sliderVal - 50) / 50.0
    $penT = New-Object System.Drawing.Pen $trackC, $th
    $penT.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $penT.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($penT, $pad, $cy, ($s.Width - $pad), $cy)
    $penT.Dispose()
    $fx = $pad + $w * $p
    $penF = New-Object System.Drawing.Pen $green, $th
    $penF.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $penF.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($penF, $pad, $cy, $fx, $cy)
    $penF.Dispose()
    $k = [Math]::Max(8, (S 12))
    $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(242, 242, 242))
    $g.FillEllipse($b, ($fx - $k / 2), ($cy - $k / 2), $k, $k)
    $b.Dispose()
}
$script:setOpacity = {
    param($xPos)
    $pad = S 8
    $w = $slider.Width - $pad * 2
    $p = ($xPos - $pad) / [double]$w
    if ($p -lt 0) { $p = 0 }
    if ($p -gt 1) { $p = 1 }
    $v = [int][Math]::Round(50 + $p * 50)
    if ($v -ne $script:sliderVal) {
        $script:sliderVal = $v
        $lblOpacityVal.Text = "$v%"
        $slider.Invalidate()
        Update-Preview
        Save-Overlay
    }
}
$slider.Add_Paint($script:drawSlider)
$slider.Add_MouseDown({ param($s, $e) $script:sliderDrag = $true; & $script:setOpacity $e.X })
$slider.Add_MouseMove({ param($s, $e) if ($script:sliderDrag) { & $script:setOpacity $e.X } })
$slider.Add_MouseUp({ $script:sliderDrag = $false })

# --- state ---------------------------------------------------------------
function Update-Preview {
    $L = $script:L[$script:lang]
    $dims = @{ small = @(160, 64); medium = @(210, 84); large = @(260, 104) }
    $d = $dims[$script:sizeKey]
    $posName = @{ topright = $L.posTR; topleft = $L.posTL; bottomright = $L.posBR }[$script:posKey]
    $lblPreview.Text = $L.preview -f $d[0], $d[1], $script:sliderVal, $posName
}
# Show what "follow the display" resolves to right now (60 Hz screens land on
# 60, i.e. no unlock at all - worth knowing before clicking unlock).
function Update-TierLabel {
    $hz = Get-MaxHz
    $tier = 30
    if ($hz -ge 120) { $tier = 120 } elseif ($hz -ge 60) { $tier = 60 }
    if ($script:lang -eq 'zh') {
        $txt = (($script:L.zh.tierAuto) + ' · ' + $tier)
    } else {
        $txt = (($script:L.en.tierAuto) + ' · ' + $tier)
    }
    if ($pillTierAuto.Text -ne $txt) { $pillTierAuto.Text = $txt }
}

function Update-Pills {
    Style-Pill $pillTier120  ($script:tierKey -eq '120')
    Style-Pill $pillTierAuto ($script:tierKey -eq 'auto')
    Style-Pill $pillS  ($script:sizeKey -eq 'small')
    Style-Pill $pillM  ($script:sizeKey -eq 'medium')
    Style-Pill $pillL  ($script:sizeKey -eq 'large')
    Style-Pill $pillTR ($script:posKey -eq 'topright')
    Style-Pill $pillTL ($script:posKey -eq 'topleft')
    Style-Pill $pillBR ($script:posKey -eq 'bottomright')
}
function Test-HasBackup {
    # A backup exists if any client's original value was saved. The single
    # backup.b64 written by older builds only counts for the Global client.
    $dir = Join-Path $env:LOCALAPPDATA 'star-rail-120fps'
    foreach ($f in @('backup-global.b64', 'backup-cn.b64', 'backup.b64')) {
        if (Test-Path (Join-Path $dir $f)) { return $true }
    }
    return $false
}

function Refresh-Status {
    $L = $script:L[$script:lang]
    $info = Get-FpsInfo
    $run = Test-GameRunning

    # The hero shows a bare number with a small caption above it. A combined
    # "120 / 60" in 30pt does not fit, and the client line below already
    # carries the detail of which client sits at which cap.
    $caps = @($info.clients | Where-Object { $null -ne $_.fps } | ForEach-Object { $_.fps })
    $distinct = @($caps | Select-Object -Unique)
    if ($distinct.Count -gt 1) {
        $lblHeroLabel.Text = $L.heroMismatch
        $lblState.Text = [string](($caps | Measure-Object -Minimum).Minimum)
        $lblState.ForeColor = $amber
    } elseif ($info.fps -eq 120) {
        $lblHeroLabel.Text = $L.heroUnlocked
        $lblState.Text = '120'; $lblState.ForeColor = $green
    } elseif ($info.fps -eq 60) {
        $lblHeroLabel.Text = $L.heroDefault
        $lblState.Text = '60'; $lblState.ForeColor = $fg
    } elseif ($null -ne $info.fps) {
        $lblHeroLabel.Text = $L.heroUnknown
        $lblState.Text = [string]$info.fps; $lblState.ForeColor = $amber
    } else {
        $lblHeroLabel.Text = $L.heroNone
        $lblState.Text = '--'; $lblState.ForeColor = $amber
    }
    $lblStateUnit.Text = if ($null -eq $info.fps) { '' } else { 'FPS' }

    # Client fact: name both when both are installed, and show each cap when
    # they disagree so nobody has to guess which one is still at 60.
    if ($distinct.Count -gt 1) {
        $pairs = @($info.clients | Where-Object { $null -ne $_.fps } | ForEach-Object {
            $who = if ($_.key -eq 'cn') { $L.clientCN } else { $L.clientGlobal }
            $who + ' ' + $_.fps
        })
        $script:factV['Client'].Text = ($pairs -join ' · ')
        $script:factV['Client'].ForeColor = $amber
    } elseif ($info.client -eq 'both') {
        $script:factV['Client'].Text = $L.clientBoth; $script:factV['Client'].ForeColor = $fg
    } elseif ($info.client -eq 'global') {
        $script:factV['Client'].Text = $L.clientGlobal; $script:factV['Client'].ForeColor = $fg
    } elseif ($info.client -eq 'cn') {
        $script:factV['Client'].Text = $L.clientCN; $script:factV['Client'].ForeColor = $fg
    } else {
        $script:factV['Client'].Text = $L.valClientNA; $script:factV['Client'].ForeColor = $amber
    }

    $hz = Get-MaxHz
    if ($hz -gt 0) { $script:factV['Hz'].Text = $L.valHz -f $hz } else { $script:factV['Hz'].Text = '--' }
    $script:factV['Hz'].ForeColor = $dim

    if ($run) {
        $script:factV['Game'].Text = $L.valGameOn; $script:factV['Game'].ForeColor = $amber
    } else {
        $script:factV['Game'].Text = $L.valGameOff; $script:factV['Game'].ForeColor = $dim
    }

    if (Test-HasBackup) {
        $script:factV['Backup'].Text = $L.valBackupOk; $script:factV['Backup'].ForeColor = $green
    } else {
        $script:factV['Backup'].Text = $L.valBackupNo; $script:factV['Backup'].ForeColor = $dim
    }

    try { Update-TierLabel } catch { }
}
function Apply-Language {
    $L = $script:L[$script:lang]
    $form.Text = $L.winTitle
    $lblTitle.Text = $L.title
    $lblSub.Text = $L.subtitle
    $btnOn.Text = $L.btnOn
    $btnOff.Text = $L.btnOff
    $lblOvTitle.Text = $L.ovTitle
    Sync-OverlayButton
    $lblOpacity.Text = $L.opacity
    $lblSize.Text = $L.size
    $lblPos.Text = $L.position
    $pillS.Text = $L.szS
    $pillM.Text = $L.szM
    $pillL.Text = $L.szL
    $pillTR.Text = $L.posTR
    $pillTL.Text = $L.posTL
    $pillBR.Text = $L.posBR
    $lblNotesTitle.Text = $L.notesTitle
    $lblNotes.Text = ($L.notes -join "`n")
    $lblFooter.Text = $L.footer
    $script:factK['Client'].Text = $L.factClient
    $script:factK['Hz'].Text     = $L.factHz
    $script:factK['Game'].Text   = $L.factGame
    $script:factK['Backup'].Text = $L.factBackup
    $lblTier.Text = $L.tierTitle
    $pillTier120.Text = $L.tier120
    Update-TierLabel
    $lblAuto.Text = $L.autoTitle
    Sync-AutoStart
    Style-Pill $pillAuto $script:autoStart
    if ($script:autoStart) { $pillAuto.Text = $L.autoOn } else { $pillAuto.Text = $L.autoOff }

    if ($script:lang -eq 'zh') {
        Style-Pill $btnZh $true
        Style-Pill $btnEn $false
    } else {
        Style-Pill $btnEn $true
        Style-Pill $btnZh $false
    }

    $lblOpacityVal.Text = "$($script:sliderVal)%"
    Update-Pills
    Update-Preview
    Refresh-Status
}
function Invoke-Cap([string]$mode) {
    $btnOn.Enabled = $false
    $btnOff.Enabled = $false
    try {
        $capArgs = @('-Mode', $mode)
        if ($mode -eq 'unlock' -and $script:tierKey -eq 'auto') { $capArgs += '-Auto' }
        $out = & $script:capScript @capArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } catch {
        $out = $_.Exception.Message
        $code = 1
    }
    $btnOn.Enabled = $true
    $btnOff.Enabled = $true
    Refresh-Status
    if ($code -ne 0) {
        $L = $script:L[$script:lang]
        [System.Windows.Forms.MessageBox]::Show($out.Trim(), $L.errTitle, 'OK', 'Warning') | Out-Null
    }
}

$btnOn.Add_Click({ Invoke-Cap 'unlock' })
$btnOff.Add_Click({ Invoke-Cap 'restore' })
$btnZh.Add_Click({ $script:lang = 'zh'; Apply-Language })
$btnEn.Add_Click({ $script:lang = 'en'; Apply-Language })
$btnOvLaunch.Add_Click({
    if (Test-OverlayRunning) { Stop-Overlay }
    elseif (Test-Path $script:monBat) { Start-Process -FilePath $script:monBat }
    # No Start-Sleep here: this runs on the UI thread, and the overlay needs a
    # moment to write its PID file anyway. The 2s timer corrects the label.
    Sync-OverlayButton
})
$pillAuto.Add_Click({
    $L = $script:L[$script:lang]
    if ($script:autoStart) {
        [void](Disable-AutoStart)
    } else {
        if (-not (Enable-AutoStart)) {
            [System.Windows.Forms.MessageBox]::Show($L.autoFail, $L.errTitle, 'OK', 'Warning') | Out-Null
            return
        }
    }
    Sync-AutoStart
    Style-Pill $pillAuto $script:autoStart
    if ($script:autoStart) { $pillAuto.Text = $L.autoOn } else { $pillAuto.Text = $L.autoOff }
})
$pillTier120.Add_Click({  $script:tierKey = '120';  Update-Pills; Save-Overlay })
$pillTierAuto.Add_Click({ $script:tierKey = 'auto'; Update-Pills; Save-Overlay })
$pillS.Add_Click({ $script:sizeKey = 'small';   Update-Pills; Update-Preview; Save-Overlay })
$pillM.Add_Click({ $script:sizeKey = 'medium';  Update-Pills; Update-Preview; Save-Overlay })
$pillL.Add_Click({ $script:sizeKey = 'large';   Update-Pills; Update-Preview; Save-Overlay })
# picking a corner discards any position the user dragged the overlay to,
# otherwise the saved coordinates would keep overriding the preset
function Clear-DraggedPos {
    try {
        $p = Join-Path $script:ovDir 'position.json'
        if (Test-Path $p) { Remove-Item $p -Force }
    } catch { }
}
$pillTR.Add_Click({ $script:posKey = 'topright';    Clear-DraggedPos; Update-Pills; Update-Preview; Save-Overlay })
$pillTL.Add_Click({ $script:posKey = 'topleft';     Clear-DraggedPos; Update-Pills; Update-Preview; Save-Overlay })
$pillBR.Add_Click({ $script:posKey = 'bottomright'; Clear-DraggedPos; Update-Pills; Update-Preview; Save-Overlay })

Load-Overlay

# Live status: without this the "game is running" warning would stay on screen
# after the user closes the game.
$script:refreshTimer = New-Object System.Windows.Forms.Timer
$script:refreshTimer.Interval = 2000
$script:refreshTimer.Add_Tick({ try { Refresh-Status } catch { }; try { Sync-OverlayButton } catch { } })

$form.Add_Shown({
    [void](Get-MaxHz)                 # warm the WMI query before the first timer tick
    Apply-Language
    if (-not (Test-Path $script:ovFile)) { Save-Overlay }
    $script:refreshTimer.Start()
})
$form.Add_FormClosed({ try { $script:refreshTimer.Stop() } catch { } })

[void]$form.ShowDialog()
exit 0
