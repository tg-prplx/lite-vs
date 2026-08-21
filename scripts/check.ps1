[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failed = $false

Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' | ForEach-Object {
  $tokens = $null
  $errors = $null
  [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
  foreach ($parseError in $errors) {
    Write-Error "$($_.FullName): $($parseError.Message)" -ErrorAction Continue
    $failed = $true
  }
}

$lua = Get-Command luac -ErrorAction SilentlyContinue
if ($lua) {
  Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.lua' | ForEach-Object {
    & $lua.Source -p $_.FullName
    if ($LASTEXITCODE -ne 0) { $failed = $true }
  }
} else {
  Write-Warning 'luac is not on PATH; Lua parser validation was skipped locally.'
}

$forbiddenExtensions = @('.dll', '.exe', '.so', '.dylib', '.lib', '.ttf', '.otf')
$forbiddenNames = @('session.lua', 'font_cache.lua', 'error.txt')
$assets = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
  $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() -or
  $forbiddenNames -contains $_.Name.ToLowerInvariant()
}
if ($assets) {
  $assets | ForEach-Object { Write-Error "Forbidden asset: $($_.FullName)" -ErrorAction Continue }
  $failed = $true
}

$codeFiles = Get-ChildItem -LiteralPath (Join-Path $root 'plugins'),(Join-Path $root 'colors') -File
$forbiddenText = 'microsoft_visual_studio_code|visual studio code|copilot|C:\\Windows\\Fonts'
foreach ($file in $codeFiles) {
  $match = Select-String -LiteralPath $file.FullName -Pattern $forbiddenText
  if ($match) {
    Write-Error "Forbidden brand or platform reference in $($file.FullName)" -ErrorAction Continue
    $failed = $true
  }
}

if ($failed) { exit 1 }
Write-Host 'All local checks passed.' -ForegroundColor Green
