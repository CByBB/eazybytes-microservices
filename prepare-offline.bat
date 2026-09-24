@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Online PC only: download portable JDK 8 + Maven, fill tools\m2, prove offline build.
cd /d "%~dp0"
set "ROOT=%CD%"
set "TOOLS=%ROOT%\tools"
set "JDK_DIR=%TOOLS%\jdk"
set "MAVEN_DIR=%TOOLS%\maven"
set "M2_REPO=%TOOLS%\m2"
set "DOWNLOADS=%TOOLS%\downloads"
set "ONLINE_SETTINGS=%ROOT%\.mvn\settings.xml"
set "OFFLINE_SETTINGS=%ROOT%\.mvn\settings-offline.xml"

set "JDK_URL=https://api.adoptium.net/v3/binary/latest/8/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
set "MAVEN_VERSION=3.9.9"
set "MAVEN_URL=https://archive.apache.org/dist/maven/maven-3/%MAVEN_VERSION%/binaries/apache-maven-%MAVEN_VERSION%-bin.zip"

echo.
echo [RUN ] Preparing offline kit under tools\
echo.

if not exist "%DOWNLOADS%" mkdir "%DOWNLOADS%"
if not exist "%TOOLS%" mkdir "%TOOLS%"

rem --- JDK 8 (bytecode targets 8; same jars run on JDK 8/11/17) ---
set "NEED_JDK=1"
if exist "%JDK_DIR%\bin\java.exe" (
  "%JDK_DIR%\bin\java.exe" -version 2>&1 | findstr /C:"1.8." >nul
  if not errorlevel 1 set "NEED_JDK=0"
)
if "%NEED_JDK%"=="0" (
  echo [SKIP] JDK 8 already present at tools\jdk
) else (
  if exist "%JDK_DIR%" (
    echo [RUN ] Replacing tools\jdk with Temurin JDK 8...
    rmdir /s /q "%JDK_DIR%"
  )
  echo [RUN ] Downloading Temurin JDK 8...
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%JDK_URL%' -OutFile '%DOWNLOADS%\jdk8.zip'"
  if errorlevel 1 (
    echo [FAIL] JDK download failed.
    exit /b 1
  )
  echo [RUN ] Extracting JDK...
  if exist "%DOWNLOADS%\jdk-extract" rmdir /s /q "%DOWNLOADS%\jdk-extract"
  mkdir "%DOWNLOADS%\jdk-extract"
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -Path '%DOWNLOADS%\jdk8.zip' -DestinationPath '%DOWNLOADS%\jdk-extract' -Force"
  if errorlevel 1 (
    echo [FAIL] JDK extract failed.
    exit /b 1
  )
  for /d %%D in ("%DOWNLOADS%\jdk-extract\*") do (
    move "%%D" "%JDK_DIR%" >nul
    goto :jdk_moved
  )
  :jdk_moved
  if not exist "%JDK_DIR%\bin\java.exe" (
    echo [FAIL] java.exe not found after extract.
    exit /b 1
  )
  del /f /q "%DOWNLOADS%\jdk8.zip" >nul 2>&1
  if exist "%DOWNLOADS%\jdk-extract" rmdir /s /q "%DOWNLOADS%\jdk-extract"
  echo [DONE] JDK 8 ready
)

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

set "JAVA_HOME=%JDK_DIR%"
set "MAVEN_HOME=%MAVEN_DIR%"
set "PATH=%JAVA_HOME%\bin;%MAVEN_HOME%\bin;%PATH%"
set "MVN=%MAVEN_HOME%\bin\mvn.cmd"

echo.
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
echo        Next: package-offline.bat
echo              ^(one .tar = source + tools + Docker images for offline develop AND run^)
echo        On the offline PC: build.bat then start-all.bat
echo                           OR docker-start.bat if Docker Desktop is installed
exit /b 0
