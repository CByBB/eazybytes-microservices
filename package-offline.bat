@echo off
setlocal EnableExtensions
rem Build eazybank-offline.zip including tools\ for copy to an offline PC.
cd /d "%~dp0"
set "ROOT=%CD%"
set "ZIP=%ROOT%\eazybank-offline.zip"
set "STAGING=%ROOT%\tools\package-staging"

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

echo.
echo [RUN ] Packaging offline zip...
echo.

if exist "%STAGING%" rmdir /s /q "%STAGING%"
mkdir "%STAGING%\eazybank"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root='%ROOT%'; $dest='%STAGING%\eazybank'; $excludeDirs = @('.git','logs','tools\downloads','tools\package-staging'); $excludeNames = @('eazybank-offline.zip'); function ShouldSkip($full) { $rel = $full.Substring($root.Length).TrimStart('\'); foreach ($d in $excludeDirs) { if ($rel -eq $d -or $rel.StartsWith($d + '\')) { return $true } }; if ($rel -match '\\target\\') { return $true }; if ($rel -eq 'target' -or $rel.EndsWith('\target')) { return $true }; $name = Split-Path $full -Leaf; if ($excludeNames -contains $name) { return $true }; return $false }; Get-ChildItem -Path $root -Recurse -Force | Where-Object { -not (ShouldSkip $_.FullName) } | ForEach-Object { $rel = $_.FullName.Substring($root.Length).TrimStart('\'); $target = Join-Path $dest $rel; if ($_.PSIsContainer) { New-Item -ItemType Directory -Force -Path $target | Out-Null } else { $parent = Split-Path $target -Parent; if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }; Copy-Item -Force $_.FullName $target } }; Write-Host '[DONE] Staging complete'"

if errorlevel 1 (
  echo [FAIL] Staging failed.
  exit /b 1
)

if exist "%ZIP%" del /f /q "%ZIP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path '%STAGING%\eazybank' -DestinationPath '%ZIP%' -Force"

if errorlevel 1 (
  echo [FAIL] Zip creation failed.
  exit /b 1
)

rmdir /s /q "%STAGING%"

for %%A in ("%ZIP%") do echo [DONE] Created %%~fA ^(%%~zA bytes^)
echo        Copy that zip to the offline PC, unzip, then run build.bat and start-all.bat
exit /b 0
