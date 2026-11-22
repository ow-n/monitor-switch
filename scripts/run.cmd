@echo off
setlocal
"%SystemRoot%\System32\where.exe" pwsh.exe >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 is required. Install it and ensure pwsh.exe is on PATH.
    echo Install command: winget install --id Microsoft.PowerShell --exact
    pause
    exit /b 1
)
set "PSModulePath="
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0monitor-switch.ps1" %*
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
