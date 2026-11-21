@echo off
setlocal enabledelayedexpansion
title Clean up leftover PresentMon processes
set SYS=%SystemRoot%\System32

echo Checking for leftover PresentMon capture processes...
echo.

set FOUND=0
for %%E in (PresentMon-2.6.0-x64.exe PresentMon-x64.exe PresentMon.exe) do (
  "%SYS%\tasklist.exe" /FI "IMAGENAME eq %%E" 2>nul | "%SYS%\find.exe" /I "%%E" >nul
  if not errorlevel 1 (
    echo   found: %%E
    set FOUND=1
  )
)

if "%FOUND%"=="0" (
  echo   nothing to clean up - no leftover capture process is running.
  echo.
  goto footer
)

"%SYS%\net.exe" session >nul 2>&1
if errorlevel 1 (
  echo   administrator rights required, asking for elevation...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
  exit /b
)

echo.
echo   stopping leftover processes...
for %%E in (PresentMon-2.6.0-x64.exe PresentMon-x64.exe PresentMon.exe) do (
  "%SYS%\taskkill.exe" /F /IM "%%E" >nul 2>&1
)
echo   done.

:footer
echo.
echo Note: the Windows service "PresentMonSharedService" is an Intel component
echo installed by the official PresentMon installer. This script does not touch it.
echo It is harmless and idle nearly all the time. To stop it starting with Windows:
echo     sc config PresentMonSharedService start= demand
echo.
pause
