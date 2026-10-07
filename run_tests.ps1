# Runs the gdUnit4 suite headless. Usage: ./run_tests.ps1 [res://tests/path]
param([string]$Target = "res://tests")

# Import first so class_name caches and resources are up to date. Fail loudly if it breaks.
$importOutput = godot --headless --path $PSScriptRoot --import 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Godot import failed (exit code $LASTEXITCODE):" -ForegroundColor Red
    $importOutput | ForEach-Object { Write-Host $_ }
    exit $LASTEXITCODE
}

godot --headless --path $PSScriptRoot -s -d --remote-debug tcp://127.0.0.1:0 `
    res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a $Target
exit $LASTEXITCODE
