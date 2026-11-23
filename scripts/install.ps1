# Install Star Rail 120 FPS Tool into %LOCALAPPDATA% and create shortcuts.
# Nothing is written outside the user profile: no services, no system files, no auto-start entries.

$ErrorActionPreference = 'Stop'

$src  = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'StarRail120FPS'

function Say($zh, $en) { Write-Host "  $zh" ; Write-Host "  $en" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '  Star Rail 120 FPS Tool - installer' -ForegroundColor Green
Write-Host '  ----------------------------------'
Write-Host ''

if (-not (Test-Path (Join-Path $src 'StarRail-120FPS.bat'))) {
    Write-Host "  ERROR: run this from the unpacked repository folder." -ForegroundColor Red
    Write-Host '  错误：请先解压整个仓库，再从解压出来的文件夹里运行本安装。' -ForegroundColor Red
    Read-Host '  Press Enter to exit'
    exit 1
}

if ($dest -ieq $src) {
    Write-Host "  Already running from the install location ($dest) - skipping copy." -ForegroundColor Yellow
} else {
    Write-Host "  installing to: $dest"
    if (Test-Path $dest) {
        Write-Host '  removing previous copy...'
        try { Remove-Item $dest -Recurse -Force -ErrorAction Stop }
        catch {
            # A running GUI/overlay keeps its files locked. Say so instead of
            # failing later with a confusing "directory already exists".
            Write-Host ''
            Write-Host '  The previous copy is still in use - close the tool first:' -ForegroundColor Yellow
            Write-Host '    * close the Star Rail 120 FPS window (or its tray icon)' -ForegroundColor Yellow
            Write-Host '    * close the FPS overlay (Ctrl+Alt+F) if it is on screen' -ForegroundColor Yellow
            Write-Host '  Then run INSTALL.bat again.' -ForegroundColor Yellow
            Write-Host ''
            exit 1
        }
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    # Copy every file in the repository root (bat / vbs / md / LICENSE ...),
    # then the script and tool folders. Listing files by hand used to mean a
    # forgotten file silently broke a feature after an update.
    Get-ChildItem -Path $src -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
    }
    foreach ($d in @('scripts', 'tools')) {
        $p = Join-Path $src $d
        if (Test-Path $p) { Copy-Item $p $dest -Recurse -Force }
    }
    $ico = Join-Path $src 'docs\app.ico'
    if (Test-Path $ico) { Copy-Item $ico $dest -Force }
}

# --- shortcuts -------------------------------------------------------------
$ws = New-Object -ComObject WScript.Shell
$target = Join-Path $dest 'StarRail-120FPS.bat'
$icon   = Join-Path $dest 'app.ico'
$name   = '星穹铁道 120帧.lnk'

$places = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
)
foreach ($dir in $places) {
    if (-not (Test-Path $dir)) { continue }
    $lnkPath = Join-Path $dir $name
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath        = $target
    $lnk.WorkingDirectory  = $dest
    $lnk.Description       = '星穹铁道 120 帧解锁 + 帧率小窗'
    if (Test-Path $icon) { $lnk.IconLocation = "$icon,0" }
    $lnk.WindowStyle       = 1
    $lnk.Save()
    Write-Host "  shortcut: $lnkPath"
}

Write-Host ''
Write-Host '  done.' -ForegroundColor Green
Say '已安装完成，桌面和开始菜单都有「星穹铁道 120帧」图标。' 'Installed. Look for "星穹铁道 120帧" on your desktop and in the Start menu.'
Write-Host ''
Write-Host '  --- what was installed ---' -ForegroundColor Cyan
Say "仅复制了程序文件到 $dest" "Only program files were copied to $dest"
Say '没有安装服务、没有写系统目录、没有添加开机自启项' 'No services, no system directories, no auto-start entries'
Say '唯一的 exe 是 Intel 官方 PresentMon（帧率小窗取数用），仓库自带' 'The only exe is Intel PresentMon, bundled for the FPS overlay'
Write-Host ''
Write-Host '  --- next steps ---' -ForegroundColor Cyan
Say '1. 双击桌面图标，点「开启 120 FPS」' '1. Open the desktop shortcut and click "开启 120 FPS"'
Say '2. 想显示帧率：卡片里调好样式，点「启动小窗 →」，授权一次' '2. For the FPS overlay: adjust the card, click "启动小窗 →", approve once'
Say '3. 想免掉每次授权：见 README 的 Performance Log Users 一节' '3. To skip the UAC prompt: see the Performance Log Users section in README'
Write-Host ''
Read-Host '  Press Enter to close'
