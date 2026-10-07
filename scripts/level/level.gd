class_name Level
extends Node2D
## Composition root of one mission (SDD 8.4). Holds no rules: it wires LevelController and
## HUD together (signals up, calls down), forwards load_level() and owns the pause.
## ScreenHost listens to get_controller().level_completed and to the navigation intents below.
##
## Pause: pausing sets SceneTree.paused; the Level subtree (controller timer, input) is pausable
## while the HUD runs with PROCESS_MODE_ALWAYS to show the pause overlay. Only allowed while
## PLAYING. Leaving the tree while paused always unpauses.

signal next_mission_requested()
signal mission_select_requested()

@onready var _controller: LevelController = $LevelController
@onready var _hud: Hud = $HUD

var _paused := false


func _ready() -> void:
	_controller.move_count_changed.connect(_hud.set_moves)
	_controller.time_changed.connect(_hud.set_time)
	_controller.level_completed.connect(_hud.show_completion)
	_controller.level_restart_requested.connect(_on_level_restarted)
	_hud.restart_pressed.connect(_on_restart_pressed)
	_hud.story_dismissed.connect(_controller.start_playing)
	_hud.pause_requested.connect(pause)
	_hud.resume_pressed.connect(resume)
	_hud.next_mission_pressed.connect(next_mission_requested.emit)
	_hud.mission_select_pressed.connect(_on_mission_select_pressed)


func _exit_tree() -> void:
	if _paused:
		_set_paused(false)


func load_level(level: LevelData) -> void:
	resume()
	_hud.hide_completion()
	_hud.set_next_mission_available(false)
	_hud.set_mission_title(level.mission_name)
	_controller.load_level(level)
	if _controller.get_state() == LevelController.State.INTRO:
		_hud.show_story(level.story_text)
	else:
		_hud.hide_story()


func get_controller() -> LevelController:
	return _controller


func get_hud() -> Hud:
	return _hud


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


func _on_level_restarted() -> void:
	_hud.hide_completion()
	_hud.hide_story()
