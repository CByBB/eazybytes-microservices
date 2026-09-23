# Start or stop all Eazy Bank services using bundled JDK jars.
param(
  [Parameter(Position = 0)]
  [ValidateSet('start', 'stop')]
  [string]$Action = 'start'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$JavaHome = Join-Path $Root 'tools\jdk'
$Java = Join-Path $JavaHome 'bin\java.exe'
$LogDir = Join-Path $Root 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

if (-not (Test-Path $Java)) {
  Write-Host '[FAIL] Bundled JDK not found at tools\jdk'
  Write-Host '       On an online PC run prepare-offline.bat first, then copy the whole folder.'
  exit 1
}

$Services = @(
  @{ Name = 'configserver';  Port = 8071; KafkaQuiet = $false }
  @{ Name = 'eurekaserver';  Port = 8070; KafkaQuiet = $false }
  @{ Name = 'accounts';      Port = 8080; KafkaQuiet = $true }
  @{ Name = 'cards';         Port = 9000; KafkaQuiet = $false }
  @{ Name = 'loans';         Port = 8090; KafkaQuiet = $false }
  @{ Name = 'message';       Port = 9010; KafkaQuiet = $true }
  @{ Name = 'gatewayserver'; Port = 8072; KafkaQuiet = $false }
)

function Find-Jar([string]$Module) {
  $dir = Join-Path $Root "$Module\target"
  if (-not (Test-Path $dir)) { return $null }
  $jars = Get-ChildItem -Path $dir -Filter "$Module-*.jar" -File |
    Where-Object { $_.Name -notmatch 'sources|javadoc|\.original' } |
    Sort-Object Length -Descending
  if ($jars) { return $jars[0].FullName }
  return $null
}

function Stop-ServiceByName([string]$Name) {
  $pidFile = Join-Path $LogDir "$Name.pid"
  if (-not (Test-Path $pidFile)) { return }
  $procId = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
  if ($procId) {
    Write-Host "[STOP] $Name pid $procId"
    & taskkill.exe /F /T /PID $procId 2>$null | Out-Null
  }
  Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
}

function Wait-Port([int]$Port, [string]$Name) {
  Write-Host "[WAIT] $Name on port $Port (first start can take a few minutes)"
  for ($i = 1; $i -le 90; $i++) {
    try {
      $code = & curl.exe --noproxy '*' -sf -o NUL -w '%{http_code}' "http://127.0.0.1:$Port/actuator/health" 2>$null
      if ($code -eq '200') {
        Write-Host "[ UP ] $Name is ready on $Port"
        return $true
      }
    } catch {}
    try {
      $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/actuator/health" -TimeoutSec 2
      if ($r.StatusCode -eq 200) {
        Write-Host "[ UP ] $Name is ready on $Port"
        return $true
      }
    } catch {}
    if (($i % 15) -eq 0) {
      Write-Host "[WAIT] $Name still starting... $(Join-Path $LogDir "$Name.log")"
    }
    Start-Sleep -Seconds 2
  }
  Write-Host "[FAIL] $Name timed out on port $Port. See $(Join-Path $LogDir "$Name.log")"
  return $false
}

function Start-OneService($Svc) {
  $name = $Svc.Name
  $jar = Find-Jar $name
  if (-not $jar) {
    Write-Host "[FAIL] No runnable jar for $name. Run build.bat first."
    return $false
  }
  $log = Join-Path $LogDir "$name.log"
  $pidFile = Join-Path $LogDir "$name.pid"
  Write-Host "[RUN ] Starting $name"
  '' | Set-Content -Path $log

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

  # cmd.exe merges stdout/stderr into one log; taskkill /T stops the java child.
  $quotedArgs = ($argList | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
  }) -join ' '
  $cmdLine = "`"$Java`" $quotedArgs > `"$log`" 2>&1"
  $p = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $cmdLine) -WorkingDirectory $Root -WindowStyle Hidden -PassThru
  Set-Content -Path $pidFile -Value $p.Id
  return (Wait-Port $Svc.Port $name)
}

if ($Action -eq 'stop') {
  Write-Host ''
  Write-Host ' Eazy Bank  stopping services'
  Write-Host ''
  foreach ($name in @('gatewayserver', 'message', 'loans', 'cards', 'accounts', 'eurekaserver', 'configserver')) {
    Stop-ServiceByName $name
  }
  Write-Host '[DONE] All services stopped.'
  exit 0
}

Write-Host ''
Write-Host " Eazy Bank  starting from $Root"
Write-Host ''

foreach ($svc in $Services) {
  if (-not (Start-OneService $svc)) { exit 1 }
}

Write-Host ''
Write-Host ' Eazy Bank  all services are up'
Write-Host ''
Write-Host '  configserver     http://localhost:8071'
Write-Host '  eurekaserver     http://localhost:8070'
Write-Host '  accounts         http://localhost:8080'
Write-Host '  cards            http://localhost:9000'
Write-Host '  loans            http://localhost:8090'
Write-Host '  message          http://localhost:9010'
Write-Host '  gatewayserver    http://localhost:8072'
Write-Host ''
Write-Host "[LOGS] $LogDir"
Write-Host '[HINT] Stop everything with start-all.bat stop'
exit 0
