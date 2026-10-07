class_name Hud
extends CanvasLayer
## Minimal in-level HUD (SDD 4, 6, 7.1, 8.5): mission title, moves, time (mm:ss), restart
## button, story overlay dismissed by click/tap, and a completion panel with stars.
## Calls come down from the Level; user intent goes up through signals.
## Non-interactive nodes use mouse_filter IGNORE so drags reach the InputController.

signal restart_pressed()
signal story_dismissed()

@onready var _mission_label: Label = $TopBar/Row/MissionLabel
@onready var _moves_label: Label = $TopBar/Row/MovesLabel
@onready var _time_label: Label = $TopBar/Row/TimeLabel
@onready var _restart_button: Button = $TopBar/Row/RestartButton
@onready var _story_overlay: Control = $StoryOverlay
@onready var _story_label: Label = $StoryOverlay/Center/Column/StoryLabel
@onready var _completion_overlay: Control = $CompletionOverlay
@onready var _star_row: StarRow = $CompletionOverlay/Center/Panel/Column/Stars
@onready var _stats_label: Label = $CompletionOverlay/Center/Panel/Column/StatsLabel
@onready var _replay_button: Button = $CompletionOverlay/Center/Panel/Column/ReplayButton


func _ready() -> void:
	_restart_button.pressed.connect(restart_pressed.emit)
	_replay_button.pressed.connect(restart_pressed.emit)
	_story_overlay.gui_input.connect(_on_story_gui_input)
	_story_overlay.hide()
	_completion_overlay.hide()
	set_moves(0)
	set_time(0.0)


## "mm:ss"; minutes keep counting past 59.
static func format_time(seconds: float) -> String:
	var total := floori(maxf(seconds, 0.0))
	return "%02d:%02d" % [floori(total / 60.0), total % 60]


func set_mission_title(title: String) -> void:
	_mission_label.text = title


func set_moves(count: int) -> void:
	_moves_label.text = "Moves %d" % count


func set_time(seconds: float) -> void:
	_time_label.text = format_time(seconds)


func show_story(text: String) -> void:
	_story_label.text = text
	_story_overlay.show()


func hide_story() -> void:
	_story_overlay.hide()


func show_completion(result: LevelResult) -> void:
	_star_row.stars = result.stars
	_stats_label.text = "Moves %d    Time %s" % [result.moves, format_time(result.time)]
	_completion_overlay.show()
	_replay_button.grab_focus()


func hide_completion() -> void:
	_completion_overlay.hide()


func is_story_visible() -> bool:
	return _story_overlay.visible


func is_completion_visible() -> bool:
	return _completion_overlay.visible


func get_mission_text() -> String:
	return _mission_label.text


func get_moves_text() -> String:
	return _moves_label.text


func get_time_text() -> String:
	return _time_label.text


func get_story_text() -> String:
	return _story_label.text


func get_star_count() -> int:
	return _star_row.stars


func get_completion_stats_text() -> String:
	return _stats_label.text


func get_restart_button() -> Button:
	return _restart_button


func get_replay_button() -> Button:
	return _replay_button


func _unhandled_input(event: InputEvent) -> void:
	if is_story_visible() and event.is_action_pressed(&"ui_accept"):
		_dismiss_story()
		get_viewport().set_input_as_handled()


func _on_story_gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	# The overlay's mouse_filter is STOP, so the click never reaches the playfield.
	if pressed:
		_dismiss_story()


func _dismiss_story() -> void:
	if not is_story_visible():
		return
	hide_story()
	story_dismissed.emit()
