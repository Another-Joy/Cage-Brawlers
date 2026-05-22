@echo off
:: ─────────────────────────────────────────────────────────────────────────────
:: Cage Brawlers – One-Click Launcher
:: Starts a headless server in one window, waits 2 seconds, then opens a client.
:: ─────────────────────────────────────────────────────────────────────────────

:: ► Edit this line to point at your Godot 4 executable.
::   Common locations:
::     C:\Program Files\Godot\Godot_v4.x_win64.exe
::     C:\Users\%USERNAME%\AppData\Local\Programs\Godot\Godot_v4.x_win64.exe
::     C:\tools\godot\Godot_v4.x_win64.exe
set GODOT=C:\path\to\Godot_v4.x_win64.exe

:: ► Project path (default: same folder as this script):
set PROJECT=%~dp0
:: Remove the trailing backslash that %~dp0 adds:
if "%PROJECT:~-1%"=="\" set PROJECT=%PROJECT:~0,-1%

echo.
echo  Cage Brawlers Launcher
echo  ── Server path : %GODOT%
echo  ── Project path: %PROJECT%
echo.

:: ── Verify Godot binary exists ───────────────────────────────────────────────
if not exist "%GODOT%" (
    echo  ERROR: Godot executable not found at:
    echo    %GODOT%
    echo.
    echo  Edit the GODOT variable at the top of this script.
    pause
    exit /b 1
)

:: ── Start server (headless) ──────────────────────────────────────────────────
echo  Starting server ^(headless^)...
start "Cage Brawlers – Server" "%GODOT%" --headless --path "%PROJECT%"

:: ── Wait for the server to initialise ────────────────────────────────────────
echo  Waiting 2 seconds for the server to initialise...
timeout /t 2 /nobreak >nul

:: ── Start client ─────────────────────────────────────────────────────────────
echo  Starting client...
start "Cage Brawlers – Client" "%GODOT%" --path "%PROJECT%"

echo  Done. Both windows should now be open.
echo  Close this window when finished.
pause
