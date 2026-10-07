class_name MissionSelect
extends Control
## Mission select (SDD 5.5, 7.1): one section per chapter (title, subtitle) with its missions as
## MissionNodes showing locked / unlocked / completed state and best stars. Built from
## GameState.campaign and GameState.progress when it enters the tree.
## Emits mission_selected(id) only for unlocked missions; back_pressed on Back or ui_cancel.

signal mission_selected(mission_id: StringName)
signal back_pressed()

@onready var _back_button: Button = $Margin/Column/Header/BackButton
@onready var _chapters_box: VBoxContainer = $Margin/Column/Scroll/Chapters

var _nodes: Dictionary[StringName, MissionNode] = {}
var _chapter_titles: Array[String] = []


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
	section.add_theme_constant_override(&"separation", 12)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override(&"font_size", 40)
	section.add_child(title_label)
	var subtitle_label := Label.new()
	subtitle_label.text = chapter.subtitle
	subtitle_label.modulate.a = 0.6
	section.add_child(subtitle_label)
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 40)
	row.add_theme_constant_override(&"v_separation", 24)
	section.add_child(row)
	for level in chapter.missions:
		if level != null:
			row.add_child(_make_mission_cell(level, campaign))
	return section


func _make_mission_cell(level: LevelData, campaign: Campaign) -> Control:
	var id := level.mission_id
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override(&"separation", 4)
	var node := MissionNode.new()
	node.name = String(id)
	var state := MissionNode.state_for(GameState.is_unlocked(id), GameState.progress.is_completed(id))
	node.setup(id, campaign.get_mission_number(id), state, GameState.progress.get_best_stars(id),
		level.mission_name)
	node.pressed.connect(_on_mission_pressed.bind(id))
	cell.add_child(node)
	var name_label := Label.new()
	name_label.text = level.mission_name if state != MissionNode.State.LOCKED else "Locked"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override(&"font_size", 22)
	name_label.modulate.a = 1.0 if state != MissionNode.State.LOCKED else MissionNode.LOCKED_ALPHA
	cell.add_child(name_label)
	_nodes[id] = node
	return cell


func _on_mission_pressed(mission_id: StringName) -> void:
	if GameState.is_unlocked(mission_id):
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
