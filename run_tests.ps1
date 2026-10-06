# Runs the gdUnit4 suite headless. Usage: ./run_tests.ps1 [res://tests/path]
param([string]$Target = "res://tests")

godot --headless --path $PSScriptRoot --import | Out-Null
godot --headless --path $PSScriptRoot -s -d --remote-debug tcp://127.0.0.1:0 `
    res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a $Target
exit $LASTEXITCODE
