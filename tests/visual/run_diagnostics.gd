extends Node
## Debug runner (not a test suite): plays the whole on-device diagnostic battery in a real window
## with every step shortened, prints the matrix and quits. Catches engine errors in the steps
## without a phone. Uses a temporary state file, so a real run is never touched.
##   godot --path . res://tests/visual/run_diagnostics.tscn -- [seconds_per_step]

const STATE_PATH := "user://run_diagnostics_tmp.json"

var _runner: DiagnosticRunner


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 2.0
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	_runner = DiagnosticRunner.new()
	_runner.state_path = STATE_PATH
	_runner.stage = stage
	_runner.gap_seconds = 0.2
	_runner.steps = DiagnosticSteps.build_all()
	for step in _runner.steps:
		step.duration = minf(step.duration, seconds)
	add_child(_runner)
	_runner.step_started.connect(func(id: String, index: int, total: int) -> void:
		print("run_diagnostics: step %d/%d %s" % [index, total, id]))
	_runner.run_finished.connect(_on_finished)
	_runner.start_new()


func _on_finished() -> void:
	var state := _runner.get_state()
	print(DiagnosticReport.format(state, {"titles": _runner.get_titles()}))
	DiagnosticState.clear(STATE_PATH)
	get_tree().quit()
