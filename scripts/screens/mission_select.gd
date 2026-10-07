class_name MissionSelect
extends Control
## Mission select (SDD 5.5, 7.1) as a network map: one section per chapter with an illustrated
## procedural ChapterHeader and a MissionMap whose neurons are the missions (locked / unlocked /
## completed with best stars). Built from GameState.campaign and GameState.progress when it enters
## the tree.
## Selecting an unlocked mission first sends a dendrite pulse to its node, then emits
## mission_selected(id) (at once with reduced motion); further presses meanwhile are ignored.
## back_pressed on Back or ui_cancel.
## T6.1 record reset: hovering or focusing a completed mission shows a small "Reset record"
## button in the header (Delete on a focused completed mission or a right-click on it asks
## directly). An inline confirmation follows (Cancel has focus, ui_cancel closes it); confirming
## calls GameState.reset_mission() and rebuilds the map.

signal mission_selected(mission_id: StringName)
signal back_pressed()

const HEADER := "Margin/Column/Header/"

@onready var _back_button: Button = get_node(HEADER + "BackButton")
@onready var _reset_button: Button = get_node(HEADER + "ResetRecordButton")
@onready var _confirm_row: Control = get_node(HEADER + "ConfirmRow")
@onready var _confirm_label: Label = get_node(HEADER + "ConfirmRow/ConfirmLabel")
@onready var _confirm_button: Button = get_node(HEADER + "ConfirmRow/ConfirmButton")
@onready var _cancel_button: Button = get_node(HEADER + "ConfirmRow/CancelButton")
@onready var _chapters_box: VBoxContainer = $Margin/Column/Scroll/Chapters

var _nodes: Dictionary[StringName, MissionNode] = {}
var _maps: Dictionary[StringName, MissionMap] = {}
var _headers: Array[ChapterHeader] = []
var _selecting := false
## Completed mission whose record the header button (and the confirmation) would reset.
var _reset_target: StringName = &""


func _ready() -> void:
	_back_button.pressed.connect(back_pressed.emit)
	_reset_button.pressed.connect(_on_reset_button_pressed)
	_confirm_button.pressed.connect(_confirm_reset)
	_cancel_button.pressed.connect(_cancel_reset)
	_build()
	_focus_first_playable()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_mark_handled()
		if is_mission_reset_pending():
			_cancel_reset()
		else:
			back_pressed.emit()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_DELETE:
		var focused := get_viewport().gui_get_focus_owner() as MissionNode
		if focused != null and _nodes.get(focused.mission_id) == focused:
			_mark_handled()
			request_mission_reset(focused.mission_id)


func get_mission_node(mission_id: StringName) -> MissionNode:
	return _nodes.get(mission_id)


func get_map_for(mission_id: StringName) -> MissionMap:
	return _maps.get(mission_id)


func get_chapter_headers() -> Array[ChapterHeader]:
	return _headers


## Displayed chapter headings, in campaign order.
func get_chapter_titles() -> Array[String]:
	var titles: Array[String] = []
	for header in _headers:
		titles.append(header.get_title_text())
	return titles


func get_back_button() -> Button:
	return _back_button


func get_mission_reset_button() -> Button:
	return _reset_button


func get_mission_reset_confirm_button() -> Button:
	return _confirm_button


func get_mission_reset_cancel_button() -> Button:
	return _cancel_button


func is_mission_reset_pending() -> bool:
	return _confirm_row.visible


## Asks to reset a completed mission's record (inline confirmation). Ignored otherwise.
func request_mission_reset(mission_id: StringName) -> void:
	if not GameState.progress.is_completed(mission_id):
		return
	_set_reset_target(mission_id)
	_reset_button.hide()
	_confirm_label.text = "Reset the record of mission %d?" % GameState.campaign.get_mission_number(mission_id)
	_confirm_row.show()
	_cancel_button.grab_focus()


func _build() -> void:
	var campaign := GameState.campaign
	for chapter in campaign.chapters:
		if chapter != null:
			_chapters_box.add_child(_make_chapter(chapter, campaign))


## Frees and rebuilds every chapter (after a record reset). Freed at once, not queued: the
## call comes from a header button, never from inside the chapters being freed.
func _rebuild() -> void:
	for child in _chapters_box.get_children():
		_chapters_box.remove_child(child)
		child.free()
	_nodes.clear()
	_maps.clear()
	_headers.clear()
	_build()


func _make_chapter(chapter: ChapterData, campaign: Campaign) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override(&"separation", 0)
	var header := ChapterHeader.new()
	header.setup(chapter.chapter_id, chapter.title, chapter.subtitle)
	_headers.append(header)
	section.add_child(header)
	var map := MissionMap.new()
	section.add_child(map)
	for level in chapter.missions:
		if level != null:
			_add_mission(map, level, campaign)
	return section


func _add_mission(map: MissionMap, level: LevelData, campaign: Campaign) -> void:
	var id := level.mission_id
	var node := MissionNode.new()
	node.name = String(id)
	var state := MissionNode.state_for(GameState.is_unlocked(id), GameState.progress.is_completed(id))
	node.setup(id, campaign.get_mission_number(id), state, GameState.progress.get_best_stars(id),
		level.mission_name)
	node.pressed.connect(_on_mission_pressed.bind(id))
	node.focus_entered.connect(_on_mission_hovered.bind(id))
	node.mouse_entered.connect(_on_mission_hovered.bind(id))
	node.gui_input.connect(_on_mission_gui_input.bind(id))
	var locked := state == MissionNode.State.LOCKED
	map.add_mission(node, "Locked" if locked else level.mission_name, locked)
	_nodes[id] = node
	_maps[id] = map


func _on_mission_pressed(mission_id: StringName) -> void:
	if _selecting or not GameState.is_unlocked(mission_id):
		return
	var map: MissionMap = _maps.get(mission_id)
	var delay := map.play_pulse_to(mission_id) if map != null else 0.0
	if delay <= 0.0:
		mission_selected.emit(mission_id)
		return
	_selecting = true
	# Bound callable: if this screen is freed first, the connection simply goes away.
	get_tree().create_timer(delay).timeout.connect(_finish_selection.bind(mission_id))


func _finish_selection(mission_id: StringName) -> void:
	_selecting = false
	mission_selected.emit(mission_id)


## Only completed missions become the reset target; others keep the last one, so moving the
## mouse up to the header across other missions does not hide the button.
func _on_mission_hovered(mission_id: StringName) -> void:
	if GameState.progress.is_completed(mission_id) and not is_mission_reset_pending():
		_set_reset_target(mission_id)


func _on_mission_gui_input(event: InputEvent, mission_id: StringName) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		_mark_handled()
		request_mission_reset(mission_id)


func _set_reset_target(mission_id: StringName) -> void:
	_reset_target = mission_id
	_reset_button.text = "Reset record: mission %d" % GameState.campaign.get_mission_number(mission_id)
	_reset_button.visible = not is_mission_reset_pending()


func _on_reset_button_pressed() -> void:
	if _reset_target != &"":
		request_mission_reset(_reset_target)


func _confirm_reset() -> void:
	var mission_id := _reset_target
	_close_confirmation()
	_reset_target = &""
	_reset_button.hide()
	GameState.reset_mission(mission_id)
	_rebuild()
	var node: MissionNode = _nodes.get(mission_id)
	if node != null and node.focus_mode != Control.FOCUS_NONE:
		node.grab_focus()
	else:
		_focus_first_playable()


func _cancel_reset() -> void:
	_close_confirmation()
	_reset_button.visible = _reset_target != &""
	var node: MissionNode = _nodes.get(_reset_target)
	if node != null:
		node.grab_focus()


func _close_confirmation() -> void:
	_confirm_row.hide()


func _mark_handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


## Focus the first unlocked, not yet completed mission (else the first unlocked one).
func _focus_first_playable() -> void:
	var fallback: MissionNode = null
	for id in GameState.campaign.get_mission_ids():
		var node: MissionNode = _nodes.get(id)
		if node == null or node.state == MissionNode.State.LOCKED:
			continue
		if node.state == MissionNode.State.UNLOCKED:
			node.grab_focus()
			return
		if fallback == null:
			fallback = node
	if fallback != null:
		fallback.grab_focus()
	else:
		_back_button.grab_focus()
