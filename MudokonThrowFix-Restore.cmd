@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0MudokonThrowFix.ps1" -Action Restore
echo.
pause
