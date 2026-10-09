class_name Level
extends Node2D
## Composition root of one mission (SDD 8.4). Holds no rules: it wires LevelController and
## HUD together (signals up, calls down), forwards load_level() and owns the pause.
## ScreenHost listens to get_controller().level_completed and to the navigation intents below.
##
## Pause: pausing sets SceneTree.paused; the Level subtree (controller timer, input) is pausable
## while the HUD runs with PROCESS_MODE_ALWAYS to show the pause overlay. Only allowed while
## PLAYING. Leaving the tree while paused always unpauses.
##
## Boss missions (T8.6): load_level() first plays the boss intro card (HUD), then shows the story (if
## any) and starts playing; the membrane and vignette take the boss look. The intro opens one frame
## later (deferred), so the screen host can bind the audio first. A restart never replays it.
##
## Completion: the playfield plays its light wave first (LevelFx) and the summary appears when
## it ends (immediately with reduced motion). A restart or reload meanwhile cancels the summary.

signal next_mission_requested()
signal mission_select_requested()
## T8.6: the boss intro card opened (the AudioDirector plays the stinger).
signal boss_intro_started()

@onready var _controller: LevelController = $LevelController
@onready var _hud: Hud = $HUD
@onready var _fx: LevelFx = $Playfield/Fx
@onready var _input: InputController = $InputController
@onready var _background: BackgroundView = $Background

var _measurement: Measurement  # MEASURE-MODE
var _paused := false
var _next_mission_available := false
## Bumped on every completion, restart and load; a pending summary only shows if unchanged.
var _completion_serial := 0


func _ready() -> void:
	_controller.move_count_changed.connect(_hud.set_moves)
	_controller.time_changed.connect(_hud.set_time)
	_controller.contamination_changed.connect(_hud.set_contaminated)
	_controller.diseased_progress_changed.connect(_hud.set_diseased_progress)
	_controller.level_completed.connect(_on_level_completed)
	_controller.level_restart_requested.connect(_on_level_restarted)
	_hud.restart_pressed.connect(_on_restart_pressed)
	_hud.story_dismissed.connect(_controller.start_playing)
	_hud.boss_intro_finished.connect(_on_boss_intro_finished)
	_hud.pause_requested.connect(pause)
	_hud.resume_pressed.connect(resume)
	_hud.next_mission_pressed.connect(next_mission_requested.emit)
	_hud.mission_select_pressed.connect(_on_mission_select_pressed)
	_measurement = Measurement.new()  # MEASURE-MODE
	add_child(_measurement)  # MEASURE-MODE
	_measurement.setup(_controller)  # MEASURE-MODE
	_measurement.enabled_changed.connect(_hud.set_measure_indicator)  # MEASURE-MODE
	_hud.set_measure_indicator(_measurement.enabled)  # MEASURE-MODE


func _exit_tree() -> void:
	if _paused:
		_set_paused(false)


func load_level(level: LevelData) -> void:
	resume()
	_completion_serial += 1
	_hud.hide_completion()
	set_next_mission_available(false)
	_hud.set_mission_title(level.mission_name)
	_hud.set_boss(level.is_boss)
	_background.set_boss_look(level.is_boss)
	_controller.load_level(level)
	_hud.hide_story()
	if level.is_boss:
		_start_boss_intro.call_deferred(level, _completion_serial)
	elif _controller.get_state() == LevelController.State.INTRO:
		_hud.show_story(level.story_text)


func get_controller() -> LevelController:
	return _controller


func get_measurement() -> Measurement:  # MEASURE-MODE
	return _measurement  # MEASURE-MODE


func get_hud() -> Hud:
	return _hud


func get_input_controller() -> InputController:
	return _input


## Pauses the mission (only while PLAYING) and shows the pause overlay.
func pause() -> void:
	if _paused or _controller.get_state() != LevelController.State.PLAYING:
		return
	_set_paused(true)
	_hud.show_pause()


func resume() -> void:
	if not _paused:
		return
	_set_paused(false)
	_hud.hide_pause()


func is_paused() -> bool:
	return _paused


## Called by ScreenHost after the result is recorded.
func set_next_mission_available(available: bool) -> void:
	_next_mission_available = available
	_hud.set_next_mission_available(available)


func _set_paused(value: bool) -> void:
	_paused = value
	if is_inside_tree():
		get_tree().paused = value


func _on_restart_pressed() -> void:
	resume()
	_controller.restart()


func _on_mission_select_pressed() -> void:
	resume()
	mission_select_requested.emit()


func _start_boss_intro(level: LevelData, serial: int) -> void:
	# A newer load_level() or a restart meanwhile cancels this intro.
	if serial != _completion_serial or _controller.get_level() != level or not is_inside_tree():
		return
	_hud.show_boss_intro(level.mission_name)
	boss_intro_started.emit()


func _on_boss_intro_finished() -> void:
	var level := _controller.get_level()
	if level == null or _controller.get_state() != LevelController.State.INTRO:
		return
	if level.story_text.strip_edges().is_empty():
		_controller.start_playing()
	else:
		_hud.show_story(level.story_text)


func _on_level_completed(result: LevelResult) -> void:
	_completion_serial += 1
	var serial := _completion_serial
	var level := _controller.get_level()
	var delay := _fx.play_completion_wave(level != null and level.is_boss)
	if delay > 0.0 and is_inside_tree():
		# A bound callable (not await): if the Level is freed first, the connection just goes away.
		get_tree().create_timer(delay, false).timeout.connect(_show_completion.bind(serial, result))
	else:
		_show_completion(serial, result)


func _show_completion(serial: int, result: LevelResult) -> void:
	if serial != _completion_serial:
		return
	_hud.show_completion(result)
	# Re-offer after showing so the Next button gets focus when it is available.
	_hud.set_next_mission_available(_next_mission_available)


func _on_level_restarted() -> void:
	_completion_serial += 1
	_hud.hide_completion()
	_hud.hide_story()
