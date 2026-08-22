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
  $_.FullName -notlike "$root\.git\*" -and
  $_.FullName -notlike "$root\work\*" -and
  (
  $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() -or
  $forbiddenNames -contains $_.Name.ToLowerInvariant()
  )
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

$expectedPriorities = [ordered]@{
  'lite_vs_bootstrap.lua' = 0
  'lite_vs_layout.lua' = 101
  'lite_vs_workbench.lua' = 102
  'lite_vs_workbench_full.lua' = 103
  'language_python_lite_vs.lua' = 150
}
foreach ($entry in $expectedPriorities.GetEnumerator()) {
  $path = Join-Path $root "plugins\$($entry.Key)"
  $text = Get-Content -LiteralPath $path -Raw
  $priorityMarker = "-- priority:$($entry.Value)"
  $priorityIndex = $text.IndexOf($priorityMarker, [StringComparison]::Ordinal)
  $versionIndex = $text.IndexOf('-- mod-version:3', [StringComparison]::Ordinal)
  if ($priorityIndex -lt 0 -or $versionIndex -lt 0 -or $priorityIndex -gt $versionIndex) {
    Write-Error "$($entry.Key): priority must be $($entry.Value) and appear before mod-version." -ErrorAction Continue
    $failed = $true
  }
}

$terminalWorkbench = Get-Content -LiteralPath (Join-Path $root 'plugins\lite_vs_workbench_full.lua') -Raw
if ($terminalWorkbench -notmatch 'function\s+TerminalPanel:is\(class\)' -or
    $terminalWorkbench -notmatch 'class\s*==\s*terminal_plugin\.class') {
  Write-Error 'Integrated TerminalPanel must satisfy the upstream TerminalView predicate.' -ErrorAction Continue
  $failed = $true
}

$layout = Get-Content -LiteralPath (Join-Path $root 'plugins\lite_vs_layout.lua') -Raw
if ($layout -notmatch 'toolbar_center_x\s*=\s*ox\s*\+\s*self\.size\.x\s*/\s*2' -or
    $layout -notmatch 'search_x\s*=\s*toolbar_center_x\s*-\s*search_w\s*/\s*2') {
  Write-Error 'The title-bar Search control must remain geometrically centered.' -ErrorAction Continue
  $failed = $true
}

if ($failed) { exit 1 }
Write-Host 'All local checks passed.' -ForegroundColor Green
