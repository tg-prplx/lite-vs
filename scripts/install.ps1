[CmdletBinding()]
param(
  [string] $UserDir = (Join-Path $HOME '.config\lite-xl'),
  [string] $Repository = 'https://github.com/tg-prplx/lite-vs',
  [string] $Branch = 'main',
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
  'json'
)

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
  Invoke-WebRequest -Uri $url -OutFile $download
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
      Invoke-WebRequest -Uri "$rawBase/$relative" -OutFile $target
    }
  }

  $fontTarget = Join-Path $stagingRoot 'fonts\lite-vs\Inter.ttf'
  $fontLicenseTarget = Join-Path $stagingRoot 'fonts\lite-vs\OFL.txt'
  New-Item -ItemType Directory -Path (Split-Path -Parent $fontTarget) -Force | Out-Null
  Write-Host 'Downloading the open-source Inter UI font...'
  Invoke-WebRequest -Uri $fontUrl -OutFile $fontTarget
  Invoke-WebRequest -Uri $fontLicenseUrl -OutFile $fontLicenseTarget
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
    & $lpm install @dependencies "--userdir=$UserDir" --mod-version=3 --assume-yes --no-color
    if ($LASTEXITCODE -ne 0) { throw "LPM failed with exit code $LASTEXITCODE" }
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
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}
