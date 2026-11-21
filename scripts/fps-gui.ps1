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
    gameOn     = '游戏正在运行：请先完全退出游戏，再点「开启/恢复」'
    gameOff    = '游戏未运行 · 可以安全操作'
    btnOn      = '开启 120 FPS'
    btnOff     = '恢复 60 FPS'
    ovTitle    = '帧率小窗'
    ovLaunch   = '启动小窗 →'
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
        '· 操作前请先完全退出游戏（游戏运行中修改会被覆盖）',
        '· 解锁后请勿再动游戏内画面/帧率设置，否则会重置回 60',
        '· 游戏设置界面显示 30/60 是正常现象，以帧率小窗为准',
        '· 想还原官方默认：随时点「恢复 60 FPS」',
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
    gameOn     = 'Game is running - fully exit it before unlock/restore'
    gameOff    = 'Game not running - safe to proceed'
    btnOn      = 'Unlock 120 FPS'
    btnOff     = 'Restore 60 FPS'
    ovTitle    = 'FPS overlay'
    ovLaunch   = 'Launch →'
    opacity    = 'Opacity'
    size       = 'Size'
    position   = 'Position'
    szS        = 'Small'
    szM        = 'Med'
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
    foreach ($c in $candidates) {
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($c.path)
        if ($null -eq $k) { continue }
        foreach ($v in $k.GetValueNames()) {
            if ($v -like 'GraphicsSettings_Model_h*') {
                $b = $k.GetValue($v)
                if ($null -eq $b) { continue }
                $t = [System.Text.Encoding]::UTF8.GetString($b)
                $m = [regex]::Match($t, '"FPS"\s*:\s*(\d+)')
                if ($m.Success) { return @{ fps = [int]$m.Groups[1].Value; client = $c.key } }
            }
        }
    }
    foreach ($c in $candidates) {
        if ($null -ne [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($c.path)) {
            return @{ fps = $null; client = $c.key }
        }
    }
    return @{ fps = $null; client = $null }
}
function Test-GameRunning { return [bool](Get-Process StarRail -ErrorAction SilentlyContinue) }

# --- overlay settings (shared with fps-monitor.ps1) ----------------------
$script:sliderVal = 90
$script:sizeKey   = 'medium'
$script:posKey    = 'topright'
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
    } catch { }
}
function Save-Overlay {
    try {
        if (-not (Test-Path $script:ovDir)) { New-Item -ItemType Directory -Path $script:ovDir -Force | Out-Null }
        $o = [ordered]@{
            opacity  = [Math]::Round($script:sliderVal / 100.0, 2)
            size     = $script:sizeKey
            position = $script:posKey
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
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $bg
$form.ForeColor = $fg
$form.Font = New-Object System.Drawing.Font($F, (FS 10))

$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$desW = S 460
$desH = S 640
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
$lblTitle = New-Lbl '' (S 24) (S 16) (S 300) (S 30) 16 $fg $true; $form.Controls.Add($lblTitle)
$lblSub   = New-Lbl '' (S 24) (S 50) (S 412) (S 18) 8.5 $dim $false; $form.Controls.Add($lblSub)
$btnZh = New-Pill (S 344) (S 20) (S 44) (S 26); $btnZh.Text = '中文'; $form.Controls.Add($btnZh)
$btnEn = New-Pill (S 394) (S 20) (S 42) (S 26); $btnEn.Text = 'EN';   $form.Controls.Add($btnEn)

# status card
$card1 = New-Object System.Windows.Forms.Panel
$card1.Location = New-Object System.Drawing.Point((S 24), (S 86))
$card1.Size = New-Object System.Drawing.Size((S 412), (S 96))
$card1.BackColor = $card
$form.Controls.Add($card1)

$lblDot    = New-Lbl '●' (S 20) (S 10) (S 16) (S 20) 9 $green $false; $card1.Controls.Add($lblDot)
$lblState  = New-Lbl ''  (S 40) (S 6)  (S 356) (S 26) 13 $fg $true;   $card1.Controls.Add($lblState)
$lblDetail = New-Lbl ''  (S 20) (S 42) (S 372) (S 18) 8.5 $dim $false; $card1.Controls.Add($lblDetail)
$lblGame   = New-Lbl ''  (S 20) (S 62) (S 372) (S 18) 8.5 $dim $false; $card1.Controls.Add($lblGame)

# action buttons
$btnOn  = New-FlatBtn '' (S 24) (S 198) (S 196) (S 44) 11 $true;  $form.Controls.Add($btnOn)
$btnOff = New-FlatBtn '' (S 240) (S 198) (S 196) (S 44) 10.5 $false; $form.Controls.Add($btnOff)
$btnOn.BackColor = [System.Drawing.Color]::FromArgb(30, 48, 36)
$btnOn.ForeColor = $green
$btnOn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 120, 80)
$btnOn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 62, 46)
$btnOn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(24, 40, 30)

# overlay settings card
$card2 = New-Object System.Windows.Forms.Panel
$card2.Location = New-Object System.Drawing.Point((S 24), (S 262))
$card2.Size = New-Object System.Drawing.Size((S 412), (S 192))
$card2.BackColor = $card
$form.Controls.Add($card2)

$lblOvTitle = New-Lbl '' (S 18) (S 14) (S 200) (S 22) 11 $fg $true; $card2.Controls.Add($lblOvTitle)
$btnOvLaunch = New-FlatBtn '' (S 250) (S 10) (S 144) (S 26) 9 $false
$btnOvLaunch.BackColor = $card
$btnOvLaunch.ForeColor = $green
$btnOvLaunch.FlatAppearance.BorderColor = $card
$btnOvLaunch.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(36, 36, 40)
$card2.Controls.Add($btnOvLaunch)

$lblOpacity    = New-Lbl '' (S 18) (S 48) (S 80) (S 18) 8.5 $dim $false; $card2.Controls.Add($lblOpacity)
$lblOpacityVal = New-Lbl '' (S 318) (S 46) (S 60) (S 18) 9 $fg $true;    $card2.Controls.Add($lblOpacityVal)

$slider = New-Object System.Windows.Forms.Panel
$slider.Location = New-Object System.Drawing.Point((S 96), (S 44))
$slider.Size = New-Object System.Drawing.Size((S 216), (S 26))
$slider.BackColor = $card
$card2.Controls.Add($slider)

$lblSize = New-Lbl '' (S 18) (S 84) (S 80) (S 18) 8.5 $dim $false; $card2.Controls.Add($lblSize)
$pillS = New-Pill (S 96) (S 78) (S 56) (S 26); $card2.Controls.Add($pillS)
$pillM = New-Pill (S 156) (S 78) (S 56) (S 26); $card2.Controls.Add($pillM)
$pillL = New-Pill (S 216) (S 78) (S 56) (S 26); $card2.Controls.Add($pillL)

$lblPos = New-Lbl '' (S 18) (S 120) (S 80) (S 18) 8.5 $dim $false; $card2.Controls.Add($lblPos)
$pillTR = New-Pill (S 96) (S 114) (S 92) (S 26); $card2.Controls.Add($pillTR)
$pillTL = New-Pill (S 196) (S 114) (S 92) (S 26); $card2.Controls.Add($pillTL)
$pillBR = New-Pill (S 296) (S 114) (S 92) (S 26); $card2.Controls.Add($pillBR)

$lblPreview = New-Lbl '' (S 18) (S 154) (S 372) (S 18) 8 $dim2 $false; $card2.Controls.Add($lblPreview)

# notes card
$card3 = New-Object System.Windows.Forms.Panel
$card3.Location = New-Object System.Drawing.Point((S 24), (S 470))
$card3.Size = New-Object System.Drawing.Size((S 412), (S 138))
$card3.BackColor = $card
$form.Controls.Add($card3)

$lblNotesTitle = New-Lbl '' (S 18) (S 12) (S 200) (S 22) 11 $fg $true; $card3.Controls.Add($lblNotesTitle)
$lblNotes = New-Lbl '' (S 18) (S 40) (S 378) (S 92) 8.5 $dim $false; $card3.Controls.Add($lblNotes)

$lblFooter = New-Lbl '' (S 24) (S 616) (S 412) (S 18) 8 $dim2 $false; $form.Controls.Add($lblFooter)

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
function Update-Pills {
    Style-Pill $pillS  ($script:sizeKey -eq 'small')
    Style-Pill $pillM  ($script:sizeKey -eq 'medium')
    Style-Pill $pillL  ($script:sizeKey -eq 'large')
    Style-Pill $pillTR ($script:posKey -eq 'topright')
    Style-Pill $pillTL ($script:posKey -eq 'topleft')
    Style-Pill $pillBR ($script:posKey -eq 'bottomright')
}
function Refresh-Status {
    $L = $script:L[$script:lang]
    $info = Get-FpsInfo
    $run = Test-GameRunning

    if ($info.fps -eq 120) {
        $lblState.Text = $L.st120; $lblState.ForeColor = $green; $lblDot.ForeColor = $green
    } elseif ($info.fps -eq 60) {
        $lblState.Text = $L.st60; $lblState.ForeColor = $fg; $lblDot.ForeColor = $green
    } elseif ($null -ne $info.fps) {
        $lblState.Text = $L.stUnknown -f $info.fps; $lblState.ForeColor = $amber; $lblDot.ForeColor = $amber
    } else {
        $lblState.Text = $L.stNone; $lblState.ForeColor = $amber; $lblDot.ForeColor = $amber
    }

    if ($info.client -eq 'global') { $lblDetail.Text = $L.clientLine -f $L.clientGlobal }
    elseif ($info.client -eq 'cn') { $lblDetail.Text = $L.clientLine -f $L.clientCN }
    else                           { $lblDetail.Text = $L.clientNA }

    if ($run) {
        $lblGame.Text = $L.gameOn; $lblGame.ForeColor = $amber
    } else {
        $lblGame.Text = $L.gameOff; $lblGame.ForeColor = $dim
    }
}
function Apply-Language {
    $L = $script:L[$script:lang]
    $form.Text = $L.winTitle
    $lblTitle.Text = $L.title
    $lblSub.Text = $L.subtitle
    $btnOn.Text = $L.btnOn
    $btnOff.Text = $L.btnOff
    $lblOvTitle.Text = $L.ovTitle
    $btnOvLaunch.Text = $L.ovLaunch
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
        $out = & $script:capScript -Mode $mode 2>&1 | Out-String
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
    if (Test-Path $script:monBat) { Start-Process -FilePath $script:monBat }
})
$pillS.Add_Click({ $script:sizeKey = 'small';   Update-Pills; Update-Preview; Save-Overlay })
$pillM.Add_Click({ $script:sizeKey = 'medium';  Update-Pills; Update-Preview; Save-Overlay })
$pillL.Add_Click({ $script:sizeKey = 'large';   Update-Pills; Update-Preview; Save-Overlay })
$pillTR.Add_Click({ $script:posKey = 'topright';    Update-Pills; Update-Preview; Save-Overlay })
$pillTL.Add_Click({ $script:posKey = 'topleft';     Update-Pills; Update-Preview; Save-Overlay })
$pillBR.Add_Click({ $script:posKey = 'bottomright'; Update-Pills; Update-Preview; Save-Overlay })

Load-Overlay
$form.Add_Shown({ Apply-Language; if (-not (Test-Path $script:ovFile)) { Save-Overlay } })

[void]$form.ShowDialog()
exit 0
