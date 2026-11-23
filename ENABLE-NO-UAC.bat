@echo off
setlocal
title Star Rail 120 FPS - skip the UAC prompt

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Adding "%USERNAME%" to the "Performance Log Users" group...
echo.
net localgroup "Performance Log Users" "%USERNAME%" /add >nul 2>&1
if %errorlevel% equ 0 (
    echo Done. The FPS overlay will now start WITHOUT a UAC prompt.
    echo Sign out and sign back in once so the new group membership applies.
) else (
    echo Nothing changed - the account is most likely already a member.
    echo If the overlay still asks for administrator rights, sign out and back in once.
)
echo.
echo To undo:  net localgroup "Performance Log Users" "%USERNAME%" /delete
echo.
pause
