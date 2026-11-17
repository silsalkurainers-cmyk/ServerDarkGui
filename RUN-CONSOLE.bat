@echo off
setlocal
if not exist "%~dp0ServerConsole.ps1" (
    echo ERROR: ServerConsole.ps1 is missing.
    pause
    exit /b 1
)
start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0ServerConsole.ps1"
exit /b
