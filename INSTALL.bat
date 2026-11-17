@echo off
setlocal
cd /d "%~dp0"
if not exist "ServerConsole.ps1" (
    echo ERROR: ServerConsole.ps1 is missing. Extract the complete package into this server folder.
    pause
    exit /b 1
)
if not exist "RUN-CONSOLE.bat" (
    echo ERROR: RUN-CONSOLE.bat is missing.
    pause
    exit /b 1
)
if exist "run-server.bat" (
    echo ERROR: run-server.bat already exists. Nothing was changed; it may already be installed.
    pause
    exit /b 1
)
if not exist "run.bat" (
    echo ERROR: Existing run.bat not found. Put the package files in the same folder as your server launcher.
    pause
    exit /b 1
)
ren "run.bat" "run-server.bat"
if errorlevel 1 (
    echo ERROR: Could not back up the original run.bat.
    pause
    exit /b 1
)
copy /y "RUN-CONSOLE.bat" "run.bat" >nul
if errorlevel 1 (
    echo ERROR: Could not install the new run.bat. Restoring the original.
    ren "run-server.bat" "run.bat"
    pause
    exit /b 1
)
echo.
echo Installed successfully.
echo Your original launcher is preserved as run-server.bat.
echo Double-click run.bat to open the new server console.
echo.
pause
