@echo off
rem Internal helper — not a user entry point. Called by build.bat / start-all.bat.
rem Sets ROOT (repo root), JAVA_HOME, MAVEN_HOME, MVN, and prepends PATH.

set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"

set "JAVA_HOME=%ROOT%\tools\jdk"
set "MAVEN_HOME=%ROOT%\tools\maven"
set "M2_REPO=%ROOT%\tools\m2"
set "MVN=%MAVEN_HOME%\bin\mvn.cmd"
set "OFFLINE_SETTINGS=%ROOT%\.mvn\settings-offline.xml"
set "ONLINE_SETTINGS=%ROOT%\.mvn\settings.xml"

if not exist "%JAVA_HOME%\bin\java.exe" (
  echo [FAIL] Bundled JDK not found at tools\jdk
  echo        On an online PC run prepare-offline.bat first, then copy the whole folder.
  exit /b 1
)
if not exist "%MVN%" (
  echo [FAIL] Bundled Maven not found at tools\maven
  echo        On an online PC run prepare-offline.bat first, then copy the whole folder.
  exit /b 1
)

set "PATH=%JAVA_HOME%\bin;%MAVEN_HOME%\bin;%PATH%"
exit /b 0
