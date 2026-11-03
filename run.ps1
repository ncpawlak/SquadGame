# Imports any new or changed assets, then starts the game. Plain `godot --path .` skips the import, so heads
# added since your last editor session come up as blank discs. Usage: ./run.ps1 [extra godot args]
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) {
    $pkg = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $godot = Get-ChildItem $pkg -Recurse -Filter "Godot_v*_win64.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "console" } | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $godot) { throw "Godot not found. Install it with: winget install GodotEngine.GodotEngine" }

# Incremental: only assets missing from (or newer than) the .godot cache are imported.
& $godot --headless --path . --import 2>&1 | Out-Null

# The import also re-saves tracked .import files with different line endings; put those back so git stays clean.
# Files with a real content change are left alone.
if (Test-Path .git) {
    # ls-files -m, not diff --name-only: with autocrlf the line-ending-only files show up in status but not in diff.
    foreach ($f in (git ls-files -m -- "*.import" 2>$null)) {
        if (-not (git diff -w --numstat -- $f 2>$null)) { git checkout -- $f 2>$null }
    }
}

& $godot --path . @args
