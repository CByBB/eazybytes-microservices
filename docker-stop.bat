@echo off
setlocal EnableExtensions
rem Stop the Docker Compose stack.
cd /d "%~dp0"

where docker >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Docker not found.
  exit /b 1
)

echo [RUN ] docker compose down
docker compose down
if errorlevel 1 (
  echo [FAIL] docker compose down failed.
  exit /b 1
)
echo [DONE] Stack stopped.
exit /b 0
