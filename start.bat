@echo off
REM ---------------------------------------------------------------------------
REM rnaseq-nets : double-click launcher for Windows.
REM It simply calls start.ps1 in the same folder, bypassing the execution
REM policy so that students do not have to configure anything.
REM Any argument is forwarded, e.g.:  start.bat -Port 9999
REM ---------------------------------------------------------------------------
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start.ps1" %*
if errorlevel 1 (
  echo.
  echo Something went wrong. Read the messages above.
  pause
)
endlocal
