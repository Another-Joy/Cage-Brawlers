@echo off
:: ─────────────────────────────────────────────────────────────────────────────
:: Cage Brawlers – One-Click Launcher
:: If exported binaries exist in build/ they are used directly.
:: Otherwise falls back to running the project through the Godot editor binary.
:: ─────────────────────────────────────────────────────────────────────────────

set GODOT=C:\Users\tiago\godot.exe
set PROJECT=%~dp0
if "%PROJECT:~-1%"=="\" set PROJECT=%PROJECT:~0,-1%

set CLIENT_EXE=%PROJECT%\build\client\CageBrawlers.exe
set SERVER_EXE=%PROJECT%\build\server\CageBrawlers-Server.exe

echo.
echo  Cage Brawlers Launcher

:: ── Prefer exported binaries if present ──────────────────────────────────────
if exist "%SERVER_EXE%" if exist "%CLIENT_EXE%" (
    echo  Mode: Exported binaries
    echo  ── Server: %SERVER_EXE%
    echo  ── Client: %CLIENT_EXE%
    echo.
    echo  Starting server ^(headless^)...
    start "Cage Brawlers – Server" "%SERVER_EXE%"
    echo  Waiting 2 seconds for the server to initialise...
    timeout /t 2 /nobreak >nul
    echo  Starting client...
    start "Cage Brawlers – Client" "%CLIENT_EXE%"
    goto :done
)

:: ── Fall back to Godot editor binary + project path ──────────────────────────
echo  Mode: Godot editor ^(no exported build found in build/^)
echo  ── Server path : %GODOT%
echo  ── Project path: %PROJECT%
echo.
if not exist "%GODOT%" (
    echo  ERROR: Godot executable not found at:
    echo    %GODOT%
    echo.
    echo  Either run export.bat first, or edit the GODOT variable in this script.
    pause
    exit /b 1
)
echo  Starting server ^(headless^)...
start "Cage Brawlers – Server" "%GODOT%" --headless --path "%PROJECT%"
echo  Waiting 2 seconds for the server to initialise...
timeout /t 2 /nobreak >nul
echo  Starting client...
start "Cage Brawlers – Client" "%GODOT%" --path "%PROJECT%"

:done
echo  Done. Both windows should now be open.
echo  Close this window when finished.
pause
