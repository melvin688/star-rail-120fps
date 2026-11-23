# Remove Star Rail 120 FPS Tool and its shortcuts.
# The game's own registry setting is NOT touched - run RESTORE-60FPS.bat first if you want 60 FPS back.

$ErrorActionPreference = 'Continue'

$dest = Join-Path $env:LOCALAPPDATA 'StarRail120FPS'
$name = '星穹铁道 120帧.lnk'

Write-Host ''
Write-Host '  Star Rail 120 FPS Tool - uninstaller' -ForegroundColor Yellow
Write-Host '  ------------------------------------'
Write-Host ''

$places = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
)
foreach ($dir in $places) {
    $lnk = Join-Path $dir $name
    if (Test-Path $lnk) {
        Remove-Item $lnk -Force -ErrorAction SilentlyContinue
        Write-Host "  removed shortcut: $lnk"
    }
}

# the "start with the game" watcher: stop it and drop its Startup entry
$startupLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\StarRail120FPS-Agent.lnk'
if (Test-Path $startupLnk) {
    Remove-Item $startupLnk -Force -ErrorAction SilentlyContinue
    Write-Host "  removed startup entry: $startupLnk"
}
$watcher = Join-Path $dest 'scripts\game-watch.ps1'
if (Test-Path $watcher) {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $watcher + '" -Stop') `
        -WindowStyle Hidden -Wait
    Write-Host '  stopped the game watcher (if it was running)'
}

if (Test-Path $dest) {
    Write-Host "  removing $dest ..."
    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $dest) {
        Write-Host '  could not remove everything (a file may be open). Close the tool and run this again.' -ForegroundColor Yellow
    } else {
        Write-Host '  program files removed.' -ForegroundColor Green
    }
} else {
    Write-Host '  program files already gone.'
}

Write-Host ''
Write-Host '  --- this uninstaller did NOT change ---' -ForegroundColor Cyan
Write-Host '  the game registry setting (FPS 120 stays until you change it)'
Write-Host '  >>> to go back to 60 FPS: run RESTORE-60FPS.bat BEFORE uninstalling, or edit the in-game option'
Write-Host ''
Write-Host '  if you added yourself to "Performance Log Users" earlier, undo it in an admin prompt:' -ForegroundColor Cyan
Write-Host '      net localgroup "Performance Log Users" %USERNAME% /delete'
Write-Host ''
Read-Host '  Press Enter to close'
