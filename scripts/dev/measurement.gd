class_name Measurement
extends Node
## MEASURE-MODE (T8.1): temporary, developer-only play-time logging used to tune pars from real
## data. Invisible to players. Start the session with a streak already ON with the user argument
## `--measure` (`godot --path . -- --measure`) or toggle streaks with F9.
##
## Streaks: F9 ON starts a new streak (id = UTC `YYYYMMDD-HHMMSS`), F9 OFF closes it, so play time
## is recorded in separate sessions. The ON/OFF state and the streak live in script-level statics
## (Levels are recreated for every mission; no autoload) and are read by each new Level. Turning ON
## while a mission is in progress restarts the attempt (no row for the discarded one); turning OFF
## mid-attempt logs nothing. The HUD (debug builds only) always shows the state.
##
## One Measurement is owned by Level (not an autoload). It tracks every attempt of a mission, from
## a level load or restart until it is completed, lost, restarted or abandoned (the Level left the
## tree), and, while a streak is ON, appends one CSV row per attempt to csv_path (default
## user://measurements.csv):
##   timestamp,streak,mission_id,result,seconds_to_first_move,total_seconds,moves,restarts_before,stars
## - result: completed | restarted | lost_tension | lost_overload | abandoned
## - total_seconds: active play time only (the controller is PLAYING; the story overlay and the
##   pause are excluded because this node is pausable and ticks only while PLAYING)
## - seconds_to_first_move: active time of the first neuron displacement (blank when none)
## - restarts_before: attempts of this mission already closed in this Level session
## - stars: stars of a completed run, 0 otherwise
## An untouched restarted/abandoned attempt (no active time, no move) is not logged. Tracking is
## always cheap and in memory. IO errors never crash. A file with an older header is rotated to
## measurements.legacy.csv (never lost) and a new file is started.
##
## Removal: delete this file, tools/measurement_analysis.gd, tools/analyze_measurements.gd,
## tests/dev/ and every line tagged `# MEASURE-MODE` (see odd/tasks/measure-toxic-bosses.md).

## Streak state or run counter changed (feeds the HUD indicator).
signal streak_changed(active: bool, streak_id: String, runs: int)
## A streak was started or closed: a short message for the HUD toast.
signal toggled(message: String)

const ARG := "--measure"
const TOGGLE_KEY := KEY_F9
const DEFAULT_PATH := "user://measurements.csv"
const HEADER := "timestamp,streak,mission_id,result,seconds_to_first_move,total_seconds,moves,restarts_before,stars"
const COMPLETED := "completed"
const RESTARTED := "restarted"
const LOST_TENSION := "lost_tension"
const LOST_OVERLOAD := "lost_overload"
const ABANDONED := "abandoned"

## Session-wide streak state (survives Level recreation). Empty id = OFF.
static var streak_id := ""
## Completed runs logged in the current streak.
static var streak_runs := 0
static var _last_streak_id := ""
static var _args_applied := false
## -1 = ask OS.is_debug_build(), 0 = pretend a release build, 1 = pretend a debug build (tests).
static var debug_build_override := -1

var csv_path := DEFAULT_PATH
## True while a streak is ON (read-only view of the static state).
var enabled: bool:
	get:
		return not streak_id.is_empty()

var _controller: LevelController
var _model: PuzzleModel
var _mission_id: StringName = &""
var _open := false
var _active := 0.0
var _first_move := -1.0
## Closed attempts per mission in this session (feeds restarts_before).
var _closed: Dictionary[StringName, int] = {}


static func is_requested(args: PackedStringArray) -> bool:
	return args.has(ARG)


## Whether the HUD indicator may be shown: debug builds only.
static func indicator_allowed() -> bool:
	if debug_build_override >= 0:
		return debug_build_override == 1
	return OS.is_debug_build()


## "20261009-153000" from a datetime dictionary (Time.get_datetime_dict_from_system(true)).
static func format_streak_id(dt: Dictionary) -> String:
	return "%04d%02d%02d-%02d%02d%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]]


## A streak id unique within this session: a repeat of the previous id gets a -2, -3... suffix.
static func unique_streak_id(base: String) -> String:
	if base != _last_streak_id and not _last_streak_id.begins_with(base + "-"):
		return base
	var n := 2
	while "%s-%d" % [base, n] == _last_streak_id:
		n += 1
	return "%s-%d" % [base, n]


## Back to the initial state: no streak, user args not yet applied. Tests call this.
static func reset_session() -> void:
	streak_id = ""
	streak_runs = 0
	_last_streak_id = ""
	_args_applied = false
	debug_build_override = -1


## "2026-10-08T10:00:00Z,20261008-100000,m05,completed,3.46,41.20,7,2,3". A negative first_move is blank.
static func format_row(timestamp: String, streak: String, mission_id: StringName, result: String,
		first_move: float, total: float, moves: int, restarts: int, stars: int) -> String:
	var first := "" if first_move < 0.0 else "%.2f" % first_move
	return "%s,%s,%s,%s,%s,%.2f,%d,%d,%d" % [timestamp, streak, mission_id, result, first, total, moves, restarts, stars]


## Moves a file whose header is not the current one to <name>.legacy.csv (.legacy2.csv, ... when
## taken) and returns true. A missing, empty or current file is left alone.
static func rotate_if_legacy(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var empty := file.get_length() == 0
	var first := file.get_line().strip_edges()
	file.close()
	if empty or first == HEADER:
		return false
	var base := path.get_basename()
	var target := base + ".legacy.csv"
	var n := 2
	while FileAccess.file_exists(target):
		target = "%s.legacy%d.csv" % [base, n]
		n += 1
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(target))
	if error != OK:
		push_warning("Measurement: cannot rotate %s (%s)." % [path, error_string(error)])
		return false
	return true


## Appends a row (creating the file with its header once). False on any IO error.
static func append_row(path: String, row: String) -> bool:
	rotate_if_legacy(path)
	var existed := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
	if file == null:
		push_warning("Measurement: cannot write %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false
	if existed:
		file.seek_end()
	else:
		file.store_line(HEADER)
	file.store_line(row)
	file.close()
	return true


func _ready() -> void:
	# The --measure argument starts the session with a streak ON (once, not for every Level).
	if not _args_applied:
		_args_applied = true
		if is_requested(OS.get_cmdline_user_args()) and not enabled:
			_begin_streak(false)


func _exit_tree() -> void:
	if _open:
		_close_attempt(ABANDONED)


func _process(delta: float) -> void:
	tick(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == TOGGLE_KEY:
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func setup(controller: LevelController) -> void:
	_controller = controller
	controller.model_built.connect(_on_model_built)
	controller.level_completed.connect(_on_level_completed)
	controller.level_lost.connect(_on_level_lost)


## Starts (true) or closes (false) a streak. No-op when already in that state.
func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	if value:
		_begin_streak(true)
	else:
		var runs := streak_runs
		streak_id = ""
		streak_runs = 0
		streak_changed.emit(false, "", 0)
		toggled.emit("Streak closed: %d run%s" % [runs, "" if runs == 1 else "s"])


## Adds delta to the active clock, only while the controller is PLAYING (story and result
## screens do not count; a paused tree never calls this).
func tick(delta: float) -> void:
	if _open and _controller != null and _controller.get_state() == LevelController.State.PLAYING:
		_active += delta


func get_active_seconds() -> float:
	return _active


## Active time of the first neuron displacement of this attempt, -1 before it.
func get_first_move_seconds() -> float:
	return _first_move


## Attempts of the current mission already closed in this session.
func get_restarts_before() -> int:
	return _closed.get(_mission_id, 0)


## Pushes the current state to the listeners (a new Level reads the session state this way).
func publish_state() -> void:
	streak_changed.emit(enabled, streak_id, streak_runs)


func _begin_streak(restart_attempt: bool) -> void:
	streak_id = unique_streak_id(format_streak_id(Time.get_datetime_dict_from_system(true)))
	_last_streak_id = streak_id
	streak_runs = 0
	# A partial attempt in progress is discarded without a row: the logged attempt starts at 0.
	if restart_attempt and _controller != null and _controller.get_state() == LevelController.State.PLAYING:
		_open = false
		_controller.restart()
	streak_changed.emit(true, streak_id, 0)
	toggled.emit("Streak started: %s" % streak_id)


func _on_model_built(model: PuzzleModel) -> void:
	var level := _controller.get_level()
	var mission := level.mission_id if level != null else &""
	if _open:
		_close_attempt(RESTARTED if mission == _mission_id else ABANDONED)
	_model = model
	_mission_id = mission
	_open = true
	_active = 0.0
	_first_move = -1.0
	model.neuron_moved.connect(_on_neuron_moved)


func _on_neuron_moved(_id: int, _pos: Vector2) -> void:
	if _first_move < 0.0:
		_first_move = _active


func _on_level_completed(result: LevelResult) -> void:
	if _open:
		_close_attempt(COMPLETED, result.stars)


func _on_level_lost(reason: LevelController.LossReason) -> void:
	if _open:
		_close_attempt(LOST_OVERLOAD if reason in [LevelController.LossReason.OVERLOAD, LevelController.LossReason.TOXIC_OVERLOAD] else LOST_TENSION)


func _close_attempt(result: String, stars := 0) -> void:
	_open = false
	var moves := _model.get_move_count() if _model != null else 0
	var untouched := _active <= 0.0 and moves == 0 and _first_move < 0.0
	if untouched and (result == RESTARTED or result == ABANDONED):
		return
	var restarts := get_restarts_before()
	_closed[_mission_id] = restarts + 1
	if not enabled:
		return
	var timestamp := Time.get_datetime_string_from_system(true) + "Z"
	var row := format_row(timestamp, streak_id, _mission_id, result, _first_move, _active, moves, restarts, stars)
	if append_row(csv_path, row) and result == COMPLETED:
		streak_runs += 1
		streak_changed.emit(true, streak_id, streak_runs)
