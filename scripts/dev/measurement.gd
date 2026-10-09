class_name Measurement
extends Node
## MEASURE-MODE (T8.1): temporary, developer-only play-time logging used to tune pars from real
## data. Off by default and invisible to players. Enable with the user argument `--measure`
## (`godot --path . -- --measure`) or toggle with F9; while on, the HUD shows a small MEASURE tag.
##
## One Measurement is owned by Level (not an autoload). It tracks every attempt of a mission, from
## a level load or restart until it is completed, lost, restarted or abandoned (the Level left the
## tree), and appends one CSV row per attempt to csv_path (default user://measurements.csv):
##   timestamp,mission_id,result,seconds_to_first_move,total_seconds,moves,restarts_before,stars
## - result: completed | restarted | lost_tension | lost_overload | abandoned
## - total_seconds: active play time only (the controller is PLAYING; the story overlay and the
##   pause are excluded because this node is pausable and ticks only while PLAYING)
## - seconds_to_first_move: active time of the first neuron displacement (blank when none)
## - restarts_before: attempts of this mission already closed in this Level session
## - stars: stars of a completed run, 0 otherwise
## An untouched restarted/abandoned attempt (no active time, no move) is not logged. Tracking is
## always cheap and in memory; rows are written only while enabled. IO errors never crash.
##
## Removal: delete this file, tools/measurement_analysis.gd, tools/analyze_measurements.gd,
## tests/dev/ and every line tagged `# MEASURE-MODE` (see odd/tasks/measure-toxic-bosses.md).

signal enabled_changed(enabled: bool)

const ARG := "--measure"
const TOGGLE_KEY := KEY_F9
const DEFAULT_PATH := "user://measurements.csv"
const HEADER := "timestamp,mission_id,result,seconds_to_first_move,total_seconds,moves,restarts_before,stars"
const COMPLETED := "completed"
const RESTARTED := "restarted"
const LOST_TENSION := "lost_tension"
const LOST_OVERLOAD := "lost_overload"
const ABANDONED := "abandoned"

var csv_path := DEFAULT_PATH
var enabled := false

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


## "2026-10-08T10:00:00Z,m05,completed,3.46,41.20,7,2,3". A negative first_move is left blank.
static func format_row(timestamp: String, mission_id: StringName, result: String, first_move: float,
		total: float, moves: int, restarts: int, stars: int) -> String:
	var first := "" if first_move < 0.0 else "%.2f" % first_move
	return "%s,%s,%s,%s,%.2f,%d,%d,%d" % [timestamp, mission_id, result, first, total, moves, restarts, stars]


## Appends a row (creating the file with its header once). False on any IO error.
static func append_row(path: String, row: String) -> bool:
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
	set_enabled(is_requested(OS.get_cmdline_user_args()))


func _exit_tree() -> void:
	if _open:
		_close_attempt(ABANDONED)


func _process(delta: float) -> void:
	tick(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == TOGGLE_KEY:
		set_enabled(not enabled)


func setup(controller: LevelController) -> void:
	_controller = controller
	controller.model_built.connect(_on_model_built)
	controller.level_completed.connect(_on_level_completed)
	controller.level_lost.connect(_on_level_lost)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	enabled_changed.emit(value)


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
		_close_attempt(LOST_OVERLOAD if reason == LevelController.LossReason.OVERLOAD else LOST_TENSION)


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
	append_row(csv_path, format_row(timestamp, _mission_id, result, _first_move, _active, moves, restarts, stars))
