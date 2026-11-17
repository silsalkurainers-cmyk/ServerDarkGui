@echo off
setlocal
if not exist "%~dp0ServerConsole.ps1" (
    echo ERROR: ServerConsole.ps1 is missing.
    pause
    exit /b 1
)

rem Keep PowerShell/.NET temporary files on the same drive as this server folder.
set "CONSOLE_TEMP=%~dp0.console-temp"
if not exist "%CONSOLE_TEMP%" mkdir "%CONSOLE_TEMP%"
if not exist "%CONSOLE_TEMP%\" (
    echo ERROR: Could not create the console temporary folder:
    echo "%CONSOLE_TEMP%"
    pause
    exit /b 1
)
set "TEMP=%CONSOLE_TEMP%"
set "TMP=%CONSOLE_TEMP%"

start "Minecraft Server Console" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0ServerConsole.ps1"
if errorlevel 1 (
    echo ERROR: Could not start PowerShell.
    pause
    exit /b 1
)
exit /b
