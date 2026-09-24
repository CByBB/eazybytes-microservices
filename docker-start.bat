@echo off
setlocal EnableExtensions
rem Offline PC (Docker installed): load images if needed and start the stack.
cd /d "%~dp0"

where docker >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Docker not found. Install Docker Desktop first.
  exit /b 1
)

if not exist "%~dp0docker-compose.yml" (
  echo [FAIL] docker-compose.yml missing.
  exit /b 1
)

docker image inspect eazybank/gatewayserver:offline >nul 2>&1
if errorlevel 1 (
  if not exist "%~dp0eazybank-docker-images.tar" (
    echo [FAIL] Images not loaded and eazybank-docker-images.tar not found.
    echo        On an online PC run docker-prepare-offline.bat, then copy the tar here.
    exit /b 1
  )
  echo [RUN ] docker load -i eazybank-docker-images.tar
  docker load -i "%~dp0eazybank-docker-images.tar"
  if errorlevel 1 (
    echo [FAIL] docker load failed.
    exit /b 1
  )
) else (
  echo [SKIP] eazybank images already present
)

echo.
echo [RUN ] docker compose up -d
echo.
docker compose up -d
if errorlevel 1 (
  echo [FAIL] docker compose up failed.
  exit /b 1
)

echo.
echo [DONE] Stack starting. Gateway: http://localhost:8072
echo        Swagger: http://localhost:8072/swagger-ui.html
echo        Stop with docker-stop.bat
exit /b 0
