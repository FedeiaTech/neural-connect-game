class_name NeuronView
extends Node2D
## Draws one neuron (SDD 3, 4, 5.4): a white soma (red when fixed) with a soft glow halo, a
## gentle idle pulse with a per-neuron phase and a multipolar neuron body (NeuronMorphology, seeded by
## neuron id): an angular soma with a nucleus, tapered forking dendrites and one axon that sway
## slightly. The soma, halo and effects are
## assets/shaders/neuron.gdshader on a single quad, the processes a per-neuron mesh behind it
## (drawn first in the same item and material). Dendrites grow towards linked neighbours. All in assets/shaders/neuron.gdshader on a single quad. Grabbing brightens and
## scales it up (tween); crossing involvement adds a soft, slowly breathing warm "latency" glow
## with a light sparkle around the unchanged soma (T7.1) that fades in and calms smoothly; a
## contact ring flashes when the model blocks it.
##
## Wiring: setup() connects this view to the model signals it needs (neuron_moved,
## crossings_changed, neuron_blocked) and filters them by id. The grabbed state is not a model
## concept, so the LevelController pushes it down with set_grabbed(). Freeing the view drops
## its connections automatically, which is how a restart rebuilds the views.
## Toxic neurons (T8.2): a yellow soma with a faint pulsing warning glow that turns into a
## strong fast pulse plus a ring while the neuron contaminates a receptor (the warning amount eases
## towards its target; reduced motion snaps it and the pulse stands still).
## Reduced motion (GameState) freezes the shader animation, turns the sparkle off (the latency
## glow stays as a static tint) and snaps the fades.

const NeuronShader := preload("res://assets/shaders/neuron.gdshader")

const GRAB_SCALE := 1.15
const CONTACT_FLASH_TIME := 0.25

var neuron_id := PuzzleModel.NO_NEURON

var _radius := 28.0
var _fixed := false
## Receptor (T7.3): cyan soma; ReceptorView draws its halo, stub and link dots.
var _receptor := false
## Toxic (T8.2): yellow soma; _contaminated while it sits inside a receptor's reach.
var _toxic := false
var _contaminated := false
var _warn_amount := 0.0
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
## Lethal walls (T7.2): proximity warning 0..1 and the overload before the explosion.
var _hazard := 0.0
var _destroyed := false
var _overload_age := 0.0
var _shader_material := ShaderMaterial.new()
## Multipolar body of this neuron (seeded by id, oriented to its links); the shaders mirror it.
var _morphology: NeuronMorphology
## Dendrites and axon: a mesh drawn behind the soma quad in the same canvas item and material.
var _arms_mesh: ArrayMesh
var _link_angles := PackedFloat32Array()
## Last value pushed per dynamic shader parameter.
var _param_cache: Dictionary[StringName, float] = {}


func _init() -> void:
	_shader_material.shader = NeuronShader
	material = _shader_material


func setup(id: int, model: PuzzleModel, show_feedback := true) -> void:
	neuron_id = id
	_radius = model.get_neuron_radius()
	_fixed = model.is_fixed(id)
	_receptor = model.is_receptor(id)
	_toxic = model.is_toxic(id)
	_show_feedback = show_feedback
	position = model.get_neuron_position(id)
	_highlighted = show_feedback and model.get_crossing_neurons().has(id)
	_highlight_amount = 1.0 if _highlighted else 0.0
	model.neuron_moved.connect(_on_neuron_moved)
	model.crossings_changed.connect(_on_crossings_changed)
	model.neuron_blocked.connect(_on_neuron_blocked)
	model.neuron_destroyed.connect(_on_neuron_destroyed)
	model.hazard_proximity_changed.connect(_on_hazard_proximity_changed)
	if _toxic:
		_contaminated = _is_contaminated_in(model)
		_warn_amount = get_warning_target()
		model.contamination_formed.connect(_on_contamination_changed.bind(model).unbind(2))
		model.contamination_cleared.connect(_on_contamination_changed.bind(model).unbind(2))
	_link_angles = _compute_link_angles(model)
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


func is_toxic() -> bool:
	return _toxic


## True while this toxic neuron is inside a receptor's reach.
func is_contaminated() -> bool:
	return _contaminated


## Warning glow the view eases towards: 0 for normal neurons, faint at rest, full when
## contaminating.
func get_warning_target() -> float:
	if not _toxic:
		return 0.0
	return 1.0 if _contaminated else VisualTuning.TOXIC_WARN_IDLE


## Warning glow currently shown, 0..1.
func get_warning_amount() -> float:
	return _warn_amount


func is_fixed() -> bool:
	return _fixed


func is_receptor() -> bool:
	return _receptor


## True from the lethal contact until the explosion hides the neuron (T7.2).
func is_overloading() -> bool:
	return _destroyed and visible


func is_destroyed() -> bool:
	return _destroyed


func is_contact_flashing() -> bool:
	return _contact_flash > 0.0


## Model radius (collision size).
func get_radius() -> float:
	return _radius


## Target visual radius: grows while grabbed (the drawn size eases towards it).
func get_draw_radius() -> float:
	return _radius * GRAB_SCALE if _grabbed else _radius


func get_fill_color() -> Color:
	if _receptor:
		return Palette.RECEPTOR
	if _fixed:
		return Palette.NEURON_FIXED
	if _toxic:
		return Palette.TOXIC
	if _grabbed:
		return Palette.NEURON_GRABBED
	return Palette.NEURON


## Crossing warmth currently shown, 0..1 (eases towards is_highlighted()).
func get_highlight_amount() -> float:
	return _highlight_amount


func get_morphology() -> NeuronMorphology:
	return _morphology


func get_arms_mesh() -> ArrayMesh:
	return _arms_mesh


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
	var warn_target := get_warning_target()
	if motion > 0.0:
		_warn_amount = VisualTuning.approach(_warn_amount, warn_target, VisualTuning.TOXIC_WARN_RATE, delta)
	else:
		_warn_amount = warn_target
	_contact_flash = maxf(_contact_flash - delta, 0.0)
	if _destroyed and visible:
		_overload_age += delta
		if _overload_age >= VisualTuning.OVERLOAD_TIME:
			# The explosion (LevelFx) takes over from here.
			visible = false
	_update_dynamic_params(motion)


func _draw() -> void:
	_draw_neuron()


## The only drawing entry point, so the look can change without touching state. One quad
## large enough for the grabbed soma and its halo; the shader does the rest.
func _draw_neuron() -> void:
	if _arms_mesh != null:
		draw_mesh(_arms_mesh, null)
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
	if _receptor:
		m.set_shader_parameter(&"core_color", Palette.RECEPTOR)
		m.set_shader_parameter(&"glow_color", Palette.RECEPTOR_GLOW)
	elif _toxic:
		m.set_shader_parameter(&"core_color", Palette.TOXIC)
		m.set_shader_parameter(&"glow_color", Palette.TOXIC_GLOW)
		m.set_shader_parameter(&"warn_color", Palette.TOXIC_GLOW)
	else:
		m.set_shader_parameter(&"core_color", Palette.NEURON_FIXED if _fixed else Palette.NEURON)
		m.set_shader_parameter(&"glow_color", Palette.NEURON_FIXED_GLOW if _fixed else Palette.NEURON_GLOW)
	m.set_shader_parameter(&"latency_color", Palette.CROSSING_LATENCY)
	m.set_shader_parameter(&"latency_speed", VisualTuning.LATENCY_SPEED)
	m.set_shader_parameter(&"latency_glow", VisualTuning.LATENCY_GLOW)
	m.set_shader_parameter(&"overload_color", Palette.OVERLOAD_FLASH)
	m.set_shader_parameter(&"half_size_px", _quad_half_size())
	m.set_shader_parameter(&"glow_strength", VisualTuning.NEURON_GLOW_STRENGTH)
	var heavy := _fixed and not _receptor
	m.set_shader_parameter(&"pulse_speed",
		VisualTuning.FIXED_PULSE_SPEED if heavy else VisualTuning.NEURON_PULSE_SPEED)
	m.set_shader_parameter(&"pulse_depth",
		VisualTuning.FIXED_PULSE_DEPTH if heavy else VisualTuning.NEURON_PULSE_DEPTH)
	m.set_shader_parameter(&"phase", VisualTuning.phase_for(neuron_id))
	var kind := NeuronMorphology.Kind.NORMAL
	if _receptor:
		kind = NeuronMorphology.Kind.RECEPTOR
	elif _fixed:
		kind = NeuronMorphology.Kind.FIXED
	elif _toxic:
		kind = NeuronMorphology.Kind.TOXIC
	_morphology = NeuronMorphology.generate(neuron_id, kind, _link_angles)
	m.set_shader_parameter(&"soma_radius", _morphology.soma_radius)
	m.set_shader_parameter(&"corner_amp", _morphology.corner_amp)
	m.set_shader_parameter(&"corner_width", _morphology.corner_width)
	var corners := PackedFloat32Array(_morphology.corners)
	m.set_shader_parameter(&"corner_count", corners.size())
	corners.resize(NeuronMorphology.MAX_CORNERS)
	m.set_shader_parameter(&"corners", corners)
	m.set_shader_parameter(&"nucleus", _morphology.nucleus)
	m.set_shader_parameter(&"shape_breath", _morphology.breath_phase)
	_arms_mesh = _morphology.build_mesh()
	m.set_shader_parameter(&"arm_alpha", VisualTuning.NEURON_ARM_ALPHA)
	_update_dynamic_params(VisualTuning.motion_scale())


## Called every frame: only pushes values that changed, so an idle neuron does not dirty its
## material (each push re-uploads the material's uniforms; T4.7).
func _update_dynamic_params(motion: float) -> void:
	_set_param(&"motion", motion)
	var low := VisualTuning.is_low_quality()
	_set_param(&"low_quality", 1.0 if low else 0.0)
	_set_param(&"sparkle", 0.0 if low else VisualTuning.LATENCY_SPARKLE * motion)
	_set_param(&"radius_px", lerpf(_radius, _radius * GRAB_SCALE, _grab_amount))
	_set_param(&"crossing", _highlight_amount)
	_set_param(&"contact", _contact_flash / CONTACT_FLASH_TIME)
	var overload := _hazard * VisualTuning.HAZARD_OVERLOAD
	if _destroyed:
		overload = maxf(overload, minf(_overload_age / VisualTuning.OVERLOAD_TIME, 1.0) * 0.6 + 0.4)
	_set_param(&"overload", overload)
	_set_param(&"warn", _warn_amount)
	var brightness := lerpf(1.0, VisualTuning.GRAB_BRIGHTNESS, _grab_amount)
	var total_brightness := brightness + _wave_boost * (VisualTuning.WAVE_BRIGHTNESS - 1.0)
	_set_param(&"brightness", total_brightness)
	_set_param(&"mesh_scale", lerpf(_radius, _radius * GRAB_SCALE, _grab_amount))


func _set_param(param: StringName, value: float) -> void:
	if _param_cache.get(param, NAN) == value:
		return
	_param_cache[param] = value
	_shader_material.set_shader_parameter(param, value)


## Angles to the linked neighbours (edge list, longest link first): dendrites and the axon grow
## towards them. Computed once; the model is not changed.
func _compute_link_angles(model: PuzzleModel) -> PackedFloat32Array:
	var here := model.get_neuron_position(neuron_id)
	var found: Array[Vector2] = []
	var seen := {}
	for edge in model.get_edge_count():
		var ends := model.get_edge_endpoints(edge)
		var other := -1
		if ends.x == neuron_id:
			other = ends.y
		elif ends.y == neuron_id:
			other = ends.x
		if other < 0 or seen.has(other):
			continue
		seen[other] = true
		found.append(model.get_neuron_position(other) - here)
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() > b.length())
	var angles := PackedFloat32Array()
	for offset in found:
		angles.append(fposmod(offset.angle(), TAU))
	return angles


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


func _on_neuron_destroyed(id: int, _contact: Vector2) -> void:
	if id == neuron_id:
		_destroyed = true
		_overload_age = 0.0


func _is_contaminated_in(model: PuzzleModel) -> bool:
	for pair in model.get_contamination_links():
		if pair.y == neuron_id:
			return true
	return false


func _on_contamination_changed(model: PuzzleModel) -> void:
	_contaminated = _is_contaminated_in(model)


func _on_hazard_proximity_changed(id: int, proximity: float) -> void:
	if id == neuron_id:
		_hazard = proximity


func _on_neuron_blocked(id: int, _contact: Vector2) -> void:
	if id != neuron_id:
		return
	_contact_flash = CONTACT_FLASH_TIME
