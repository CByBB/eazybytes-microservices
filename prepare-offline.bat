@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Online PC only: download portable JDK 8+11+17 + Maven, fill tools\m2, prove offline build.
cd /d "%~dp0"
set "ROOT=%CD%"
set "TOOLS=%ROOT%\tools"
set "MAVEN_DIR=%TOOLS%\maven"
set "M2_REPO=%TOOLS%\m2"
set "DOWNLOADS=%TOOLS%\downloads"
set "ONLINE_SETTINGS=%ROOT%\.mvn\settings.xml"
set "OFFLINE_SETTINGS=%ROOT%\.mvn\settings-offline.xml"

set "MAVEN_VERSION=3.9.9"
set "MAVEN_URL=https://archive.apache.org/dist/maven/maven-3/%MAVEN_VERSION%/binaries/apache-maven-%MAVEN_VERSION%-bin.zip"

echo.
echo [RUN ] Preparing offline kit under tools\
echo.

if not exist "%DOWNLOADS%" mkdir "%DOWNLOADS%"
if not exist "%TOOLS%" mkdir "%TOOLS%"

rem Migrate legacy tools\jdk (single folder) -> tools\jdk-8
if exist "%TOOLS%\jdk\bin\java.exe" if not exist "%TOOLS%\jdk-8\bin\java.exe" (
  echo [RUN ] Moving legacy tools\jdk to tools\jdk-8...
  move "%TOOLS%\jdk" "%TOOLS%\jdk-8" >nul
)

call :ensure_jdk 8
if errorlevel 1 exit /b 1
call :ensure_jdk 11
if errorlevel 1 exit /b 1
call :ensure_jdk 17
if errorlevel 1 exit /b 1

rem --- Maven ---
if exist "%MAVEN_DIR%\bin\mvn.cmd" (
  echo [SKIP] Maven already present at tools\maven
) else (
  echo [RUN ] Downloading Apache Maven %MAVEN_VERSION%...
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%MAVEN_URL%' -OutFile '%DOWNLOADS%\maven.zip'"
  if errorlevel 1 (
    echo [FAIL] Maven download failed.
    exit /b 1
  )
  echo [RUN ] Extracting Maven...
  if exist "%MAVEN_DIR%" rmdir /s /q "%MAVEN_DIR%"
  if exist "%DOWNLOADS%\maven-extract" rmdir /s /q "%DOWNLOADS%\maven-extract"
  mkdir "%DOWNLOADS%\maven-extract"
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -Path '%DOWNLOADS%\maven.zip' -DestinationPath '%DOWNLOADS%\maven-extract' -Force"
  if errorlevel 1 (
    echo [FAIL] Maven extract failed.
    exit /b 1
  )
  for /d %%D in ("%DOWNLOADS%\maven-extract\*") do (
    move "%%D" "%MAVEN_DIR%" >nul
    goto :maven_moved
  )
  :maven_moved
  if not exist "%MAVEN_DIR%\bin\mvn.cmd" (
    echo [FAIL] mvn.cmd not found after extract.
    exit /b 1
  )
  del /f /q "%DOWNLOADS%\maven.zip" >nul 2>&1
  if exist "%DOWNLOADS%\maven-extract" rmdir /s /q "%DOWNLOADS%\maven-extract"
  echo [DONE] Maven ready
)

rem Build/proof with JDK 8 (bytecode target is 1.8)
set "JAVA_HOME=%TOOLS%\jdk-8"
set "MAVEN_HOME=%MAVEN_DIR%"
set "PATH=%JAVA_HOME%\bin;%MAVEN_HOME%\bin;%PATH%"
set "MVN=%MAVEN_HOME%\bin\mvn.cmd"

echo.
echo [INFO] JDKs: tools\jdk-8 , tools\jdk-11 , tools\jdk-17
echo [INFO] Using JDK 8 for Maven build ^(project bytecode is Java 8^)
"%JAVA_HOME%\bin\java.exe" -version
call "%MVN%" -version
echo.

if not exist "%M2_REPO%" mkdir "%M2_REPO%"

echo [RUN ] Filling tools\m2 ^(online clean install^)...
call "%MVN%" -s "%ONLINE_SETTINGS%" -Dmaven.repo.local="%M2_REPO%" -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn clean install -DskipTests
if errorlevel 1 (
  echo [FAIL] Online install into tools\m2 failed.
  exit /b 1
)

echo [RUN ] dependency:go-offline ...
call "%MVN%" -s "%ONLINE_SETTINGS%" -Dmaven.repo.local="%M2_REPO%" -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn dependency:go-offline -DskipTests
if errorlevel 1 (
  echo [WARN] dependency:go-offline reported errors; continuing to prove offline build.
)

echo [RUN ] dependency:resolve-plugins ...
call "%MVN%" -s "%ONLINE_SETTINGS%" -Dmaven.repo.local="%M2_REPO%" -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn dependency:resolve-plugins -DskipTests
if errorlevel 1 (
  echo [WARN] dependency:resolve-plugins reported errors; continuing to prove offline build.
)

echo [RUN ] Normalizing local-repo remote markers for offline use...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-ChildItem -Path '%M2_REPO%' -Recurse -Filter '_remote.repositories' -File -ErrorAction SilentlyContinue | ForEach-Object { $lines = Get-Content -LiteralPath $_.FullName; $out = foreach ($line in $lines) { if ($line -match '^#') { $line } elseif ($line -match '^([^>=]+)>.*') { $matches[1] + '>=' } else { $line } }; Set-Content -LiteralPath $_.FullName -Value $out }"

echo.
echo [RUN ] Proving offline build ^(mvn -o clean install^)...
call "%MVN%" -o -s "%OFFLINE_SETTINGS%" -Dmaven.repo.local="%M2_REPO%" -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn clean install -DskipTests
if errorlevel 1 (
  echo.
  echo [FAIL] Offline proof build failed. Fix missing deps and re-run prepare-offline.bat.
  exit /b 1
)

rem Fat Boot jars in tools\m2 are not needed as dependencies; keep only common/bom there.
for %%M in (accounts cards loans message configserver eurekaserver gatewayserver eazybank) do (
  if exist "%M2_REPO%\com\eazybytes\%%M" rmdir /s /q "%M2_REPO%\com\eazybytes\%%M"
)
del /s /q "%ROOT%\*\target\*.jar.original" >nul 2>&1

echo.
echo [DONE] Offline kit ready under tools\
echo        JDKs: tools\jdk-8  tools\jdk-11  tools\jdk-17
echo        Next: package-offline.bat
exit /b 0

rem ---------------------------------------------------------------------------
rem :ensure_jdk <majorVersion>
rem Downloads Temurin JDK into tools\jdk-<ver> when missing.
rem ---------------------------------------------------------------------------
:ensure_jdk
set "JDK_VER=%~1"
set "JDK_DIR=%TOOLS%\jdk-%JDK_VER%"
set "JDK_ZIP=%DOWNLOADS%\jdk%JDK_VER%.zip"
set "JDK_URL=https://api.adoptium.net/v3/binary/latest/%JDK_VER%/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"

if exist "%JDK_DIR%\bin\java.exe" (
  echo [SKIP] JDK %JDK_VER% already present at tools\jdk-%JDK_VER%
  exit /b 0
)

echo [RUN ] Downloading Temurin JDK %JDK_VER%...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%JDK_URL%' -OutFile '%JDK_ZIP%'"
if errorlevel 1 (
  echo [FAIL] JDK %JDK_VER% download failed.
  exit /b 1
)
echo [RUN ] Extracting JDK %JDK_VER%...
if exist "%JDK_DIR%" rmdir /s /q "%JDK_DIR%"
if exist "%DOWNLOADS%\jdk-extract-%JDK_VER%" rmdir /s /q "%DOWNLOADS%\jdk-extract-%JDK_VER%"
mkdir "%DOWNLOADS%\jdk-extract-%JDK_VER%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; Expand-Archive -Path '%JDK_ZIP%' -DestinationPath '%DOWNLOADS%\jdk-extract-%JDK_VER%' -Force; $src = Get-ChildItem -Path '%DOWNLOADS%\jdk-extract-%JDK_VER%' -Directory | Select-Object -First 1; if (-not $src) { throw 'No JDK folder in zip' }; New-Item -ItemType Directory -Force -Path '%JDK_DIR%' | Out-Null; Copy-Item -Path (Join-Path $src.FullName '*') -Destination '%JDK_DIR%' -Recurse -Force"
if errorlevel 1 (
  echo [FAIL] JDK %JDK_VER% extract failed.
  exit /b 1
)
if not exist "%JDK_DIR%\bin\java.exe" (
  echo [FAIL] java.exe not found after extracting JDK %JDK_VER%.
  exit /b 1
)
del /f /q "%JDK_ZIP%" >nul 2>&1
if exist "%DOWNLOADS%\jdk-extract-%JDK_VER%" rmdir /s /q "%DOWNLOADS%\jdk-extract-%JDK_VER%"
echo [DONE] JDK %JDK_VER% ready at tools\jdk-%JDK_VER%
exit /b 0
