# Star Rail 120 FPS tool - bilingual (zh/en) dark GUI front-end
# PowerShell 5.1, dependency-free. Wraps scripts\fps-cap.ps1.
param(
    [ValidateSet('zh', 'en')]
    [string]$Lang = 'zh'
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$script:root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path (Join-Path $script:root 'scripts\fps-cap.ps1'))) {
    $script:root = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:capScript = Join-Path $script:root 'scripts\fps-cap.ps1'
$script:monBat    = Join-Path $script:root 'FPS-MONITOR.bat'
$script:lang      = $Lang

# --- string tables -------------------------------------------------------
$script:L = @{}
$script:L.zh = @{
    winTitle   = 'Star Rail 120 FPS 工具'
    title      = '星穹铁道 120 帧工具'
    subtitle   = '解锁官方隐藏的 120 FPS 档位 · 只修改游戏自己的设置值'
    st120      = '当前状态：已解锁 120 FPS'
    st60       = '当前状态：官方默认 60 FPS'
    stUnknown  = '当前状态：检测到未知值 {0}'
    stNone     = '当前状态：未找到游戏设置'
    clientLine = '客户端：{0} · 已自动备份原值（可在恢复时还原）'
    clientNA   = '客户端：未检测到（运行过游戏后出现）'
    clientGlobal = '国际服'
    clientCN   = '国服'
    gameOn     = '⚠ 游戏正在运行：请先完全退出游戏，再点「开启/恢复」'
    gameOff    = '游戏未运行 · 可以安全操作'
    btnOn      = '开启 120 FPS'
    btnOff     = '恢复 60 FPS（官方默认）'
    notesTitle = '注意事项'
    notes      = @(
        '· 操作前请先完全退出游戏（游戏运行中修改会被覆盖）',
        '· 解锁后请勿再动游戏内画面/帧率设置，否则会重置回 60',
        '· 游戏设置界面显示 30/60 是正常现象，请以外置帧率工具为准',
        '· 想还原官方默认：随时点「恢复 60 FPS」',
        '· 备份在本机 %LOCALAPPDATA%\star-rail-120fps\，可放心折腾'
    )
    btnMon     = '启动帧率小窗（首次需管理员授权）'
    errTitle   = '操作未完成'
}
$script:L.en = @{
    winTitle   = 'Star Rail 120 FPS Tool'
    title      = 'Star Rail 120 FPS Tool'
    subtitle   = 'Unlocks the hidden 120 FPS option - safe & reversible'
    st120      = 'Status: Unlocked - 120 FPS'
    st60       = 'Status: Official default - 60 FPS'
    stUnknown  = 'Status: unknown value {0}'
    stNone     = 'Status: game settings not found'
    clientLine = 'Client: {0} - original value backed up (restorable)'
    clientNA   = 'Client: not detected (appears after you run the game once)'
    clientGlobal = 'Global'
    clientCN   = 'China'
    gameOn     = 'Game is running - fully exit it before unlock/restore'
    gameOff    = 'Game not running - safe to proceed'
    btnOn      = 'Unlock 120 FPS'
    btnOff     = 'Restore 60 FPS (default)'
    notesTitle = 'Notes'
    notes      = @(
        '· Exit the game fully first (in-game changes overwrite this)',
        '· Do not touch in-game graphics/FPS settings after unlocking',
        '· In-game menu still showing 30/60 is normal; trust the counter',
        '· Restore the official default anytime: "Restore 60 FPS"',
        '· Backup kept in %LOCALAPPDATA%\star-rail-120fps\'
    )
    btnMon     = 'Launch FPS overlay (one-time admin prompt)'
    errTitle   = 'Action not completed'
}

# --- registry helpers ----------------------------------------------------
function Get-FpsInfo {
    # returns @{ fps = int|null; client = 'global'|'cn'|null }
    $candidates = @(
        @{ path = 'Software\Cognosphere\Star Rail';   key = 'global' },
        @{ path = 'Software\miHoYo\崩坏：星穹铁道'; key = 'cn' }
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
                if ($m.Success) {
                    return @{ fps = [int]$m.Groups[1].Value; client = $c.key }
                }
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

# --- palette -------------------------------------------------------------
$bg     = [System.Drawing.Color]::FromArgb(18, 18, 18)
$card   = [System.Drawing.Color]::FromArgb(28, 28, 31)
$fg     = [System.Drawing.Color]::FromArgb(236, 236, 236)
$dim    = [System.Drawing.Color]::FromArgb(150, 150, 150)
$green  = [System.Drawing.Color]::FromArgb(110, 230, 140)
$amber  = [System.Drawing.Color]::FromArgb(240, 210, 90)
$red    = [System.Drawing.Color]::FromArgb(240, 100, 100)
$btnBg  = [System.Drawing.Color]::FromArgb(40, 40, 44)
$btnBrd = [System.Drawing.Color]::FromArgb(80, 80, 86)
$selBg  = [System.Drawing.Color]::FromArgb(70, 70, 78)
$selBrd = [System.Drawing.Color]::FromArgb(138, 138, 150)
$F = 'Microsoft YaHei UI'

$form = New-Object System.Windows.Forms.Form
$form.ClientSize = New-Object System.Drawing.Size(460, 520)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $bg
$form.ForeColor = $fg
$form.Font = New-Object System.Drawing.Font($F, 10)

function New-Lbl([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [float]$size, $color, [bool]$bold, $parent) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $st = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font = New-Object System.Drawing.Font($F, $size, $st)
    $l.ForeColor = $color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $parent.Controls.Add($l)
    return $l
}
function New-FlatBtn([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [float]$size, [bool]$bold, $parent) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = $btnBg
    $b.ForeColor = $fg
    $st = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $b.Font = New-Object System.Drawing.Font($F, $size, $st)
    $b.FlatAppearance.BorderColor = $btnBrd
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(50, 50, 55)
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(34, 34, 38)
    $parent.Controls.Add($b)
    return $b
}

$lblTitle = New-Lbl '' 20 14 320 36 15 $fg $true $form
$lblSub   = New-Lbl '' 20 50 420 22 9 $dim $false $form

# language selector (top-right)
$btnZh = New-FlatBtn '中文' 348 20 42 28 9 $false $form
$btnEn = New-FlatBtn 'EN'   392 20 48 28 9 $false $form

# --- status card ---------------------------------------------------------
$card1 = New-Object System.Windows.Forms.Panel
$card1.Location = New-Object System.Drawing.Point(20, 84)
$card1.Size = New-Object System.Drawing.Size(420, 96)
$card1.BackColor = $card
$form.Controls.Add($card1)

$lblState  = New-Lbl '' 16 12 388 30 12 $fg $true $card1
$lblDetail = New-Lbl '' 16 46 388 20 9 $dim $false $card1
$lblGame   = New-Lbl '' 16 66 388 20 9 $amber $false $card1

# --- action buttons ------------------------------------------------------
$btnOn  = New-FlatBtn '' 20 196 204 46 11 $true $form
$btnOff = New-FlatBtn '' 236 196 204 46 11 $false $form
$btnOn.BackColor = [System.Drawing.Color]::FromArgb(30, 48, 36)
$btnOn.ForeColor = $green
$btnOn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 120, 80)
$btnOn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 62, 46)
$btnOn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(24, 40, 30)

# --- notes card ----------------------------------------------------------
$card2 = New-Object System.Windows.Forms.Panel
$card2.Location = New-Object System.Drawing.Point(20, 256)
$card2.Size = New-Object System.Drawing.Size(420, 190)
$card2.BackColor = $card
$form.Controls.Add($card2)

$lblNotesTitle = New-Lbl '' 16 10 388 24 10 $fg $true $card2
$lblNotes      = New-Lbl '' 16 38 388 142 9 $dim $false $card2

# --- fps monitor button --------------------------------------------------
$btnMon = New-FlatBtn '' 20 456 420 42 10 $false $form

# --- behavior ------------------------------------------------------------
function Refresh-Status {
    $L = $script:L[$script:lang]
    $info = Get-FpsInfo
    $run = Test-GameRunning

    if ($info.fps -eq 120) {
        $lblState.Text = $L.st120
        $lblState.ForeColor = $green
    } elseif ($info.fps -eq 60) {
        $lblState.Text = $L.st60
        $lblState.ForeColor = $fg
    } elseif ($null -ne $info.fps) {
        $lblState.Text = $L.stUnknown -f $info.fps
        $lblState.ForeColor = $amber
    } else {
        $lblState.Text = $L.stNone
        $lblState.ForeColor = $amber
    }

    if ($info.client -eq 'global') { $lblDetail.Text = $L.clientLine -f $L.clientGlobal }
    elseif ($info.client -eq 'cn') { $lblDetail.Text = $L.clientLine -f $L.clientCN }
    else                           { $lblDetail.Text = $L.clientNA }

    if ($run) {
        $lblGame.Text = $L.gameOn
        $lblGame.ForeColor = $amber
    } else {
        $lblGame.Text = $L.gameOff
        $lblGame.ForeColor = $dim
    }
}

function Apply-Language {
    $L = $script:L[$script:lang]
    $form.Text = $L.winTitle
    $lblTitle.Text = $L.title
    $lblSub.Text = $L.subtitle
    $btnOn.Text = $L.btnOn
    $btnOff.Text = $L.btnOff
    $lblNotesTitle.Text = $L.notesTitle
    $lblNotes.Text = ($L.notes -join "`n")
    $btnMon.Text = $L.btnMon

    if ($script:lang -eq 'zh') {
        $btnZh.BackColor = $selBg;  $btnZh.ForeColor = $fg;  $btnZh.FlatAppearance.BorderColor = $selBrd
        $btnEn.BackColor = $btnBg;  $btnEn.ForeColor = $dim; $btnEn.FlatAppearance.BorderColor = $btnBrd
    } else {
        $btnEn.BackColor = $selBg;  $btnEn.ForeColor = $fg;  $btnEn.FlatAppearance.BorderColor = $selBrd
        $btnZh.BackColor = $btnBg;  $btnZh.ForeColor = $dim; $btnZh.FlatAppearance.BorderColor = $btnBrd
    }
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
$btnMon.Add_Click({
    if (Test-Path $script:monBat) { Start-Process -FilePath $script:monBat }
})
$form.Add_Shown({ Apply-Language })

[void]$form.ShowDialog()
exit 0
