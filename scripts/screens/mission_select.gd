class_name MissionSelect
extends Control
## Mission select (SDD 5.5, 7.1) as a network map: one section per chapter with an illustrated
## procedural ChapterHeader and a MissionMap whose neurons are the missions (locked / unlocked /
## completed with best stars). Built from GameState.campaign and GameState.progress when it enters
## the tree.
## Selecting an unlocked mission first sends a dendrite pulse to its node, then emits
## mission_selected(id) (at once with reduced motion); further presses meanwhile are ignored.
## back_pressed on Back or ui_cancel.

signal mission_selected(mission_id: StringName)
signal back_pressed()

@onready var _back_button: Button = $Margin/Column/Header/BackButton
@onready var _chapters_box: VBoxContainer = $Margin/Column/Scroll/Chapters

var _nodes: Dictionary[StringName, MissionNode] = {}
var _maps: Dictionary[StringName, MissionMap] = {}
var _headers: Array[ChapterHeader] = []
var _chapter_titles: Array[String] = []
var _selecting := false


func _ready() -> void:
	_back_button.pressed.connect(back_pressed.emit)
	_build()
	_focus_first_playable()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()


func get_mission_node(mission_id: StringName) -> MissionNode:
	return _nodes.get(mission_id)


func get_map_for(mission_id: StringName) -> MissionMap:
	return _maps.get(mission_id)


func get_chapter_headers() -> Array[ChapterHeader]:
	return _headers


func get_chapter_titles() -> Array[String]:
	return _chapter_titles


func get_back_button() -> Button:
	return _back_button


func _build() -> void:
	var campaign := GameState.campaign
	for chapter in campaign.chapters:
		if chapter == null:
			continue
		var title := "Chapter %d: %s" % [chapter.chapter_id, chapter.title]
		_chapter_titles.append(title)
		_chapters_box.add_child(_make_chapter(chapter, title, campaign))


func _make_chapter(chapter: ChapterData, title: String, campaign: Campaign) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override(&"separation", 0)
	var header := ChapterHeader.new()
	header.setup(chapter.chapter_id, title, chapter.subtitle)
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
