@echo off
setlocal EnableExtensions
rem Start or stop all Eazy Bank services (PowerShell body embedded below).
cd /d "%~dp0"
call "%~dp0scripts\offline-env.bat" || exit /b 1
set "EAZYBANK_ROOT=%CD%"
set "TMPPS=%TEMP%\eazybank-start-all-%RANDOM%%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%~f0'; $o=$env:TMPPS; $lines=Get-Content -LiteralPath $p; $i=0; while ($i -lt $lines.Count -and $lines[$i] -ne 'rem === POWERSHELL ===') { $i++ }; if ($i -ge $lines.Count) { throw 'POWERSHELL marker not found' }; Set-Content -LiteralPath $o -Value (($lines[($i+1)..($lines.Count-1)]) -join [Environment]::NewLine)"
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%" %*
set "ERR=%ERRORLEVEL%"
del /f /q "%TMPPS%" >nul 2>&1
exit /b %ERR%

rem === POWERSHELL ===
# Start or stop all Eazy Bank services using bundled JDK jars.
param(
  [Parameter(Position = 0)]
  [ValidateSet('start', 'stop')]
  [string]$Action = 'start'
)

$ErrorActionPreference = 'Stop'
$Root = if ($env:EAZYBANK_ROOT) { $env:EAZYBANK_ROOT } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location $Root

$JavaHome = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { Join-Path $Root 'tools\jdk-8' }
$Java = Join-Path $JavaHome 'bin\java.exe'
$LogDir = Join-Path $Root 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

if (-not (Test-Path $Java)) {
  Write-Host "[FAIL] Bundled JDK not found at $JavaHome" -ForegroundColor Red
  Write-Host '       Expected tools\jdk-8 (default), or set EAZYBANK_JAVA_VERSION=11|17.'
  exit 1
}

$Services = @(
  @{ Name = 'configserver';  Port = 8071; KafkaQuiet = $false; Color = 'Blue' }
  @{ Name = 'eurekaserver';  Port = 8070; KafkaQuiet = $false; Color = 'Magenta' }
  @{ Name = 'accounts';      Port = 8080; KafkaQuiet = $true;  Color = 'Cyan' }
  @{ Name = 'cards';         Port = 9000; KafkaQuiet = $false; Color = 'Yellow' }
  @{ Name = 'loans';         Port = 8090; KafkaQuiet = $false; Color = 'Green' }
  @{ Name = 'message';       Port = 9010; KafkaQuiet = $true;  Color = 'White' }
  @{ Name = 'gatewayserver'; Port = 8072; KafkaQuiet = $false; Color = 'Cyan' }
)

$ServiceColor = @{}
foreach ($s in $Services) { $ServiceColor[$s.Name] = $s.Color }

function Say([string]$Tag, [string]$Msg, [string]$Name = '') {
  $tagColor = switch -Regex ($Tag.Trim()) {
    'FAIL' { 'Red' }
    'UP'   { 'Green' }
    'DONE' { 'Green' }
    'WAIT' { 'Yellow' }
    'RUN'  { 'Cyan' }
    'STOP' { 'Magenta' }
    'LOGS|HINT' { 'Blue' }
    default { 'Gray' }
  }
  Write-Host -NoNewline '[' -ForegroundColor $tagColor
  Write-Host -NoNewline $Tag -ForegroundColor $tagColor
  Write-Host -NoNewline '] ' -ForegroundColor $tagColor
  if ($Name -and $ServiceColor.ContainsKey($Name) -and $Msg.StartsWith($Name)) {
    Write-Host -NoNewline $Name -ForegroundColor $ServiceColor[$Name]
    Write-Host $Msg.Substring($Name.Length)
  } else {
    Write-Host $Msg
  }
}

function Find-Jar([string]$Module) {
  $dir = Join-Path $Root "$Module\target"
  if (-not (Test-Path $dir)) { return $null }
  $jars = Get-ChildItem -Path $dir -Filter "$Module-*.jar" -File |
    Where-Object { $_.Name -notmatch 'sources|javadoc|\.original' } |
    Sort-Object Length -Descending
  if ($jars) { return $jars[0].FullName }
  return $null
}

function Get-PidsOnPort([int]$Port) {
  $pids = New-Object 'System.Collections.Generic.HashSet[int]'
  try {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
      ForEach-Object { if ($_.OwningProcess) { [void]$pids.Add([int]$_.OwningProcess) } }
  } catch {}
  # Fallback for older Windows / missing Get-NetTCPConnection permissions
  if ($pids.Count -eq 0) {
    $lines = netstat -ano -p tcp 2>$null | Select-String -Pattern ":$Port\s+.*LISTENING\s+(\d+)\s*$"
    foreach ($m in $lines) {
      if ($m.Matches.Count -gt 0) {
        $id = [int]$m.Matches[0].Groups[1].Value
        if ($id -gt 0) { [void]$pids.Add($id) }
      }
    }
  }
  return @($pids)
}

function Stop-ServiceByName([string]$Name, [int]$Port = 0) {
  $killed = New-Object 'System.Collections.Generic.HashSet[int]'
  $pidFile = Join-Path $LogDir "$Name.pid"
  if (Test-Path $pidFile) {
    $procId = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($procId) {
      $id = 0
      if ([int]::TryParse($procId, [ref]$id) -and $id -gt 0) {
        Say 'STOP' "$Name pid $id" $Name
        cmd.exe /c "taskkill /F /T /PID $id >nul 2>&1"
        [void]$killed.Add($id)
      }
    }
    Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
  }
  if ($Port -gt 0) {
    foreach ($id in (Get-PidsOnPort $Port)) {
      if ($killed.Contains($id)) { continue }
      Say 'STOP' "$Name port $Port pid $id" $Name
      cmd.exe /c "taskkill /F /T /PID $id >nul 2>&1"
      [void]$killed.Add($id)
    }
  }
  # Also catch leftover mvn spring-boot:run / java -jar for this module
  try {
    Get-CimInstance Win32_Process -Filter "name='java.exe'" -ErrorAction SilentlyContinue |
      Where-Object {
        $_.CommandLine -and (
          $_.CommandLine -match [regex]::Escape("$Name-0.0.1-SNAPSHOT.jar") -or
          $_.CommandLine -match ("-pl\s+$Name\b") -or
          $_.CommandLine -match ("com\.eazybytes\.$Name\.")
        )
      } |
      ForEach-Object {
        if ($killed.Contains([int]$_.ProcessId)) { return }
        Say 'STOP' "$Name java pid $($_.ProcessId)" $Name
        cmd.exe /c "taskkill /F /T /PID $($_.ProcessId) >nul 2>&1"
        [void]$killed.Add([int]$_.ProcessId)
      }
  } catch {}
}

function Wait-Port([int]$Port, [string]$Name) {
  Say 'WAIT' "$Name on port $Port (first start can take a few minutes)" $Name
  for ($i = 1; $i -le 90; $i++) {
    try {
      $code = & curl.exe --noproxy '*' -sf -o NUL -w '%{http_code}' "http://127.0.0.1:$Port/actuator/health" 2>$null
      if ($code -eq '200') {
        Say ' UP ' "$Name is ready on $Port" $Name
        return $true
      }
    } catch {}
    try {
      $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/actuator/health" -TimeoutSec 2
      if ($r.StatusCode -eq 200) {
        Say ' UP ' "$Name is ready on $Port" $Name
        return $true
      }
    } catch {}
    if (($i % 15) -eq 0) {
      Say 'WAIT' "$Name still starting... $(Join-Path $LogDir "$Name.log")" $Name
    }
    Start-Sleep -Seconds 2
  }
  Say 'FAIL' "$Name timed out on port $Port. See $(Join-Path $LogDir "$Name.log")" $Name
  return $false
}

function Start-OneService($Svc) {
  $name = $Svc.Name
  $jar = Find-Jar $name
  if (-not $jar) {
    Say 'FAIL' "No runnable jar for $name. Run build.bat first." $name
    return $false
  }
  $log = Join-Path $LogDir "$name.log"
  $pidFile = Join-Path $LogDir "$name.pid"
  $launcher = Join-Path $LogDir "$name-run.cmd"
  Say 'RUN ' "$name" $name
  if (Test-Path $log) { Remove-Item -Force $log -ErrorAction SilentlyContinue }

  $argList = New-Object System.Collections.Generic.List[string]
  if ($Svc.KafkaQuiet) {
    $argList.Add('-Dspring.cloud.function.autodetect=false')
    $argList.Add('-Dspring.cloud.function.definition=')
    $argList.Add('-Dlogging.level.org.apache.kafka=ERROR')
    $argList.Add('-Dlogging.level.org.springframework.kafka=ERROR')
    $argList.Add('-Dlogging.level.org.springframework.cloud.stream.binder.kafka=ERROR')
  }
  $argList.Add('-jar')
  $argList.Add($jar)

  # Quote every arg for cmd.exe. Empty -Dfoo= must be "-Dfoo=" or cmd drops the rest of the line.
  $quotedArgs = ($argList | ForEach-Object {
    '"' + ($_ -replace '"', '""') + '"'
  }) -join ' '
  $launcherLines = @(
    '@echo off',
    "cd /d `"$Root`"",
    "`"$Java`" $quotedArgs > `"$log`" 2>&1"
  )
  Set-Content -LiteralPath $launcher -Value $launcherLines -Encoding ASCII
  $p = Start-Process -FilePath $launcher -WorkingDirectory $Root -WindowStyle Hidden -PassThru
  if (-not $p) {
    Say 'FAIL' "Could not start $name" $name
    return $false
  }
  Set-Content -Path $pidFile -Value $p.Id

  # Give the process a moment; refresh HasExited. Do not treat buffered (empty) logs as failure.
  Start-Sleep -Seconds 3
  $null = $p.Refresh()
  if ($p.HasExited) {
    $snippet = ''
    if (Test-Path $log) {
      $snippet = (Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue)
      if ($snippet -and $snippet.Length -gt 400) { $snippet = $snippet.Substring(0, 400) }
    }
    if (-not $snippet) { $snippet = '(log empty — java failed before writing output)' }
    Say 'FAIL' "$name exited immediately. $snippet" $name
    return $false
  }

  return (Wait-Port $Svc.Port $name)
}

if ($Action -eq 'stop') {
  Write-Host ''
  Write-Host ' Eazy Bank  ' -NoNewline
  Write-Host 'stopping services' -ForegroundColor Magenta
  Write-Host ''
  foreach ($svc in @(
    @{ Name = 'gatewayserver'; Port = 8072 },
    @{ Name = 'message'; Port = 9010 },
    @{ Name = 'loans'; Port = 8090 },
    @{ Name = 'cards'; Port = 9000 },
    @{ Name = 'accounts'; Port = 8080 },
    @{ Name = 'eurekaserver'; Port = 8070 },
    @{ Name = 'configserver'; Port = 8071 }
  )) {
    Stop-ServiceByName $svc.Name $svc.Port
  }
  $logcap = Join-Path $LogDir 'logcap.pid'
  if (Test-Path $logcap) {
    $lp = (Get-Content $logcap -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($lp) { cmd.exe /c "taskkill /F /T /PID $lp >nul 2>&1" }
    Remove-Item -Force $logcap -ErrorAction SilentlyContinue
  }
  Say 'DONE' 'All services stopped.'
  exit 0
}

Write-Host ''
Write-Host ' Eazy Bank  ' -NoNewline
Write-Host "starting from $Root" -ForegroundColor Cyan
Write-Host ''

foreach ($svc in $Services) {
  if (-not (Start-OneService $svc)) { exit 1 }
}

Write-Host ''
Write-Host ' Eazy Bank  ' -NoNewline
Write-Host 'all services are up' -ForegroundColor Green
Write-Host ''
foreach ($svc in $Services) {
  Write-Host -NoNewline '  '
  Write-Host -NoNewline $svc.Name.PadRight(16) -ForegroundColor $svc.Color
  Write-Host ("http://localhost:{0}" -f $svc.Port)
}
Write-Host ''
Say 'LOGS' $LogDir
Say 'HINT' 'Stop everything with start-all.bat stop'
exit 0
