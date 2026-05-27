@echo off
:: ─────────────────────────────────────────────────────────────────────────────
:: Cage Brawlers – Export Builder
:: Exports both the client and dedicated-server executables into build/.
:: Requires Godot export templates to be installed (see README / Godot docs).
:: ─────────────────────────────────────────────────────────────────────────────

set GODOT=C:\Users\tiago\godot.exe
set PROJECT=%~dp0
if "%PROJECT:~-1%"=="\" set PROJECT=%PROJECT:~0,-1%

echo.
echo  Running source guard checks...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT%\scripts\tools\check_no_runtime_dir_scanning.ps1" -ProjectRoot "%PROJECT%"
if errorlevel 1 ( echo  SOURCE GUARD FAILED & pause & exit /b 1 )

if not exist "%GODOT%" (
    echo ERROR: Godot executable not found at %GODOT%
    pause & exit /b 1
)

:: Create output folders
mkdir "%PROJECT%\build\client"  2>nul
mkdir "%PROJECT%\build\server"  2>nul

echo.
echo  Exporting client...
"%GODOT%" --headless --path "%PROJECT%" --export-release "Windows - Client" "%PROJECT%\build\client\CageBrawlers.exe"
if errorlevel 1 ( echo  CLIENT EXPORT FAILED & pause & exit /b 1 )

echo  Exporting dedicated server...
"%GODOT%" --headless --path "%PROJECT%" --export-release "Windows - Dedicated Server" "%PROJECT%\build\server\CageBrawlers-Server.exe"
if errorlevel 1 ( echo  SERVER EXPORT FAILED & pause & exit /b 1 )

echo.
echo  Done!
echo    Client : build\client\CageBrawlers.exe
echo    Server : build\server\CageBrawlers-Server.exe
echo.
pause
