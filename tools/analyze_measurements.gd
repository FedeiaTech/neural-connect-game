extends SceneTree
## MEASURE-MODE (T8.1) offline tool, not game code: summarizes the measurement log per mission
## and proposes pars (formulas in tools/measurement_analysis.gd).
##
## Run from the project root (PowerShell):
##   godot --headless --path . -s res://tools/analyze_measurements.gd
##   godot --headless --path . -s res://tools/analyze_measurements.gd -- --csv=C:/path/measurements.csv
##   godot --headless --path . -s res://tools/analyze_measurements.gd -- --apply
## The default CSV is user://measurements.csv resolved to its real OS path. --apply rewrites
## par_moves / par_time of the missions WITH data inside tools/level_specs.gd (deterministic;
## missions without a completed run stay untouched); then rebuild with
##   godot --headless --path . -s res://tools/build_levels.gd
## Output per mission: runs, best / median moves and time, the proposed values ready to paste
## into level_specs.gd and the 2-star thresholds they imply (1.5 x par).

const Analysis := preload("res://tools/measurement_analysis.gd")
const SPECS_PATH := "res://tools/level_specs.gd"


func _init() -> void:
	var csv_path := ProjectSettings.globalize_path("user://measurements.csv")
	var apply := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--csv="):
			csv_path = arg.trim_prefix("--csv=")
		elif arg == "--apply":
			apply = true
	var file := FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		printerr("analyze_measurements: cannot read %s (%s)" % [csv_path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	var rows := Analysis.parse_csv(file.get_as_text())
	file.close()
	var stats := Analysis.analyze(rows)
	var proposals := {}
	var ids := stats.keys()
	ids.sort()
	print("analyze_measurements: %d rows from %s" % [rows.size(), csv_path])
	for mission: String in ids:
		var stat: Dictionary = stats[mission]
		var proposal := Analysis.propose(stat)
		if proposal.is_empty():
			print("%s  no data (no completed run)" % mission)
			continue
		proposals[mission] = proposal
		print("%s  runs=%d  moves best/median=%d/%.1f  time best/median=%.1f/%.1f  ->  \"par_moves\": %d, \"par_time\": %.1f,  (2 stars up to %.1f moves / %.1f s)" % [
			mission, stat["runs"], stat["best_moves"], stat["median_moves"], stat["best_time"], stat["median_time"],
			proposal["par_moves"], proposal["par_time"], proposal["two_star_moves"], proposal["two_star_time"]])
	if apply:
		_apply(proposals)
	quit(0)


func _apply(proposals: Dictionary) -> void:
	if proposals.is_empty():
		print("analyze_measurements: nothing to apply")
		return
	var file := FileAccess.open(SPECS_PATH, FileAccess.READ)
	if file == null:
		printerr("analyze_measurements: cannot read %s" % SPECS_PATH)
		return
	var text := file.get_as_text()
	file.close()
	var out := file_text_with_pars(text, proposals)
	var target := FileAccess.open(SPECS_PATH, FileAccess.WRITE)
	if target == null:
		printerr("analyze_measurements: cannot write %s" % SPECS_PATH)
		return
	target.store_string(out)
	target.close()
	print("analyze_measurements: pars of %d mission(s) written to %s" % [proposals.size(), SPECS_PATH])


func file_text_with_pars(text: String, proposals: Dictionary) -> String:
	return Analysis.apply_to_specs(text, proposals)
