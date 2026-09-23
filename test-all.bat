@echo off
setlocal EnableExtensions
rem Full API regression through the gateway. Thin launcher for test-all.ps1.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-all.ps1" %*
exit /b %ERRORLEVEL%
