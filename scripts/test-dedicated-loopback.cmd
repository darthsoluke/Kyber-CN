@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0run-dedicated.ps1" -Action Loopback %*
