@echo off
rem Shared env for portable JDK + Maven under tools\
rem Call with: call "%~dp0offline-env.bat"
rem Sets ROOT, JAVA_HOME, MAVEN_HOME, MVN, and prepends PATH.

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

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
