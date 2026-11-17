@echo off
setlocal
cd /d "%~dp0"
if not exist "run-server.bat" (
    echo ERROR: run-server.bat was not found. Nothing to restore.
    pause
    exit /b 1
)
if exist "run-console-installed.bat" (
    echo ERROR: run-console-installed.bat already exists. Rename or move it first.
    pause
    exit /b 1
)
if exist "run.bat" ren "run.bat" "run-console-installed.bat"
ren "run-server.bat" "run.bat"
if errorlevel 1 (
    echo ERROR: Could not restore the original launcher.
    if exist "run-console-installed.bat" ren "run-console-installed.bat" "run.bat"
    pause
    exit /b 1
)
echo.
echo Original run.bat restored.
echo The console launcher was kept as run-console-installed.bat.
echo.
pause
