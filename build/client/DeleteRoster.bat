@echo off
set "ROSTER_FILE=%APPDATA%\Godot\app_userdata\Cage Brawlers\roster.json"
if exist "%ROSTER_FILE%" (
    del /f /q "%ROSTER_FILE%"
    echo Deleted: %ROSTER_FILE%
) else (
    echo No roster file found at: %ROSTER_FILE%
)
pause
