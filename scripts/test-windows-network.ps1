[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('lite-vs-network-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
$installer = Join-Path $PSScriptRoot 'install.ps1'
$utf8 = [Text.UTF8Encoding]::new($false)
$savedEnvironment = @{}
$passed = $false
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $lpm = Join-Path $testRoot 'lpm.exe'
  Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/lite-xl/lite-xl-plugin-manager/releases/download/latest/lpm.x86_64-windows.exe' -OutFile $lpm -TimeoutSec 60

  # Inject exactly the native transport failure from the reported Windows bug.
  [IO.File]::WriteAllText((Join-Path $testRoot 'native-failure.lua'), @'
system.request = function(method, protocol, host, port)
  local marker = assert(io.open(os.getenv("LITE_VS_TEST_ROOT") .. "/native-failure-exercised.txt", "w"))
  marker:write(host)
  marker:close()
  error("can't connect to " .. host .. ":" .. tostring(port) .. ": Unknown error")
end
'@, $utf8)
  [IO.File]::WriteAllText((Join-Path $testRoot 'checksum-test.lua'), @'
local target = os.getenv("LITE_VS_TEST_ROOT") .. "/invalid-checksum.txt"
local ok, message = pcall(common.get,
  "https://raw.githubusercontent.com/google/fonts/ec626514f79f831f1ab848a82114a0ce7e2d6372/ofl/inter/OFL.txt",
  { target = target, checksum = string.rep("0", 64) })
assert(not ok and tostring(message):find("checksum doesn't match", 1, true),
  "The fallback must reject corrupted/unexpected downloads: " .. tostring(message))
assert(not system.stat(target), "A checksum failure must not install the payload")
'@, $utf8)
  $wrapper = Join-Path $testRoot 'lpm-test-wrapper.ps1'
  [IO.File]::WriteAllText($wrapper, @'
if ($env:LITE_VS_TEST_MODE -eq 'fail') { $global:LASTEXITCODE = 37; return }
$realLpm = $env:LITE_VS_TEST_LPM
$root = $env:LITE_VS_TEST_ROOT
$injection = "--plugin=$(Join-Path $root 'native-failure.lua')"
$cache = "--cachedir=$(Join-Path $root 'cache')"
$config = "--configdir=$(Join-Path $root 'config')"
$adapter = @($args | Where-Object { $_ -like '--plugin=*' })[0]
if (-not $adapter) { throw 'Installer did not enable the Windows transport adapter.' }
& $realLpm exec (Join-Path $root 'checksum-test.lua') $injection $adapter $cache $config --no-color
if ($LASTEXITCODE -ne 0) { throw 'Checksum rejection test failed.' }
& $realLpm $injection @args $cache $config
$global:LASTEXITCODE = $LASTEXITCODE
'@, $utf8)

  $environment = @{
    LPM_BIN = $wrapper
    LITE_VS_TEST_LPM = $lpm
    LITE_VS_TEST_ROOT = $testRoot
    LITE_VS_TEST_MODE = 'success'
    LITE_VS_LPM_REQUEST = 'original-request-sentinel'
    LITE_VS_LPM_DOWNLOADER = 'original-downloader-sentinel'
    LITE_VS_LPM_TRANSPORT = 'original-transport-sentinel'
  }
  foreach ($name in $environment.Keys) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process')
  }
  $userdir = Join-Path $testRoot "profile with spaces & apostrophe's"
  & $installer -UserDir $userdir -DependencyTransport Auto
  if (-not (Test-Path -LiteralPath (Join-Path $testRoot 'native-failure-exercised.txt'))) {
    throw 'The native-failure fallback was not exercised.'
  }
  foreach ($relative in @(
    'libraries\font_symbols_nerdfont_mono_regular\SymbolsNerdFontMono-Regular.ttf',
    'libraries\widget\init.lua', 'plugins\settings.lua',
    'plugins\terminal\libterminal.x86_64-windows.dll',
    'plugins\lite_vs_settings.lua', 'fonts\lite-vs\Inter.ttf', 'lite-vs-install.json'
  )) {
    $file = Join-Path $userdir $relative
    if (-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -eq 0) {
      throw "Full dependency installation is incomplete: $relative"
    }
  }
  foreach ($name in @('LITE_VS_LPM_REQUEST', 'LITE_VS_LPM_DOWNLOADER', 'LITE_VS_LPM_TRANSPORT')) {
    if ([Environment]::GetEnvironmentVariable($name, 'Process') -ne $environment[$name]) {
      throw "Installer leaked its temporary environment: $name"
    }
  }

  # An LPM failure must leave an existing project plugin untouched.
  $env:LITE_VS_TEST_MODE = 'fail'
  $failedProfile = Join-Path $testRoot 'failed-profile'
  New-Item -ItemType Directory -Path (Join-Path $failedProfile 'plugins') | Out-Null
  $sentinel = Join-Path $failedProfile 'plugins\lite_vs_layout.lua'
  [IO.File]::WriteAllText($sentinel, 'preserve-existing-layout', $utf8)
  $rejected = $false
  try { & $installer -UserDir $failedProfile }
  catch {
    if ($_.Exception.Message -notmatch 'LPM failed with exit code 37') { throw }
    $rejected = $true
  }
  if (-not $rejected -or [IO.File]::ReadAllText($sentinel) -ne 'preserve-existing-layout' -or
      (Test-Path -LiteralPath (Join-Path $failedProfile 'lite-vs-install.json'))) {
    throw 'Failed dependency installation modified the existing payload or reported success.'
  }
  foreach ($name in @('LITE_VS_LPM_REQUEST', 'LITE_VS_LPM_DOWNLOADER', 'LITE_VS_LPM_TRANSPORT')) {
    if ([Environment]::GetEnvironmentVariable($name, 'Process') -ne $environment[$name]) {
      throw "Failed installation leaked its temporary environment: $name"
    }
  }
  $passed = $true
  Write-Host 'Windows network regression passed: native failure recovered, checksums enforced, failed install preserved existing files.'
} finally {
  foreach ($name in $savedEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
  }
  if ($passed) {
    $resolved = (Resolve-Path -LiteralPath $testRoot).Path
    $parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ((Split-Path -Parent $resolved).TrimEnd('\', '/') -ne $parent -or
        (Split-Path -Leaf $resolved) -notmatch '^lite-vs-network-[0-9a-f-]{36}$') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
  } else { Write-Warning "Test artifacts retained at $testRoot" }
}
