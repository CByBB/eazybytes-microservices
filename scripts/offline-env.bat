@echo off
rem Internal helper — not a user entry point. Called by build.bat / start-all.bat.
rem Sets ROOT, JAVA_HOME (tools\jdk-8|11|17), MAVEN_HOME, MVN, and prepends PATH.
rem Optional: set EAZYBANK_JAVA_VERSION=8|11|17 before calling (default 8).

set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"

if not defined EAZYBANK_JAVA_VERSION set "EAZYBANK_JAVA_VERSION=8"
if "%EAZYBANK_JAVA_VERSION%"=="1.8" set "EAZYBANK_JAVA_VERSION=8"

if not "%EAZYBANK_JAVA_VERSION%"=="8" if not "%EAZYBANK_JAVA_VERSION%"=="11" if not "%EAZYBANK_JAVA_VERSION%"=="17" (
  echo [FAIL] EAZYBANK_JAVA_VERSION must be 8, 11, or 17 ^(got %EAZYBANK_JAVA_VERSION%^)
  exit /b 1
)

set "JAVA_HOME=%ROOT%\tools\jdk-%EAZYBANK_JAVA_VERSION%"
set "MAVEN_HOME=%ROOT%\tools\maven"
set "M2_REPO=%ROOT%\tools\m2"
set "MVN=%MAVEN_HOME%\bin\mvn.cmd"
set "OFFLINE_SETTINGS=%ROOT%\.mvn\settings-offline.xml"
set "ONLINE_SETTINGS=%ROOT%\.mvn\settings.xml"

if not exist "%JAVA_HOME%\bin\java.exe" (
  echo [FAIL] Bundled JDK not found at tools\jdk-%EAZYBANK_JAVA_VERSION%
  echo        Expected tools\jdk-8, tools\jdk-11, and tools\jdk-17 in this package.
  exit /b 1
)
if not exist "%MVN%" (
  echo [FAIL] Bundled Maven not found at tools\maven
  exit /b 1
)

set "PATH=%JAVA_HOME%\bin;%MAVEN_HOME%\bin;%PATH%"
echo [INFO] Using JAVA_HOME=%JAVA_HOME%
exit /b 0
