[CmdletBinding()]
param(
  [string] $UserDir = (Join-Path $HOME '.config\lite-xl'),
  [switch] $RestoreLatestBackup
)

$ErrorActionPreference = 'Stop'
$files = @(
  'colors/lite-vs-dark.lua',
  'plugins/lite_vs_bootstrap.lua',
  'plugins/lite_vs_layout.lua',
  'plugins/lite_vs_workbench.lua',
  'plugins/lite_vs_workbench_full.lua',
  'plugins/language_python_lite_vs.lua',
  'fonts/lite-vs/Inter.ttf',
  'fonts/lite-vs/OFL.txt'
)

$backupRoot = $null
if ($RestoreLatestBackup) {
  $backupRoot = Get-ChildItem -LiteralPath (Join-Path $UserDir 'lite-vs-backups') `
    -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | `
    Select-Object -First 1 -ExpandProperty FullName
  if (-not $backupRoot) { throw 'No lite-vs backup was found.' }
}

foreach ($relative in $files) {
  $nativeRelative = $relative -replace '/', '\'
  $target = Join-Path $UserDir $nativeRelative
  $backup = if ($backupRoot) { Join-Path $backupRoot $nativeRelative } else { $null }
  if ($backup -and (Test-Path -LiteralPath $backup)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $backup -Destination $target -Force
  } elseif (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Force
  }
}

$state = Join-Path $UserDir 'lite-vs-install.json'
if (Test-Path -LiteralPath $state) { Remove-Item -LiteralPath $state -Force }

if ($backupRoot) {
  Write-Host "lite-vs removed and the backup from $backupRoot restored." -ForegroundColor Green
} else {
  Write-Host 'lite-vs removed. Shared LPM dependencies and backups were kept.' -ForegroundColor Green
}
