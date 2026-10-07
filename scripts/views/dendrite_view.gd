class_name DendriteView
extends Node2D
## Draws one dendrite as a straight glowing line between its neurons (SDD 2, 3, 4, 5.4).
## NORMAL: white. TENSION: light green, thinning from WIDTH to MIN_TENSION_WIDTH as the
## tension ratio goes 0 -> 1, trembling and flickering near the limit, hidden once broken.
## Crossing involvement fades in a warm pulsing glow that calms smoothly when resolved.
## The look (core, glow, travelling electrical pulse, tremble, completion wave) lives in
## assets/shaders/dendrite.gdshader; this script only feeds it parameters.
##
## Wiring: setup() connects to neuron_moved, crossings_changed, tension_changed and edge_broke
## and filters by its own edge / endpoint ids. Positions are in Playfield coordinates, so the
## node itself stays at the origin. All geometry lives in _draw_dendrite() so curved dendrites
## can replace straight ones by changing only that method.

const DendriteShader := preload("res://assets/shaders/dendrite.gdshader")

const WIDTH := 3.0
const MIN_TENSION_WIDTH := 1.0

var edge_id := -1

var _a_id := PuzzleModel.NO_NEURON
var _b_id := PuzzleModel.NO_NEURON
var _a_pos := Vector2.ZERO
var _b_pos := Vector2.ZERO
var _tension := false
var _ratio := 0.0
var _show_feedback := true
var _highlighted := false
var _broken := false
var _highlight_amount := 0.0
## Completion wave: front position along the dendrite (0 at A, 1 at B) and strength.
var _wave_pos := -1.0
var _wave_strength := 0.0
var _wave_tween: Tween
var _shader_material := ShaderMaterial.new()


func _init() -> void:
	_shader_material.shader = DendriteShader
	material = _shader_material


func setup(id: int, model: PuzzleModel, show_feedback := true) -> void:
	edge_id = id
	var endpoints := model.get_edge_endpoints(id)
	_a_id = endpoints.x
	_b_id = endpoints.y
	_a_pos = model.get_neuron_position(_a_id)
	_b_pos = model.get_neuron_position(_b_id)
	_tension = model.is_tension_edge(id)
	_ratio = model.get_tension_ratio(id)
	_show_feedback = show_feedback
	_highlighted = show_feedback and model.get_crossing_edges().has(id)
	_highlight_amount = 1.0 if _highlighted else 0.0
	model.neuron_moved.connect(_on_neuron_moved)
	model.crossings_changed.connect(_on_crossings_changed)
	model.tension_changed.connect(_on_tension_changed)
	model.edge_broke.connect(_on_edge_broke)
	_configure_material()
	queue_redraw()


func get_endpoints() -> PackedVector2Array:
	return PackedVector2Array([_a_pos, _b_pos])


func get_endpoint_ids() -> Vector2i:
	return Vector2i(_a_id, _b_id)


func is_highlighted() -> bool:
	return _highlighted


func is_broken() -> bool:
	return _broken


func get_line_width() -> float:
	if _tension:
		return VisualTuning.tension_width(_ratio)
	return WIDTH


## Logical color (crossing color while highlighted). The shader eases towards it.
func get_line_color() -> Color:
	if _highlighted:
		return Palette.CROSSING
	return get_base_color()


func get_base_color() -> Color:
	return Palette.TENSION if _tension else Palette.DENDRITE


## Crossing warmth currently shown, 0..1 (eases towards is_highlighted()).
func get_highlight_amount() -> float:
	return _highlight_amount


func get_shader_param(param: StringName) -> Variant:
	return _shader_material.get_shader_parameter(param)


## Completion wave: after delay, a light front runs along the dendrite in duration seconds,
## starting at endpoint A (from_a) or B.
func play_wave(delay: float, from_a: bool, duration: float) -> void:
	if _wave_tween != null:
		_wave_tween.kill()
	if not is_inside_tree():
		return
	var start := -0.2 if from_a else 1.2
	var finish := 1.2 if from_a else -0.2
	_wave_pos = start
	_wave_tween = create_tween()
	_wave_tween.tween_interval(delay)
	_wave_tween.tween_property(self, ^"_wave_strength", 1.0, 0.05)
	_wave_tween.tween_property(self, ^"_wave_pos", finish, maxf(duration, 0.01))
	_wave_tween.tween_property(self, ^"_wave_strength", 0.0, VisualTuning.WAVE_TAIL)


func _process(delta: float) -> void:
	var motion := VisualTuning.motion_scale()
	var target := 1.0 if _highlighted else 0.0
	if motion > 0.0:
		_highlight_amount = VisualTuning.approach(_highlight_amount, target, VisualTuning.HIGHLIGHT_RATE, delta)
	else:
		_highlight_amount = target
	_update_dynamic_params(motion)


func _draw() -> void:
	_draw_dendrite(_a_pos, _b_pos, get_line_width())


## The only geometry entry point; replace it to change the dendrite shape (e.g. curves).
## Builds a strip along the segment, wide enough for the glow, with UV.x along the length
## and UV.y across it, subdivided so the shader can bow it (tension tremble).
func _draw_dendrite(from: Vector2, to: Vector2, width: float) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var direction := (to - from) / length
	var normal := direction.orthogonal()
	var half := width * 0.5 + VisualTuning.DENDRITE_HALF_WIDTH
	var segments := clampi(ceili(length / VisualTuning.DENDRITE_SEGMENT_LENGTH), 1, 64)
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var u := float(i) / segments
		var center := from + direction * length * u
		points.append(center + normal * half)
		points.append(center - normal * half)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		if i < segments:
			var k := i * 2
			indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points,
		PackedColorArray([Color.WHITE]), uvs)
	_shader_material.set_shader_parameter(&"length_px", length)
	_shader_material.set_shader_parameter(&"half_width_px", half)
	_shader_material.set_shader_parameter(&"normal", normal)


func _configure_material() -> void:
	var m := _shader_material
	m.set_shader_parameter(&"line_color", get_base_color())
	m.set_shader_parameter(&"warm_color", Palette.CROSSING)
	m.set_shader_parameter(&"glow_strength", VisualTuning.DENDRITE_GLOW_STRENGTH)
	m.set_shader_parameter(&"phase", VisualTuning.phase_for(edge_id + 101) / TAU * VisualTuning.PULSE_INTERVAL)
	m.set_shader_parameter(&"pulse_interval", VisualTuning.PULSE_INTERVAL)
	m.set_shader_parameter(&"pulse_speed_px", VisualTuning.PULSE_SPEED)
	m.set_shader_parameter(&"pulse_strength", VisualTuning.PULSE_STRENGTH)
	_apply_tension_params()
	_update_dynamic_params(VisualTuning.motion_scale())


func _apply_tension_params() -> void:
	var m := _shader_material
	m.set_shader_parameter(&"core_width_px", get_line_width())
	m.set_shader_parameter(&"tremble_px", VisualTuning.tension_tremble(_ratio) if _tension else 0.0)
	m.set_shader_parameter(&"flicker", VisualTuning.tension_flicker(_ratio) if _tension else 0.0)


func _update_dynamic_params(motion: float) -> void:
	var m := _shader_material
	m.set_shader_parameter(&"motion", motion)
	m.set_shader_parameter(&"warm", _highlight_amount)
	m.set_shader_parameter(&"wave_pos", _wave_pos)
	m.set_shader_parameter(&"wave_strength", _wave_strength)


func _on_neuron_moved(id: int, pos: Vector2) -> void:
	if id == _a_id:
		_a_pos = pos
	elif id == _b_id:
		_b_pos = pos
	else:
		return
	queue_redraw()


func _on_crossings_changed(crossing_edges: Array[int], _involved_neurons: Array[int]) -> void:
	_highlighted = _show_feedback and crossing_edges.has(edge_id)


func _on_tension_changed(id: int, ratio: float) -> void:
	if id == edge_id:
		_ratio = ratio
		_apply_tension_params()
		queue_redraw()


func _on_edge_broke(id: int) -> void:
	if id == edge_id:
		_broken = true
		visible = false
