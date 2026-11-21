@echo off
setlocal
title Star Rail - set 120 FPS cap
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\fps-cap.ps1" -Mode unlock
echo.
pause
