class_name Hud
extends CanvasLayer
## Minimal in-level HUD (SDD 4, 6, 7.1, 8.5): mission title, moves, time (mm:ss), restart
## button, story overlay dismissed by click/tap, and a completion panel with stars.
## T3.1 adds: Next mission / Mission select on the completion panel and a pause overlay
## (Resume, Restart, Mission select) toggled by the `pause` action or the Pause button.
## Calls come down from the Level; user intent goes up through signals.
## Non-interactive nodes use mouse_filter IGNORE so drags reach the InputController.
## The HUD runs with PROCESS_MODE_ALWAYS so the pause overlay works while the tree is paused.
## T4.5 summary: the panel eases in, its title letters fade in, the stars light up one by one
## (star_revealed(index) announces each, e.g. for a sound), moves and time count up and a light
## wave sweeps across the screen. Reduced motion shows the final state at once (every star is
## still announced). Buttons are GlowButtons; labels have a soft glow outline.

signal restart_pressed()
signal story_dismissed()
signal pause_requested()
signal resume_pressed()
signal next_mission_pressed()
signal mission_select_pressed()
signal star_revealed(index: int)

const COMPLETION := "CompletionOverlay/Center/Panel/Column/"
const PAUSE := "PauseOverlay/Center/Panel/Column/"
const STAR_START := 0.35
const STAR_INTERVAL := 0.32
const COUNT_DELAY := 0.2
const COUNT_TIME := 0.9
const SWEEP_TIME := 1.3
const PANEL_IN_TIME := 0.3
const PANEL_IN_SCALE := 0.94

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
@onready var _completion_panel: Control = $CompletionOverlay/Center/Panel
@onready var _completion_title: GlowTitle = get_node(COMPLETION + "Title")
@onready var _sweep: ColorRect = $CompletionOverlay/Sweep

var _summary_tween: Tween
var _sweep_tween: Tween


func _ready() -> void:
	_star_row.star_revealed.connect(star_revealed.emit)
	_completion_panel.offset_transform_enabled = true
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


## Seconds after show_completion() at which each of count stars lights up.
static func star_reveal_times(count: int) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	for i in count:
		times.append(STAR_START + i * STAR_INTERVAL)
	return times


## Summary stats with moves and time scaled by progress (0..1) for the count-up.
static func stats_text(moves: int, seconds: float, progress: float) -> String:
	var t := clampf(progress, 0.0, 1.0)
	return "Moves %d    Time %s" % [roundi(moves * t), format_time(seconds * t)]


func show_completion(result: LevelResult) -> void:
	_stop_summary()
	_star_row.stars = result.stars
	_completion_overlay.show()
	_replay_button.grab_focus()
	if not VisualTuning.is_motion_enabled():
		_apply_count(1.0, result.moves, result.time)
		for i in result.stars:
			_star_row.light(i)
		return
	_star_row.clear_lit()
	_apply_count(0.0, result.moves, result.time)
	_completion_title.restart()
	_completion_panel.modulate.a = 0.0
	_completion_panel.offset_transform_scale = Vector2.ONE * PANEL_IN_SCALE
	_summary_tween = create_tween().set_parallel(true)
	_summary_tween.tween_property(_completion_panel, ^"modulate:a", 1.0, PANEL_IN_TIME)
	_summary_tween.tween_property(_completion_panel, ^"offset_transform_scale", Vector2.ONE, PANEL_IN_TIME * 1.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var times := star_reveal_times(result.stars)
	for i in times.size():
		_summary_tween.tween_callback(_star_row.light.bind(i)).set_delay(times[i])
	_summary_tween.tween_method(_apply_count.bind(result.moves, result.time), 0.0, 1.0, COUNT_TIME) \
		.set_delay(COUNT_DELAY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_play_sweep()


func hide_completion() -> void:
	_stop_summary()
	_completion_overlay.hide()


func get_lit_star_count() -> int:
	return _star_row.get_lit_count()


func is_sweeping() -> bool:
	return _sweep_tween != null and _sweep_tween.is_running()


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


func _apply_count(progress: float, moves: int, seconds: float) -> void:
	_stats_label.text = stats_text(moves, seconds, progress)


func _play_sweep() -> void:
	_sweep.show()
	_sweep_tween = create_tween()
	_sweep_tween.tween_method(_set_sweep_progress, -0.3, 1.3, SWEEP_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sweep_tween.tween_callback(_sweep.hide)


func _set_sweep_progress(value: float) -> void:
	(_sweep.material as ShaderMaterial).set_shader_parameter(&"progress", value)


## Stops a running summary animation and restores the panel.
func _stop_summary() -> void:
	for tween: Tween in [_summary_tween, _sweep_tween]:
		if tween != null:
			tween.kill()
	_summary_tween = null
	_sweep_tween = null
	_sweep.hide()
	_completion_panel.modulate.a = 1.0
	_completion_panel.offset_transform_scale = Vector2.ONE


func _dismiss_story() -> void:
	if not is_story_visible():
		return
	hide_story()
	story_dismissed.emit()
