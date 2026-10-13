@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0MudokonThrowFix.ps1" -Action Apply -Fixes 1,2
echo.
pause
