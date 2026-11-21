@echo off
setlocal
title Star Rail - FPS monitor

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights ^(needed once to read system frame events^)...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -WindowStyle Minimized"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\fps-monitor.ps1" %*
if errorlevel 1 pause
