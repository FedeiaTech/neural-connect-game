class_name NeuronView
extends Node2D
## Draws one neuron (SDD 3, 4, 5.4): a white soma (red when fixed) with a soft glow halo, a
## gentle idle pulse with a per-neuron phase and an organic wobbling outline with short dendrite
## stubs, all in assets/shaders/neuron.gdshader on a single quad. Grabbing brightens and
## scales it up (tween); crossing involvement adds a warm flicker that fades in and calms
## smoothly; a contact ring flashes when the model blocks it.
##
## Wiring: setup() connects this view to the model signals it needs (neuron_moved,
## crossings_changed, neuron_blocked) and filters them by id. The grabbed state is not a model
## concept, so the LevelController pushes it down with set_grabbed(). Freeing the view drops
## its connections automatically, which is how a restart rebuilds the views.
## Reduced motion (GameState) freezes the shader animation and snaps the fades.

const NeuronShader := preload("res://assets/shaders/neuron.gdshader")

const GRAB_SCALE := 1.15
const CONTACT_FLASH_TIME := 0.25

var neuron_id := PuzzleModel.NO_NEURON

var _radius := 28.0
var _fixed := false
var _show_feedback := true
var _highlighted := false
var _grabbed := false
var _contact_flash := 0.0
## Visual state, eased towards the logical one.
var _grab_amount := 0.0
var _highlight_amount := 0.0
var _wave_boost := 0.0
var _grab_tween: Tween
var _wave_tween: Tween
var _shader_material := ShaderMaterial.new()


func _init() -> void:
	_shader_material.shader = NeuronShader
	material = _shader_material


func setup(id: int, model: PuzzleModel, show_feedback := true) -> void:
	neuron_id = id
	_radius = model.get_neuron_radius()
	_fixed = model.is_fixed(id)
	_show_feedback = show_feedback
	position = model.get_neuron_position(id)
	_highlighted = show_feedback and model.get_crossing_neurons().has(id)
	_highlight_amount = 1.0 if _highlighted else 0.0
	model.neuron_moved.connect(_on_neuron_moved)
	model.crossings_changed.connect(_on_crossings_changed)
	model.neuron_blocked.connect(_on_neuron_blocked)
	_configure_material()
	queue_redraw()


func set_grabbed(value: bool) -> void:
	if _grabbed == value:
		return
	_grabbed = value
	_animate_grab(1.0 if value else 0.0)


func is_grabbed() -> bool:
	return _grabbed


func is_highlighted() -> bool:
	return _highlighted


func is_fixed() -> bool:
	return _fixed


func is_contact_flashing() -> bool:
	return _contact_flash > 0.0


## Model radius (collision size).
func get_radius() -> float:
	return _radius


## Target visual radius: grows while grabbed (the drawn size eases towards it).
func get_draw_radius() -> float:
	return _radius * GRAB_SCALE if _grabbed else _radius


func get_fill_color() -> Color:
	if _fixed:
		return Palette.NEURON_FIXED
	if _grabbed:
		return Palette.NEURON_GRABBED
	return Palette.NEURON


## Crossing warmth currently shown, 0..1 (eases towards is_highlighted()).
func get_highlight_amount() -> float:
	return _highlight_amount


func get_shader_param(param: StringName) -> Variant:
	return _shader_material.get_shader_parameter(param)


## Completion wave: brightens after delay seconds, then settles back.
func play_wave(delay: float) -> void:
	if _wave_tween != null:
		_wave_tween.kill()
	if not is_inside_tree():
		return
	_wave_tween = create_tween()
	_wave_tween.tween_interval(delay)
	_wave_tween.tween_property(self, ^"_wave_boost", 1.0, 0.12).set_trans(Tween.TRANS_SINE)
	_wave_tween.tween_property(self, ^"_wave_boost", 0.0, VisualTuning.WAVE_TAIL * 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	var motion := VisualTuning.motion_scale()
	var target := 1.0 if _highlighted else 0.0
	if motion > 0.0:
		_highlight_amount = VisualTuning.approach(_highlight_amount, target, VisualTuning.HIGHLIGHT_RATE, delta)
	else:
		_highlight_amount = target
	_contact_flash = maxf(_contact_flash - delta, 0.0)
	_update_dynamic_params(motion)


func _draw() -> void:
	_draw_neuron()


## The only drawing entry point, so the look can change without touching state. One quad
## large enough for the grabbed soma and its halo; the shader does the rest.
func _draw_neuron() -> void:
	var half := _quad_half_size()
	var rect := Rect2(-half, -half, 2.0 * half, 2.0 * half)
	draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([Color.WHITE]),
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))


func _quad_half_size() -> float:
	return _radius * GRAB_SCALE * VisualTuning.NEURON_QUAD_EXTENT


func _configure_material() -> void:
	var m := _shader_material
	m.set_shader_parameter(&"core_color", Palette.NEURON_FIXED if _fixed else Palette.NEURON)
	m.set_shader_parameter(&"glow_color", Palette.NEURON_FIXED_GLOW if _fixed else Palette.NEURON_GLOW)
	m.set_shader_parameter(&"warm_color", Palette.CROSSING)
	m.set_shader_parameter(&"half_size_px", _quad_half_size())
	m.set_shader_parameter(&"glow_strength", VisualTuning.NEURON_GLOW_STRENGTH)
	m.set_shader_parameter(&"pulse_speed",
		VisualTuning.FIXED_PULSE_SPEED if _fixed else VisualTuning.NEURON_PULSE_SPEED)
	m.set_shader_parameter(&"pulse_depth",
		VisualTuning.FIXED_PULSE_DEPTH if _fixed else VisualTuning.NEURON_PULSE_DEPTH)
	m.set_shader_parameter(&"phase", VisualTuning.phase_for(neuron_id))
	m.set_shader_parameter(&"wobble", VisualTuning.NEURON_WOBBLE)
	m.set_shader_parameter(&"stub_count", VisualTuning.NEURON_STUB_COUNT)
	m.set_shader_parameter(&"stub_length", VisualTuning.NEURON_STUB_LENGTH)
	_update_dynamic_params(VisualTuning.motion_scale())


func _update_dynamic_params(motion: float) -> void:
	var m := _shader_material
	m.set_shader_parameter(&"motion", motion)
	m.set_shader_parameter(&"radius_px", lerpf(_radius, _radius * GRAB_SCALE, _grab_amount))
	m.set_shader_parameter(&"warm", _highlight_amount)
	m.set_shader_parameter(&"contact", _contact_flash / CONTACT_FLASH_TIME)
	var brightness := lerpf(1.0, VisualTuning.GRAB_BRIGHTNESS, _grab_amount)
	m.set_shader_parameter(&"brightness", brightness + _wave_boost * (VisualTuning.WAVE_BRIGHTNESS - 1.0))


func _animate_grab(target: float) -> void:
	if _grab_tween != null:
		_grab_tween.kill()
		_grab_tween = null
	if not is_inside_tree() or not VisualTuning.is_motion_enabled():
		_grab_amount = target
		_update_dynamic_params(VisualTuning.motion_scale())
		return
	_grab_tween = create_tween()
	_grab_tween.tween_property(self, ^"_grab_amount", target, VisualTuning.GRAB_TWEEN_TIME) \
		.set_trans(Tween.TRANS_BACK if target > 0.0 else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_neuron_moved(id: int, pos: Vector2) -> void:
	if id == neuron_id:
		position = pos


func _on_crossings_changed(_crossing_edges: Array[int], involved_neurons: Array[int]) -> void:
	_highlighted = _show_feedback and involved_neurons.has(neuron_id)


func _on_neuron_blocked(id: int, _contact: Vector2) -> void:
	if id != neuron_id:
		return
	_contact_flash = CONTACT_FLASH_TIME
