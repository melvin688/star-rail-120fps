@echo off
setlocal
title Star Rail - restore 60 FPS cap
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\fps-cap.ps1" -Mode restore
echo.
pause
