@echo off
setlocal EnableExtensions
rem Start or stop all Eazy Bank services. Thin launcher for start-all.ps1.
cd /d "%~dp0"
call "%~dp0offline-env.bat" || exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-all.ps1" %*
exit /b %ERRORLEVEL%
