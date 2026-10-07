class_name MissionMap
extends Control
## One chapter of MissionSelect drawn as a network map (SDD 5.5): every mission is a neuron-like
## MissionNode placed along a gentle wave (layout()), consecutive missions are joined by dendrites
## and faint stubs lead in from the left and out to the right (the network goes on).
## Dendrites between completed missions are lit and carry a slow electrical pulse; the one leading
## to the next playable mission is half lit; locked ones are dim.
## play_pulse_to() sends a pulse along the incoming dendrite of a mission before it loads.
## Redraws every frame only while something animates; reduced motion keeps it static.

enum Segment { DIM, OPEN, LIT }

const MAP_HEIGHT := 300.0
const MARGIN := 110.0
const MAX_SPACING := 300.0
const WAVE_AMPLITUDE := 46.0
const NAME_OFFSET := 112.0
const NAME_WIDTH := 220.0
const PULSE_TIME := 0.45
const AMBIENT_CYCLE := 3.6
const AMBIENT_TRAVEL := 1.4
const SEGMENT_COLORS: Array[Color] = [
	Color(0.72, 0.86, 1.0, 0.12), Color(0.8, 0.9, 1.0, 0.38), Color(0.88, 0.95, 1.0, 0.7)]
const GLOW_COLOR := Color(0.6, 0.82, 1.0)

var _nodes: Array[MissionNode] = []
var _names: Array[Label] = []
var _points := PackedVector2Array()
var _time := 0.0
## Selection pulse: target index and progress 0..1 (negative = none).
var _pulse_index := -1
var _pulse_t := -1.0
var _pulse_tween: Tween


## Node centers for count missions inside a map of the given size, left to right, centered, at
## most MAX_SPACING apart, gently waving up and down.
static func layout(count: int, map_size: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	if count <= 0:
		return points
	var usable := maxf(map_size.x - 2.0 * MARGIN, 0.0)
	var spacing := minf(usable / maxf(count - 1, 1), MAX_SPACING)
	var x0 := map_size.x * 0.5 - spacing * (count - 1) * 0.5
	for i in count:
		var y := map_size.y * 0.42 + WAVE_AMPLITUDE * sin(i * 2.4 + 4.0)
		points.append(Vector2(x0 + spacing * i, y))
	return points


## Look of the dendrite between two consecutive missions.
static func segment_state(from: MissionNode.State, to: MissionNode.State) -> Segment:
	if from == MissionNode.State.COMPLETED and to == MissionNode.State.COMPLETED:
		return Segment.LIT
	if from == MissionNode.State.COMPLETED and to == MissionNode.State.UNLOCKED:
		return Segment.OPEN
	return Segment.DIM


func _init() -> void:
	custom_minimum_size = Vector2(0, MAP_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_relayout)


## Adds a mission node (in play order) with its name label under it.
func add_mission(node: MissionNode, label_text: String, dim: bool) -> void:
	_nodes.append(node)
	add_child(node)
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(NAME_WIDTH, 0)
	label.add_theme_font_size_override(&"font_size", 22)
	label.modulate.a = MissionNode.LOCKED_ALPHA if dim else 0.85
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_names.append(label)
	add_child(label)
	_relayout()


func has_mission(mission_id: StringName) -> bool:
	return _index_of(mission_id) >= 0


func is_pulsing() -> bool:
	return _pulse_t >= 0.0


## Plays a pulse along the dendrite that leads into mission_id and returns its duration
## (0 with reduced motion or an unknown mission: the caller proceeds at once).
func play_pulse_to(mission_id: StringName) -> float:
	var index := _index_of(mission_id)
	if index < 0 or not VisualTuning.is_motion_enabled() or not is_inside_tree():
		return 0.0
	if _pulse_tween != null:
		_pulse_tween.kill()
	_pulse_index = index
	_pulse_t = 0.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, ^"_pulse_t", 1.0, PULSE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_pulse_tween.tween_callback(_end_pulse)
	return PULSE_TIME


func _end_pulse() -> void:
	_pulse_t = -1.0
	queue_redraw()


func _process(delta: float) -> void:
	if not VisualTuning.is_motion_enabled():
		return
	_time += delta
	if is_pulsing() or _has_lit_segment():
		queue_redraw()


func _relayout() -> void:
	_points = layout(_nodes.size(), size if size.x > 0.0 else Vector2(1600, MAP_HEIGHT))
	for i in _nodes.size():
		var node := _nodes[i]
		node.position = _points[i] - node.get_center_offset()
		_names[i].size = Vector2(NAME_WIDTH, 0)
		_names[i].position = _points[i] + Vector2(-NAME_WIDTH * 0.5, NAME_OFFSET)
	queue_redraw()


func _draw() -> void:
	if _points.is_empty():
		return
	var first := _points[0]
	var last := _points[_points.size() - 1]
	_draw_dendrite(Vector2(0.0, first.y + 30.0), first, Segment.DIM if _nodes[0].state == MissionNode.State.LOCKED else Segment.OPEN, -1)
	_draw_dendrite(last, Vector2(size.x, last.y - 30.0), Segment.DIM, -1)
	for i in range(1, _points.size()):
		_draw_dendrite(_points[i - 1], _points[i], segment_state(_nodes[i - 1].state, _nodes[i].state), i)
	if is_pulsing():
		var from := Vector2(0.0, first.y + 30.0) if _pulse_index == 0 else _points[_pulse_index - 1]
		var to := _points[_pulse_index]
		draw_line(from, from.lerp(to, _pulse_t), Color(GLOW_COLOR, 0.6), 4.0, true)
		GlowTexture.draw(self, from.lerp(to, _pulse_t), 30.0, Color(1, 1, 1, 0.9))
		GlowTexture.draw(self, to, 70.0 * _pulse_t, Color(GLOW_COLOR, 0.5 * _pulse_t))


func _draw_dendrite(a: Vector2, b: Vector2, segment: Segment, index: int) -> void:
	var color := SEGMENT_COLORS[segment]
	if segment != Segment.DIM:
		draw_line(a, b, Color(GLOW_COLOR, color.a * 0.18), 12.0, true)
	draw_line(a, b, color, 2.0 if segment == Segment.DIM else 3.0, true)
	if segment == Segment.LIT and VisualTuning.is_motion_enabled():
		var u := fposmod(_time + index * 1.1, AMBIENT_CYCLE) / AMBIENT_TRAVEL
		if u <= 1.0:
			GlowTexture.draw(self, a.lerp(b, u), 14.0, Color(1, 1, 1, 0.7 * sin(u * PI)))


func _has_lit_segment() -> bool:
	for i in range(1, _nodes.size()):
		if segment_state(_nodes[i - 1].state, _nodes[i].state) == Segment.LIT:
			return true
	return false


func _index_of(mission_id: StringName) -> int:
	for i in _nodes.size():
		if _nodes[i].mission_id == mission_id:
			return i
	return -1
