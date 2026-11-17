@echo off
setlocal EnableExtensions
cd /d "%~dp0"

where javac >nul 2>&1
if errorlevel 1 (
    echo ERROR: JDK 21 or newer is required. javac was not found in PATH.
    echo Install a JDK, then reopen Command Prompt.
    exit /b 1
)

set "JAVAC_VERSION="
for /f "tokens=2" %%V in ('javac -version 2^>^&1') do set "JAVAC_VERSION=%%V"
for /f "tokens=1 delims=." %%V in ("%JAVAC_VERSION%") do set "JAVAC_MAJOR=%%V"

if not defined JAVAC_MAJOR (
    echo ERROR: Could not detect the Java compiler version.
    exit /b 1
)

if %JAVAC_MAJOR% LSS 21 (
    echo ERROR: JDK 21 or newer is required. Found javac %JAVAC_VERSION%.
    exit /b 1
)

if exist build rmdir /s /q build
mkdir build\deps
mkdir build\classes

echo Downloading the Mixin compile-time API...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://repo.maven.apache.org/maven2/net/fabricmc/sponge-mixin/0.17.3%%2Bmixin.0.8.7/sponge-mixin-0.17.3%%2Bmixin.0.8.7.jar' -OutFile 'build\deps\sponge-mixin.jar'"
if errorlevel 1 (
    echo ERROR: Could not download the Mixin compile-time API.
    exit /b 1
)

if exist build\sources.txt del build\sources.txt
for /r "src\main\java" %%F in (*.java) do echo "%%F">>build\sources.txt

echo Compiling Java sources...
javac --release 21 -proc:none -encoding UTF-8 -classpath "build\deps\sponge-mixin.jar" -d "build\classes" @build\sources.txt
if errorlevel 1 (
    echo ERROR: Compilation failed.
    exit /b 1
)

xcopy /E /I /Y "src\main\resources" "build\classes" >nul
if errorlevel 1 (
    echo ERROR: Could not copy mod resources.
    exit /b 1
)

echo Packaging the mod...
jar --create --file "build\server-dark-gui-1.0.0.jar" -C "build\classes" .
if errorlevel 1 (
    echo ERROR: JAR packaging failed.
    exit /b 1
)

echo.
echo BUILD COMPLETE:
echo %CD%\build\server-dark-gui-1.0.0.jar
exit /b 0
