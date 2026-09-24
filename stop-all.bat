@echo off
rem Convenience wrapper — same as: start-all.bat stop
cd /d "%~dp0"
call "%~dp0start-all.bat" stop
exit /b %ERRORLEVEL%
