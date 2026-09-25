@echo off
setlocal EnableExtensions
rem Online PC: Docker-only package (SOURCE + images, NO tools\).
rem Prefer package-offline.bat for the full kit (develop + Docker run in one .tar).
cd /d "%~dp0"
set "ROOT=%CD%"
set "IMAGES=%ROOT%\eazybank-docker-images.tar"
set "ARCHIVE=%ROOT%\eazybank-docker-offline.tar"
set "STAGING=%ROOT%\.docker-package-staging"

echo.
echo [HINT] For offline DEVELOP + RUN in one .tar, use package-offline.bat instead.
echo        This script creates a Docker-only .tar ^(source + images, no JDK/Maven^).
echo.

where docker >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Docker not found. Install Docker Desktop and retry.
  exit /b 1
)

where mvn >nul 2>&1
if errorlevel 1 (
  if exist "%~dp0build.bat" if exist "%~dp0tools\maven\bin\mvn.cmd" (
    echo [INFO] System Maven missing; will use build.bat / tools\ after this check.
  ) else (
    echo [FAIL] Maven not found on PATH. Install Maven 3.9+ and Java 8+, or run prepare-offline.bat first.
    exit /b 1
  )
)

set "TAR=%SystemRoot%\System32\tar.exe"
if not exist "%TAR%" (
  echo [FAIL] Windows tar.exe not found at %TAR%
  exit /b 1
)

echo.
echo [RUN ] Building jars...
echo.
if exist "%~dp0tools\maven\bin\mvn.cmd" if exist "%~dp0build.bat" (
  call "%~dp0build.bat"
) else (
  call mvn -DskipTests clean package
)
if errorlevel 1 (
  echo [FAIL] Jar build failed.
  exit /b 1
)

for %%S in (configserver eurekaserver accounts cards loans message gatewayserver) do (
  if not exist "%~dp0%%S\target\%%S-0.0.1-SNAPSHOT.jar" (
    echo [FAIL] Missing %%S\target\%%S-0.0.1-SNAPSHOT.jar
    exit /b 1
  )
)

echo.
echo [RUN ] docker compose build...
echo.
docker pull eclipse-temurin:8-jre-jammy
docker compose build
if errorlevel 1 (
  echo [FAIL] docker compose build failed ^(needs network for base image the first time^).
  exit /b 1
)

echo.
echo [RUN ] Saving images to eazybank-docker-images.tar ...
echo.
set "SAVE_LIST=eazybank/configserver:offline eazybank/eurekaserver:offline eazybank/accounts:offline eazybank/cards:offline eazybank/loans:offline eazybank/message:offline eazybank/gatewayserver:offline"
docker image inspect eclipse-temurin:8-jre-jammy >nul 2>&1
if not errorlevel 1 set "SAVE_LIST=eclipse-temurin:8-jre-jammy %SAVE_LIST%"

docker save -o "%IMAGES%" %SAVE_LIST%
if errorlevel 1 (
  echo [FAIL] docker save failed.
  exit /b 1
)

echo.
echo [RUN ] Packing SOURCE + images into eazybank-docker-offline.tar ...
echo.
echo        ^(Docker images are compiled JARs only — they do NOT contain source.^)
echo        ^(The .tar adds the project source so you can open it in an IDE offline.^)
echo.

if exist "%STAGING%" rmdir /s /q "%STAGING%"
mkdir "%STAGING%\eazybank"
if errorlevel 1 (
  echo [FAIL] Could not create staging folder.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root='%ROOT%'; $dest='%STAGING%\eazybank'; $excludeDirs = @('.git','logs','.docker-package-staging','.offline-package-staging','tools'); $excludeNames = @('eazybank-docker-offline.zip','eazybank-docker-offline.tar','eazybank-docker-offline.tar.gz','eazybank-offline.zip','eazybank-offline.tar','eazybank-offline.tar.gz','prepare-offline.bat','package-offline.bat','docker-prepare-offline.bat'); function ShouldSkip($full) { $rel = $full.Substring($root.Length).TrimStart('\'); foreach ($d in $excludeDirs) { if ($rel -eq $d -or $rel.StartsWith($d + '\')) { return $true } }; if ($rel -match '\\target\\') { return $true }; if ($rel -eq 'target' -or $rel.EndsWith('\target')) { return $true }; $name = Split-Path $full -Leaf; if ($excludeNames -contains $name) { return $true }; return $false }; Get-ChildItem -Path $root -Recurse -Force | Where-Object { -not (ShouldSkip $_.FullName) } | ForEach-Object { $rel = $_.FullName.Substring($root.Length).TrimStart('\'); $target = Join-Path $dest $rel; if ($_.PSIsContainer) { New-Item -ItemType Directory -Force -Path $target | Out-Null } else { $parent = Split-Path $target -Parent; if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }; Copy-Item -Force $_.FullName $target } }; Write-Host '[DONE] Staging complete'"

if errorlevel 1 (
  echo [FAIL] Staging failed.
  exit /b 1
)

if not exist "%STAGING%\eazybank\eazybank-docker-images.tar" (
  echo [FAIL] Staged package is missing eazybank-docker-images.tar
  exit /b 1
)
if not exist "%STAGING%\eazybank\docker-compose.yml" (
  echo [FAIL] Staged package is missing docker-compose.yml
  exit /b 1
)
if not exist "%STAGING%\eazybank\docker-start.bat" (
  echo [FAIL] Staged package is missing docker-start.bat
  exit /b 1
)

if exist "%ARCHIVE%" del /f /q "%ARCHIVE%"
rem Plain .tar via System32 tar — Git Bash tar treats C:\ as a remote host.
"%TAR%" -cf "%ARCHIVE%" -C "%STAGING%" eazybank
if errorlevel 1 (
  echo [FAIL] tar creation failed.
  exit /b 1
)

rmdir /s /q "%STAGING%" >nul 2>&1

for %%A in ("%ARCHIVE%") do echo [DONE] Created %%~fA ^(%%~zA bytes^)
echo.
echo        Copy ONLY that .tar to the offline PC.
echo        Extract: tar -xf eazybank-docker-offline.tar
echo        Then run docker-start.bat ^(Docker Desktop required^).
echo.
echo        Note: this .tar has NO tools\ — you cannot rebuild offline with it.
echo        For develop+run offline, use package-offline.bat instead.
exit /b 0
