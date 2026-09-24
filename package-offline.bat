@echo off
setlocal EnableExtensions
rem Online PC: one transfer .tar = SOURCE + tools\ (JDK/Maven/m2) + Docker images + scripts.
rem Offline PC can then develop (build.bat / start-all.bat) AND/OR run via Docker (docker-start.bat).
cd /d "%~dp0"
set "ROOT=%CD%"
set "IMAGES=%ROOT%\eazybank-docker-images.tar"
set "ARCHIVE=%ROOT%\eazybank-offline.tar"
set "STAGING=%ROOT%\.offline-package-staging"

if not exist "%ROOT%\tools\jdk\bin\java.exe" (
  echo [FAIL] tools\jdk missing. Run prepare-offline.bat first.
  exit /b 1
)
if not exist "%ROOT%\tools\maven\bin\mvn.cmd" (
  echo [FAIL] tools\maven missing. Run prepare-offline.bat first.
  exit /b 1
)
if not exist "%ROOT%\tools\m2" (
  echo [FAIL] tools\m2 missing. Run prepare-offline.bat first.
  exit /b 1
)

where docker >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Docker not found. Install Docker Desktop and retry.
  echo        ^(Client package must include Docker images.^)
  exit /b 1
)

set "TAR=%SystemRoot%\System32\tar.exe"
if not exist "%TAR%" (
  echo [FAIL] Windows tar.exe not found at %TAR%
  exit /b 1
)

echo.
echo [RUN ] Building jars with bundled tools ^(build.bat^)...
echo.
call "%~dp0build.bat"
if errorlevel 1 (
  echo [FAIL] Offline jar build failed.
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
docker pull eclipse-temurin:21-jre-jammy
docker compose build
if errorlevel 1 (
  echo [FAIL] docker compose build failed ^(needs network for base image the first time^).
  exit /b 1
)

echo.
echo [RUN ] Saving images to eazybank-docker-images.tar ...
echo.
set "SAVE_LIST=eazybank/configserver:offline eazybank/eurekaserver:offline eazybank/accounts:offline eazybank/cards:offline eazybank/loans:offline eazybank/message:offline eazybank/gatewayserver:offline"
docker image inspect eclipse-temurin:21-jre-jammy >nul 2>&1
if not errorlevel 1 set "SAVE_LIST=eclipse-temurin:21-jre-jammy %SAVE_LIST%"

docker save -o "%IMAGES%" %SAVE_LIST%
if errorlevel 1 (
  echo [FAIL] docker save failed.
  exit /b 1
)

echo.
echo [RUN ] Packing SOURCE + tools + Docker images into eazybank-offline.tar ...
echo.
echo        tools\  = JDK + Maven + m2  — offline development
echo        images  = compiled JARs only ^(no source^) — docker-start.bat
echo.

if exist "%STAGING%" rmdir /s /q "%STAGING%"
mkdir "%STAGING%\eazybank"
if errorlevel 1 (
  echo [FAIL] Could not create staging folder.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root='%ROOT%'; $dest='%STAGING%\eazybank'; $excludeDirs = @('.git','logs','.offline-package-staging','.docker-package-staging','tools\downloads','tools\package-staging'); $excludeNames = @('eazybank-offline.zip','eazybank-offline.tar','eazybank-offline.tar.gz','eazybank-docker-offline.zip','eazybank-docker-offline.tar','eazybank-docker-offline.tar.gz'); function ShouldSkip($full) { $rel = $full.Substring($root.Length).TrimStart('\'); foreach ($d in $excludeDirs) { if ($rel -eq $d -or $rel.StartsWith($d + '\')) { return $true } }; if ($rel -match '\\target\\') { return $true }; if ($rel -eq 'target' -or $rel.EndsWith('\target')) { return $true }; $name = Split-Path $full -Leaf; if ($excludeNames -contains $name) { return $true }; return $false }; Get-ChildItem -Path $root -Recurse -Force | Where-Object { -not (ShouldSkip $_.FullName) } | ForEach-Object { $rel = $_.FullName.Substring($root.Length).TrimStart('\'); $target = Join-Path $dest $rel; if ($_.PSIsContainer) { New-Item -ItemType Directory -Force -Path $target | Out-Null } else { $parent = Split-Path $target -Parent; if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }; Copy-Item -Force $_.FullName $target } }; Write-Host '[DONE] Staging complete'"

if errorlevel 1 (
  echo [FAIL] Staging failed.
  exit /b 1
)

if not exist "%STAGING%\eazybank\tools\jdk\bin\java.exe" (
  echo [FAIL] Staged package is missing tools\jdk
  exit /b 1
)
if not exist "%STAGING%\eazybank\eazybank-docker-images.tar" (
  echo [FAIL] Staged package is missing eazybank-docker-images.tar
  exit /b 1
)
if not exist "%STAGING%\eazybank\build.bat" (
  echo [FAIL] Staged package is missing build.bat
  exit /b 1
)
if not exist "%STAGING%\eazybank\start-all.bat" (
  echo [FAIL] Staged package is missing start-all.bat
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
echo        Copy ONLY that .tar to the offline PC and extract it:
echo          tar -xf eazybank-offline.tar
echo        Develop:  build.bat  then  start-all.bat   ^(no Docker needed^)
echo        Run alt:  docker-start.bat                 ^(Docker Desktop required^)
exit /b 0
