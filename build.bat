@echo off
setlocal EnableExtensions
rem Offline build using bundled JDK, Maven, and tools\m2
cd /d "%~dp0"
call "%~dp0offline-env.bat" || exit /b 1

echo.
echo [RUN ] mvn -o clean install -DskipTests
echo.

call "%MVN%" -o -s "%OFFLINE_SETTINGS%" -Dmaven.repo.local="%M2_REPO%" clean install -DskipTests
if errorlevel 1 (
  echo.
  echo [FAIL] Offline build failed. If you added new dependencies, run prepare-offline.bat on an online PC.
  exit /b 1
)

for %%M in (accounts cards loans message configserver eurekaserver gatewayserver eazybank) do (
  if exist "%M2_REPO%\com\eazybytes\%%M" rmdir /s /q "%M2_REPO%\com\eazybytes\%%M"
)
del /s /q "%ROOT%\*\target\*.jar.original" >nul 2>&1

echo.
echo [DONE] Offline build succeeded.
exit /b 0
