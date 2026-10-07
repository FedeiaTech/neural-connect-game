class_name Level
extends Node2D
## Composition root of one mission (SDD 8.4). Holds no rules: it wires LevelController and
## HUD together (signals up, calls down) and forwards load_level().
## Phase 3's ScreenHost listens to get_controller().level_completed / level_restart_requested.

@onready var _controller: LevelController = $LevelController
@onready var _hud: Hud = $HUD


func _ready() -> void:
	_controller.move_count_changed.connect(_hud.set_moves)
	_controller.time_changed.connect(_hud.set_time)
	_controller.level_completed.connect(_hud.show_completion)
	_controller.level_restart_requested.connect(_on_level_restarted)
	_hud.restart_pressed.connect(_controller.restart)
	_hud.story_dismissed.connect(_controller.start_playing)


func load_level(level: LevelData) -> void:
	_hud.hide_completion()
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


func _on_level_restarted() -> void:
	_hud.hide_completion()
	_hud.hide_story()
