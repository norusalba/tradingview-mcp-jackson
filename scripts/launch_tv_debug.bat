@echo off
REM Launch TradingView Desktop on Windows with Chrome DevTools Protocol enabled
REM Usage: scripts\launch_tv_debug.bat [port]

set PORT=%1
if "%PORT%"=="" set PORT=9222

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch_tv_debug_msix.ps1" -Port %PORT%
