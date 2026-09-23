@echo off
setlocal EnableExtensions
rem Full API regression through the gateway (PowerShell body embedded below).
cd /d "%~dp0"
set "EAZYBANK_ROOT=%CD%"
set "TMPPS=%TEMP%\eazybank-test-all-%RANDOM%%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%~f0'; $o=$env:TMPPS; $lines=Get-Content -LiteralPath $p; $i=0; while ($i -lt $lines.Count -and $lines[$i] -ne 'rem === POWERSHELL ===') { $i++ }; if ($i -ge $lines.Count) { throw 'POWERSHELL marker not found' }; Set-Content -LiteralPath $o -Value (($lines[($i+1)..($lines.Count-1)]) -join [Environment]::NewLine)"
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%" %*
set "ERR=%ERRORLEVEL%"
del /f /q "%TMPPS%" >nul 2>&1
exit /b %ERR%

rem === POWERSHELL ===
# Full API regression through the gateway.
$ErrorActionPreference = 'Continue'
$Root = if ($env:EAZYBANK_ROOT) { $env:EAZYBANK_ROOT } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location $Root

$Gw = if ($env:GATEWAY_URL) { $env:GATEWAY_URL } else { 'http://127.0.0.1:8072' }
$Corr = 'test-all'
$Mobile = '43544' + ('{0:D5}' -f (Get-Random -Maximum 100000))
$script:Pass = 0
$script:Fail = 0
$script:LastCode = ''
$script:LastBody = ''
$Hit = New-Object 'System.Collections.Generic.HashSet[string]'

function Say([string]$Tag, [string]$Msg) {
  $color = switch -Regex ($Tag.Trim()) {
    'PASS|DONE' { 'Green' }
    'FAIL|MISS' { 'Red' }
    'RUN'       { 'Cyan' }
    'INFO'      { 'Yellow' }
    default     { 'Gray' }
  }
  Write-Host -NoNewline '[' -ForegroundColor $color
  Write-Host -NoNewline $Tag -ForegroundColor $color
  Write-Host -NoNewline '] ' -ForegroundColor $color
  Write-Host $Msg
}

function Mark([string]$Spec, [string]$Method, [string]$Path) {
  [void]$Hit.Add("$Spec $Method $Path")
}

function Request([string]$Method, [string]$Url, [string]$Data = '', [string]$ContentType = 'application/json') {
  $tmp = [System.IO.Path]::GetTempFileName()
  $bodyFile = $null
  $curlArgs = New-Object 'System.Collections.Generic.List[string]'
  [void]$curlArgs.AddRange([string[]]@('--noproxy', '*', '-sS', '-o', $tmp, '-w', '%{http_code}', '-X', $Method,
    '-H', "eazybank-correlation-id: $Corr", '--max-time', '20'))
  if ($Data -ne '') {
    # PowerShell + curl.exe --data strips JSON quotes; write body to a file instead.
    $bodyFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($bodyFile, $Data, [System.Text.UTF8Encoding]::new($false))
    [void]$curlArgs.AddRange([string[]]@('-H', "Content-Type: $ContentType", '--data-binary', "@$bodyFile"))
  }
  [void]$curlArgs.Add($Url)
  try {
    $code = & curl.exe @($curlArgs.ToArray()) 2>$null
    if (-not $code) { $code = '000' }
  } catch {
    $code = '000'
  } finally {
    if ($bodyFile) { Remove-Item -Force $bodyFile -ErrorAction SilentlyContinue }
  }
  $script:LastCode = "$code".Trim()
  if (Test-Path $tmp) {
    $script:LastBody = [System.IO.File]::ReadAllText($tmp)
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  } else {
    $script:LastBody = ''
  }
}

function Expect([string]$Name, [string]$Spec, [string]$Method, [string]$Path, [string]$Url, [string]$Want, [string]$Data = '', [string]$ContentType = 'application/json') {
  $attempts = 1
  if ($Url -like '*/eazybank/*') { $attempts = 5 }
  for ($try = 1; $try -le $attempts; $try++) {
    Request $Method $Url $Data $ContentType
    $ok = ($Want -split '\s+') -contains $script:LastCode
    if ($ok) { break }
    # Gateway may return 503 until Eureka registration settles.
    if ($script:LastCode -ne '503' -or $try -eq $attempts) { break }
    Start-Sleep -Seconds 2
  }
  Mark $Spec $Method $Path
  $ok = ($Want -split '\s+') -contains $script:LastCode
  if ($ok) {
    $script:Pass++
    Say 'PASS' "$Name $Method $Path -> $($script:LastCode)"
    return $true
  }
  $script:Fail++
  Say 'FAIL' "$Name $Method $Path -> $($script:LastCode) (want $Want)"
  if ($script:LastBody) {
    $snip = $script:LastBody
    if ($snip.Length -gt 240) { $snip = $snip.Substring(0, 240) }
    Write-Host $snip
  }
  return $false
}

function Contains([string]$Name, [string]$Needle) {
  if ($script:LastBody -like "*$Needle*") {
    $script:Pass++
    Say 'PASS' "$Name body contains $Needle"
    return $true
  }
  $script:Fail++
  Say 'FAIL' "$Name missing $Needle"
  return $false
}

function JsonGet([string]$Key) {
  if ($script:LastBody -match "`"$([regex]::Escape($Key))`"\s*:\s*`"([^`"]+)`"") {
    return $Matches[1]
  }
  return ''
}

function JsonNum([string]$Key) {
  if ($script:LastBody -match "`"$([regex]::Escape($Key))`"\s*:\s*(\d+)") {
    return $Matches[1]
  }
  return ''
}

Write-Host ''
Write-Host ' Eazy Bank  full API check'
Say 'INFO' "Gateway $Gw  mobile $Mobile"
Write-Host ''

Say 'RUN ' 'Accounts'
Expect 'create' 'accounts' 'POST' '/api/create' "$Gw/eazybank/accounts/api/create" '201' "{`"name`":`"Test User`",`"email`":`"test@eazybank.com`",`"mobileNumber`":`"$Mobile`"}" | Out-Null
Expect 'create duplicate' 'accounts' 'POST' '/api/create' "$Gw/eazybank/accounts/api/create" '400' "{`"name`":`"Test User`",`"email`":`"test@eazybank.com`",`"mobileNumber`":`"$Mobile`"}" | Out-Null
Expect 'fetch' 'accounts' 'GET' '/api/fetch' "$Gw/eazybank/accounts/api/fetch?mobileNumber=$Mobile" '200' | Out-Null
Contains 'fetch name' 'Test User' | Out-Null
$accountNumber = JsonNum 'accountNumber'
if (-not $accountNumber) {
  $script:Fail++
  Say 'FAIL' 'account number missing'
} else {
  $script:Pass++
  Say 'PASS' "account number $accountNumber"
  Expect 'update' 'accounts' 'PUT' '/api/update' "$Gw/eazybank/accounts/api/update" '200' "{`"name`":`"Test User`",`"email`":`"updated@eazybank.com`",`"mobileNumber`":`"$Mobile`",`"accountsDto`":{`"accountNumber`":$accountNumber,`"accountType`":`"Savings`",`"branchAddress`":`"123 NewYork`"}}" | Out-Null
  Expect 'fetch after update' 'accounts' 'GET' '/api/fetch' "$Gw/eazybank/accounts/api/fetch?mobileNumber=$Mobile" '200' | Out-Null
  Contains 'email updated' 'updated@eazybank.com' | Out-Null
}
Expect 'contact-info' 'accounts' 'GET' '/api/contact-info' "$Gw/eazybank/accounts/api/contact-info" '200' | Out-Null
Contains 'contact payload' 'contactDetails' | Out-Null
Expect 'build-info' 'accounts' 'GET' '/api/build-info' "$Gw/eazybank/accounts/api/build-info" '200' | Out-Null
Expect 'java-version' 'accounts' 'GET' '/api/java-version' "$Gw/eazybank/accounts/api/java-version" '200' | Out-Null

Write-Host ''
Say 'RUN ' 'Cards'
Expect 'create' 'cards' 'POST' '/api/create' "$Gw/eazybank/cards/api/create?mobileNumber=$Mobile" '201' | Out-Null
Expect 'fetch' 'cards' 'GET' '/api/fetch' "$Gw/eazybank/cards/api/fetch?mobileNumber=$Mobile" '200' | Out-Null
$cardNumber = JsonGet 'cardNumber'
if (-not $cardNumber) {
  $script:Fail++
  Say 'FAIL' 'card number missing'
} else {
  $script:Pass++
  Say 'PASS' "card number $cardNumber"
  Expect 'update' 'cards' 'PUT' '/api/update' "$Gw/eazybank/cards/api/update" '200' "{`"mobileNumber`":`"$Mobile`",`"cardNumber`":`"$cardNumber`",`"cardType`":`"Credit Card`",`"totalLimit`":200000,`"amountUsed`":1000,`"availableAmount`":199000}" | Out-Null
  Expect 'fetch after update' 'cards' 'GET' '/api/fetch' "$Gw/eazybank/cards/api/fetch?mobileNumber=$Mobile" '200' | Out-Null
  Contains 'limit updated' '200000' | Out-Null
}
Expect 'contact-info' 'cards' 'GET' '/api/contact-info' "$Gw/eazybank/cards/api/contact-info" '200' | Out-Null
Expect 'build-info' 'cards' 'GET' '/api/build-info' "$Gw/eazybank/cards/api/build-info" '200' | Out-Null
Expect 'java-version' 'cards' 'GET' '/api/java-version' "$Gw/eazybank/cards/api/java-version" '200' | Out-Null

Write-Host ''
Say 'RUN ' 'Loans'
Expect 'create' 'loans' 'POST' '/api/create' "$Gw/eazybank/loans/api/create?mobileNumber=$Mobile" '201' | Out-Null
Expect 'fetch' 'loans' 'GET' '/api/fetch' "$Gw/eazybank/loans/api/fetch?mobileNumber=$Mobile" '200' | Out-Null
$loanNumber = JsonGet 'loanNumber'
if (-not $loanNumber) {
  $script:Fail++
  Say 'FAIL' 'loan number missing'
} else {
  $script:Pass++
  Say 'PASS' "loan number $loanNumber"
  Expect 'update' 'loans' 'PUT' '/api/update' "$Gw/eazybank/loans/api/update" '200' "{`"mobileNumber`":`"$Mobile`",`"loanNumber`":`"$loanNumber`",`"loanType`":`"Home Loan`",`"totalLoan`":150000,`"amountPaid`":5000,`"outstandingAmount`":145000}" | Out-Null
  Expect 'fetch after update' 'loans' 'GET' '/api/fetch' "$Gw/eazybank/loans/api/fetch?mobileNumber=$Mobile" '200' | Out-Null
  Contains 'amount updated' '150000' | Out-Null
}
Expect 'contact-info' 'loans' 'GET' '/api/contact-info' "$Gw/eazybank/loans/api/contact-info" '200' | Out-Null
Expect 'build-info' 'loans' 'GET' '/api/build-info' "$Gw/eazybank/loans/api/build-info" '200' | Out-Null
Expect 'java-version' 'loans' 'GET' '/api/java-version' "$Gw/eazybank/loans/api/java-version" '200' | Out-Null

Write-Host ''
Say 'RUN ' 'Customer details'
Expect 'fetchCustomerDetails' 'accounts' 'GET' '/api/fetchCustomerDetails' "$Gw/eazybank/accounts/api/fetchCustomerDetails?mobileNumber=$Mobile" '200' | Out-Null
Contains 'includes card' 'cardNumber' | Out-Null
Contains 'includes loan' 'loanNumber' | Out-Null

Write-Host ''
Say 'RUN ' 'Message'
Expect 'info' 'message' 'GET' '/api/info' "$Gw/eazybank/message/api/info" '200' | Out-Null
Contains 'messaging flag' 'messagingEnabled' | Out-Null

Write-Host ''
Say 'RUN ' 'Gateway'
Expect 'home' 'gateway' 'GET' '/' "$Gw/" '200' | Out-Null
Expect 'contactSupport GET' 'gateway' 'GET' '/contactSupport' "$Gw/contactSupport" '200' | Out-Null
Expect 'contactSupport POST' 'gateway' 'POST' '/contactSupport' "$Gw/contactSupport" '200' | Out-Null
Expect 'contactSupport PUT' 'gateway' 'PUT' '/contactSupport' "$Gw/contactSupport" '200' | Out-Null
Expect 'contactSupport DELETE' 'gateway' 'DELETE' '/contactSupport' "$Gw/contactSupport" '200' | Out-Null
Expect 'contactSupport PATCH' 'gateway' 'PATCH' '/contactSupport' "$Gw/contactSupport" '200' | Out-Null
Contains 'fallback text' 'contact support' | Out-Null

Write-Host ''
Say 'RUN ' 'Config server'
$Cfg = "$Gw/eazybank/configserver"
Expect 'name/profiles' 'configserver' 'GET' '/{name}/{profiles}' "$Cfg/accounts/prod" '200' | Out-Null
Contains 'accounts prod' 'contactDetails' | Out-Null
Expect 'cards prod' 'configserver' 'GET' '/{name}/{profiles}' "$Cfg/cards/prod" '200' | Out-Null
Expect 'loans prod' 'configserver' 'GET' '/{name}/{profiles}' "$Cfg/loans/prod" '200' | Out-Null
Expect 'name/profiles/label' 'configserver' 'GET' '/{name}/{profiles}/{label}' "$Cfg/accounts/prod/main" '200' | Out-Null
Expect 'name/profile/path' 'configserver' 'GET' '/{name}/{profile}/{path}' "$Cfg/accounts/prod/application" '200' | Out-Null
Expect 'name/profile/label/**' 'configserver' 'GET' '/{name}/{profile}/{label}/**' "$Cfg/accounts/prod/main/application" '200 404' | Out-Null
Expect 'name-profiles.yml' 'configserver' 'GET' '/{name}-{profiles}.yml' "$Cfg/accounts-prod.yml" '200' | Out-Null
Expect 'name-profiles.yaml' 'configserver' 'GET' '/{name}-{profiles}.yaml' "$Cfg/accounts-prod.yaml" '200' | Out-Null
Expect 'name-profiles.json' 'configserver' 'GET' '/{name}-{profiles}.json' "$Cfg/accounts-prod.json" '200' | Out-Null
Expect 'name-profiles.properties' 'configserver' 'GET' '/{name}-{profiles}.properties' "$Cfg/accounts-prod.properties" '200' | Out-Null
Expect 'label/name-profiles.yml' 'configserver' 'GET' '/{label}/{name}-{profiles}.yml' "$Cfg/main/accounts-prod.yml" '200' | Out-Null
Expect 'label/name-profiles.yaml' 'configserver' 'GET' '/{label}/{name}-{profiles}.yaml' "$Cfg/main/accounts-prod.yaml" '200' | Out-Null
Expect 'label/name-profiles.json' 'configserver' 'GET' '/{label}/{name}-{profiles}.json' "$Cfg/main/accounts-prod.json" '200' | Out-Null
Expect 'label/name-profiles.properties' 'configserver' 'GET' '/{label}/{name}-{profiles}.properties' "$Cfg/main/accounts-prod.properties" '200' | Out-Null
Expect 'encrypt status' 'configserver' 'GET' '/encrypt/status' "$Cfg/encrypt/status" '200' | Out-Null
Expect 'key' 'configserver' 'GET' '/key' "$Cfg/key" '404' | Out-Null
Contains 'no public key' 'No public key available' | Out-Null
Expect 'encrypt' 'configserver' 'POST' '/encrypt' "$Cfg/encrypt" '200' 'eazybank-test' 'text/plain' | Out-Null
$cipher = $script:LastBody
Expect 'decrypt' 'configserver' 'POST' '/decrypt' "$Cfg/decrypt" '200' $cipher 'text/plain' | Out-Null
Contains 'decrypt plaintext' 'eazybank-test' | Out-Null
Expect 'encrypt named' 'configserver' 'POST' '/encrypt/{name}/{profiles}' "$Cfg/encrypt/accounts/prod" '200' 'eazybank-test' 'text/plain' | Out-Null
$namedCipher = $script:LastBody
Expect 'decrypt named' 'configserver' 'POST' '/decrypt/{name}/{profiles}' "$Cfg/decrypt/accounts/prod" '200' $namedCipher 'text/plain' | Out-Null
Expect 'key named' 'configserver' 'GET' '/key/{name}/{profiles}' "$Cfg/key/accounts/prod" '404' | Out-Null

Write-Host ''
Say 'RUN ' 'Deletes'
Expect 'loan delete' 'loans' 'DELETE' '/api/delete' "$Gw/eazybank/loans/api/delete?mobileNumber=$Mobile" '200' | Out-Null
Expect 'card delete' 'cards' 'DELETE' '/api/delete' "$Gw/eazybank/cards/api/delete?mobileNumber=$Mobile" '200' | Out-Null
Expect 'account delete' 'accounts' 'DELETE' '/api/delete' "$Gw/eazybank/accounts/api/delete?mobileNumber=$Mobile" '200' | Out-Null
Expect 'account gone' 'accounts' 'GET' '/api/fetch' "$Gw/eazybank/accounts/api/fetch?mobileNumber=$Mobile" '404' | Out-Null
Expect 'card gone' 'cards' 'GET' '/api/fetch' "$Gw/eazybank/cards/api/fetch?mobileNumber=$Mobile" '404' | Out-Null
Expect 'loan gone' 'loans' 'GET' '/api/fetch' "$Gw/eazybank/loans/api/fetch?mobileNumber=$Mobile" '404' | Out-Null

Write-Host ''
Say 'RUN ' 'OpenAPI coverage'
$required = @(
  'accounts GET /api/build-info',
  'accounts GET /api/contact-info',
  'accounts POST /api/create',
  'accounts DELETE /api/delete',
  'accounts GET /api/fetch',
  'accounts GET /api/fetchCustomerDetails',
  'accounts GET /api/java-version',
  'accounts PUT /api/update',
  'cards GET /api/build-info',
  'cards GET /api/contact-info',
  'cards POST /api/create',
  'cards DELETE /api/delete',
  'cards GET /api/fetch',
  'cards GET /api/java-version',
  'cards PUT /api/update',
  'loans GET /api/build-info',
  'loans GET /api/contact-info',
  'loans POST /api/create',
  'loans DELETE /api/delete',
  'loans GET /api/fetch',
  'loans GET /api/java-version',
  'loans PUT /api/update',
  'message GET /api/info',
  'gateway GET /',
  'gateway GET /contactSupport',
  'gateway POST /contactSupport',
  'gateway PUT /contactSupport',
  'gateway DELETE /contactSupport',
  'gateway PATCH /contactSupport',
  'configserver POST /decrypt',
  'configserver POST /decrypt/{name}/{profiles}',
  'configserver POST /encrypt',
  'configserver GET /encrypt/status',
  'configserver POST /encrypt/{name}/{profiles}',
  'configserver GET /key',
  'configserver GET /key/{name}/{profiles}',
  'configserver GET /{label}/{name}-{profiles}.json',
  'configserver GET /{label}/{name}-{profiles}.properties',
  'configserver GET /{label}/{name}-{profiles}.yaml',
  'configserver GET /{label}/{name}-{profiles}.yml',
  'configserver GET /{name}-{profiles}.json',
  'configserver GET /{name}-{profiles}.properties',
  'configserver GET /{name}-{profiles}.yaml',
  'configserver GET /{name}-{profiles}.yml',
  'configserver GET /{name}/{profiles}',
  'configserver GET /{name}/{profiles}/{label}',
  'configserver GET /{name}/{profile}/{label}/**',
  'configserver GET /{name}/{profile}/{path}'
)
$covered = 0
$missing = 0
foreach ($op in $required) {
  if ($Hit.Contains($op)) {
    $covered++
  } else {
    $missing++
    Say 'MISS' $op
  }
}
if ($missing -eq 0) {
  $script:Pass++
  Say 'PASS' "every OpenAPI operation was called $covered/$($required.Count)"
} else {
  $script:Fail++
  Say 'FAIL' "untested OpenAPI operations $covered/$($required.Count)"
}

Write-Host ''
$total = $script:Pass + $script:Fail
if ($script:Fail -eq 0) {
  Say 'DONE' "$($script:Pass) passed, $($script:Fail) failed  ($total checks)"
  exit 0
}
Say 'FAIL' "$($script:Pass) passed, $($script:Fail) failed  ($total checks)"
exit 1
