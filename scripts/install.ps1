[CmdletBinding()]
param(
  [string] $UserDir = (Join-Path $HOME '.config\lite-xl'),
  [string] $Repository = 'https://github.com/tg-prplx/lite-vs',
  [string] $Branch = 'main',
  [ValidateSet('Auto', 'PowerShell', 'Native')]
  [string] $DependencyTransport = 'Auto',
  [switch] $SkipDependencies
)

$ErrorActionPreference = 'Stop'
$projectFiles = @(
  'colors/lite-vs-dark.lua',
  'plugins/lite_vs_bootstrap.lua',
  'plugins/lite_vs_layout.lua',
  'plugins/lite_vs_workbench.lua',
  'plugins/lite_vs_workbench_full.lua',
  'plugins/lite_vs_settings.lua',
  'plugins/language_python_lite_vs.lua'
)
$fontFiles = @(
  'fonts/lite-vs/Inter.ttf',
  'fonts/lite-vs/OFL.txt'
)
$files = @($projectFiles + $fontFiles)
$fontCommit = 'ec626514f79f831f1ab848a82114a0ce7e2d6372'
$fontUrl = "https://raw.githubusercontent.com/google/fonts/$fontCommit/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf"
$fontLicenseUrl = "https://raw.githubusercontent.com/google/fonts/$fontCommit/ofl/inter/OFL.txt"
$fontSha256 = '29160A80FF49DDCAB2C97711247E08B1FAB27A484A329CE8B813D820DC559031'
$fontLicenseSha256 = '5B9321A4298CFEB6B34354164A1C3AFC3DB114569984C502B9B35D988FD58C57'
$dependencies = @(
  'font_symbols_nerdfont_mono_regular',
  'navigate',
  'nerdicons',
  'plugin_manager',
  'scm',
  'tab_switcher',
  'terminal',
  'settings',
  'json'
)

function Receive-LiteVsFile([string] $Url, [string] $Target) {
  # Windows PowerShell 5.1 may otherwise negotiate obsolete TLS defaults.
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Target -TimeoutSec 60
      return
    } catch {
      if ($attempt -eq 3) { throw }
      Start-Sleep -Seconds $attempt
    }
  }
}

function New-LpmWindowsTransport([string] $TemporaryRoot) {
  # URLs and destination paths travel as JSON, never as shell arguments.
  # The subprocess uses Windows HTTPS/certificate/proxy handling. LPM still
  # owns cache/checksum validation outside system.request.
  $downloader = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$requestPath = $env:LITE_VS_LPM_REQUEST
$responsePath = $requestPath + '.response'
try {
  $request = [IO.File]::ReadAllText($requestPath) | ConvertFrom-Json
  if (([uri]$request.url).Scheme -ne 'https') { throw 'Only HTTPS downloads are allowed.' }
  if ($request.method -notin @('GET', 'HEAD')) { throw 'Unsupported download method.' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $parameters = @{ Uri = $request.url; Method = $request.method; UseBasicParsing = $true; TimeoutSec = 60 }
  if ($request.method -eq 'GET') { $parameters.OutFile = $request.target; $parameters.PassThru = $true }
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try { $response = Invoke-WebRequest @parameters; break }
    catch { if ($attempt -eq 3) { throw }; Start-Sleep -Seconds $attempt }
  }
  $headers = @{}
  foreach ($key in $response.Headers.Keys) {
    # IWR has already followed redirects; do not ask LPM to follow them again.
    if ($key -ne 'Location') { $headers[$key.ToLowerInvariant()] = ($response.Headers[$key] -join ', ') }
  }
  $result = @{ headers = $headers } | ConvertTo-Json -Compress -Depth 4
  [IO.File]::WriteAllText($responsePath, $result, [Text.UTF8Encoding]::new($false))
  exit 0
} catch {
  $result = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($responsePath, $result, [Text.UTF8Encoding]::new($false))
  exit 1
}
'@
  $adapter = @'
-- Transient LPM transport adapter, not a Lite XL editor plugin.
local native_request = assert(system.request, "LPM network API unavailable; update LPM")
local request_path = assert(os.getenv("LITE_VS_LPM_REQUEST"))
local downloader = assert(os.getenv("LITE_VS_LPM_DOWNLOADER"))
local forced = (os.getenv("LITE_VS_LPM_TRANSPORT") or ""):lower() == "powershell"
system.request = function(method, protocol, host, port, path, target, ...)
  if not forced or (method ~= "GET" and method ~= "HEAD") then
    local ok, body, headers = pcall(native_request, method, protocol, host, port, path, target, ...)
    if ok then return body, headers end
    if protocol ~= "https" or (method ~= "GET" and method ~= "HEAD") then error(body) end
    io.stderr:write("LPM native HTTPS failed; retrying with Windows PowerShell: " .. host .. "\n")
  end
  assert(protocol == "https", "Only HTTPS downloads are allowed")
  local output = target or (request_path .. ".body")
  local url = protocol .. "://" .. host .. ":" .. tostring(port) .. path
  local request = assert(io.open(request_path, "wb"))
  request:write(json.encode({ method = method, url = url, target = output }))
  request:close()
  os.remove(request_path .. ".response")
  local ok, _, code = os.execute(downloader)
  local response_file = io.open(request_path .. ".response", "rb")
  local response = response_file and json.decode(response_file:read("*a")) or {}
  if response_file then response_file:close() end
  if not ok or code ~= 0 or response.error then
    error("Windows HTTPS download failed for " .. host .. ": " .. (response.error or "downloader did not complete") ..
      "; check access to this host and your network/proxy settings")
  end
  local body
  if not target and method == "GET" then
    local file = assert(io.open(output, "rb"))
    body = file:read("*a")
    file:close()
    os.remove(output)
  end
  return body, response.headers or {}
end
'@
  $adapterPath = Join-Path $TemporaryRoot 'windows-https.lua'
  [IO.File]::WriteAllText($adapterPath, $adapter, [Text.UTF8Encoding]::new($false))
  $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (-not (Test-Path -LiteralPath $powershell)) { throw 'Windows PowerShell is required for the HTTPS fallback.' }
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($downloader))
  return @{
    Plugin = $adapterPath
    Request = (Join-Path $TemporaryRoot 'download-request.json')
    Command = ('"{0}" -NoLogo -NoProfile -NonInteractive -EncodedCommand {1}' -f $powershell, $encoded)
  }
}

function Get-RawBase([string] $Url, [string] $Ref) {
  $trimmed = $Url.TrimEnd('/') -replace '\.git$', ''
  if ($trimmed -notmatch '^https://github\.com/([^/]+)/([^/]+)$') {
    throw "Repository must be a GitHub HTTPS URL: $Url"
  }
  return "https://raw.githubusercontent.com/$($Matches[1])/$($Matches[2])/$Ref"
}

function Find-Lpm([string] $TargetUserDir, [string] $TemporaryRoot) {
  if ($env:LPM_BIN -and (Test-Path -LiteralPath $env:LPM_BIN)) {
    return (Resolve-Path -LiteralPath $env:LPM_BIN).Path
  }
  $command = Get-Command lpm -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $bundled = Get-ChildItem -LiteralPath (Join-Path $TargetUserDir 'plugins\plugin_manager') `
    -Filter 'lpm*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($bundled) { return $bundled.FullName }

  $download = Join-Path $TemporaryRoot 'lpm.exe'
  $url = 'https://github.com/lite-xl/lite-xl-plugin-manager/releases/download/latest/lpm.x86_64-windows.exe'
  Write-Host 'Downloading the official Lite XL Plugin Manager...'
  Receive-LiteVsFile $url $download
  return $download
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("lite-vs-" + [guid]::NewGuid())
$stagingRoot = Join-Path $temporaryRoot 'source'
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

try {
  $localRoot = $null
  if ($PSScriptRoot) {
    $candidate = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if (Test-Path -LiteralPath (Join-Path $candidate 'plugins\lite_vs_layout.lua')) {
      $localRoot = $candidate
    }
  }

  if ($localRoot) {
    Write-Host "Installing from $localRoot"
    foreach ($relative in $projectFiles) {
      $source = Join-Path $localRoot ($relative -replace '/', '\')
      $target = Join-Path $stagingRoot ($relative -replace '/', '\')
      New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
      Copy-Item -LiteralPath $source -Destination $target
    }
  } else {
    $rawBase = Get-RawBase $Repository $Branch
    Write-Host "Downloading $Repository ($Branch)..."
    foreach ($relative in $projectFiles) {
      $target = Join-Path $stagingRoot ($relative -replace '/', '\')
      New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
      Receive-LiteVsFile "$rawBase/$relative" $target
    }
  }

  $fontTarget = Join-Path $stagingRoot 'fonts\lite-vs\Inter.ttf'
  $fontLicenseTarget = Join-Path $stagingRoot 'fonts\lite-vs\OFL.txt'
  New-Item -ItemType Directory -Path (Split-Path -Parent $fontTarget) -Force | Out-Null
  Write-Host 'Downloading the open-source Inter UI font...'
  Receive-LiteVsFile $fontUrl $fontTarget
  Receive-LiteVsFile $fontLicenseUrl $fontLicenseTarget
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fontTarget).Hash -ne $fontSha256) {
    throw 'Inter font checksum mismatch.'
  }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fontLicenseTarget).Hash -ne $fontLicenseSha256) {
    throw 'Inter license checksum mismatch.'
  }

  foreach ($relative in $files) {
    $source = Join-Path $stagingRoot ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $source) -or (Get-Item -LiteralPath $source).Length -eq 0) {
      throw "Downloaded file is missing or empty: $relative"
    }
  }

  if (-not $SkipDependencies) {
    $lpm = Find-Lpm $UserDir $temporaryRoot
    Write-Host 'Installing cross-platform dependencies through LPM...'
    Write-Host "Dependency HTTPS transport: $DependencyTransport"
    $transportArguments = @()
    $savedEnvironment = @{}
    try {
      if ($DependencyTransport -ne 'Native') {
        $transport = New-LpmWindowsTransport $temporaryRoot
        $environment = @{
          LITE_VS_LPM_REQUEST = $transport.Request
          LITE_VS_LPM_DOWNLOADER = $transport.Command
          LITE_VS_LPM_TRANSPORT = $DependencyTransport
        }
        foreach ($name in $environment.Keys) {
          $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
          [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process')
        }
        $transportArguments = @("--plugin=$($transport.Plugin)")
      }
      & $lpm install @dependencies "--userdir=$UserDir" --mod-version=3 --assume-yes --no-color @transportArguments
      if ($LASTEXITCODE -ne 0) {
        throw "LPM failed with exit code $LASTEXITCODE. Dependency installation is incomplete; lite-vs files were not applied. Check the download error above."
      }
    } finally {
      foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
      }
    }
  }

  $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupRoot = Join-Path $UserDir "lite-vs-backups\$timestamp"
  $hasBackup = $false
  foreach ($relative in $files) {
    $nativeRelative = $relative -replace '/', '\'
    $source = Join-Path $stagingRoot $nativeRelative
    $target = Join-Path $UserDir $nativeRelative
    if (Test-Path -LiteralPath $target) {
      $backup = Join-Path $backupRoot $nativeRelative
      New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
      Copy-Item -LiteralPath $target -Destination $backup
      $hasBackup = $true
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
  }

  $state = [ordered]@{
    repository = $Repository
    branch = $Branch
    installed_at = (Get-Date).ToString('o')
    backup = if ($hasBackup) { $backupRoot } else { $null }
    files = $files
  }
  $state | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $UserDir 'lite-vs-install.json') -Encoding utf8

  Write-Host ''
  Write-Host 'lite-vs installed successfully. Restart Lite XL to apply it.' -ForegroundColor Green
  if ($hasBackup) { Write-Host "Previous files were backed up to $backupRoot" }
} finally {
  if (Test-Path -LiteralPath $temporaryRoot) {
    $resolvedTemp = (Resolve-Path -LiteralPath $temporaryRoot).Path
    $tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ((Split-Path -Parent $resolvedTemp).TrimEnd('\', '/') -ne $tempParent -or
        (Split-Path -Leaf $resolvedTemp) -notmatch '^lite-vs-[0-9a-f-]{36}$') {
      throw "Refusing cleanup outside the installer temporary directory: $resolvedTemp"
    }
    Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
  }
}
