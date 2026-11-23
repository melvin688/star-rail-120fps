@echo off
setlocal
title Star Rail - FPS monitor

net session >nul 2>&1
if %errorlevel% equ 0 goto run

rem member of "Performance Log Users" (SID S-1-5-32-559)? that group can read
rem system frame events without elevation, so skip the UAC prompt entirely
powershell -NoProfile -Command "try { $m = Get-LocalGroupMember -SID S-1-5-32-559 -ErrorAction Stop; foreach ($x in $m) { if ($x.Name -match [regex]::Escape($env:USERNAME)) { exit 0 } } } catch { }; exit 1" >nul 2>&1
if %errorlevel% equ 0 goto run

echo Requesting administrator rights ^(needed once to read system frame events^)...
echo Tip: run ENABLE-NO-UAC.bat once to skip this prompt from now on.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -WindowStyle Minimized"
exit /b

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\fps-monitor.ps1" %*
if errorlevel 1 pause
