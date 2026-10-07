class_name Hud
extends CanvasLayer
## Minimal in-level HUD (SDD 4, 6, 7.1, 8.5): mission title, moves, time (mm:ss), restart
## button, story overlay dismissed by click/tap, and a completion panel with stars.
## T3.1 adds: Next mission / Mission select on the completion panel and a pause overlay
## (Resume, Restart, Mission select) toggled by the `pause` action or the Pause button.
## Calls come down from the Level; user intent goes up through signals.
## Non-interactive nodes use mouse_filter IGNORE so drags reach the InputController.
## The HUD runs with PROCESS_MODE_ALWAYS so the pause overlay works while the tree is paused.

signal restart_pressed()
signal story_dismissed()
signal pause_requested()
signal resume_pressed()
signal next_mission_pressed()
signal mission_select_pressed()

const COMPLETION := "CompletionOverlay/Center/Panel/Column/"
const PAUSE := "PauseOverlay/Center/Panel/Column/"

@onready var _mission_label: Label = $TopBar/Row/MissionLabel
@onready var _moves_label: Label = $TopBar/Row/MovesLabel
@onready var _time_label: Label = $TopBar/Row/TimeLabel
@onready var _restart_button: Button = $TopBar/Row/RestartButton
@onready var _pause_button: Button = $TopBar/Row/PauseButton
@onready var _story_overlay: Control = $StoryOverlay
@onready var _story_label: Label = $StoryOverlay/Center/Column/StoryLabel
@onready var _completion_overlay: Control = $CompletionOverlay
@onready var _star_row: StarRow = get_node(COMPLETION + "Stars")
@onready var _stats_label: Label = get_node(COMPLETION + "StatsLabel")
@onready var _next_button: Button = get_node(COMPLETION + "Buttons/NextButton")
@onready var _replay_button: Button = get_node(COMPLETION + "Buttons/ReplayButton")
@onready var _mission_select_button: Button = get_node(COMPLETION + "Buttons/MissionSelectButton")
@onready var _pause_overlay: Control = $PauseOverlay
@onready var _resume_button: Button = get_node(PAUSE + "ResumeButton")
@onready var _pause_restart_button: Button = get_node(PAUSE + "RestartButton")
@onready var _pause_mission_select_button: Button = get_node(PAUSE + "MissionSelectButton")


func _ready() -> void:
	_restart_button.pressed.connect(restart_pressed.emit)
	_replay_button.pressed.connect(restart_pressed.emit)
	_pause_button.pressed.connect(pause_requested.emit)
	_next_button.pressed.connect(next_mission_pressed.emit)
	_mission_select_button.pressed.connect(mission_select_pressed.emit)
	_resume_button.pressed.connect(resume_pressed.emit)
	_pause_restart_button.pressed.connect(restart_pressed.emit)
	_pause_mission_select_button.pressed.connect(mission_select_pressed.emit)
	_story_overlay.gui_input.connect(_on_story_gui_input)
	_story_overlay.hide()
	_completion_overlay.hide()
	_pause_overlay.hide()
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


## Shows the Next mission button (only when a next mission exists and is unlocked).
func set_next_mission_available(available: bool) -> void:
	_next_button.visible = available
	if available and _completion_overlay.visible:
		_next_button.grab_focus()


func show_pause() -> void:
	_pause_overlay.show()
	_resume_button.grab_focus()


func hide_pause() -> void:
	_pause_overlay.hide()


func is_pause_visible() -> bool:
	return _pause_overlay.visible


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


func get_pause_button() -> Button:
	return _pause_button


func get_next_button() -> Button:
	return _next_button


func get_mission_select_button() -> Button:
	return _mission_select_button


func get_resume_button() -> Button:
	return _resume_button


func get_pause_restart_button() -> Button:
	return _pause_restart_button


func get_pause_mission_select_button() -> Button:
	return _pause_mission_select_button


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		# The Level decides whether pausing is allowed (only while playing).
		if is_pause_visible():
			resume_pressed.emit()
		else:
			pause_requested.emit()
		_mark_handled()
		return
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


func _mark_handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _dismiss_story() -> void:
	if not is_story_visible():
		return
	hide_story()
	story_dismissed.emit()
