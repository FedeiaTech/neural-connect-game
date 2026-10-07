class_name LevelFx
extends Node2D
## One-off playfield effects (SDD 5.4 "juice"), drawn above the neurons with additive blending:
## - Tension break: a snap flash along the broken dendrite, a particle burst and a light screen
##   shake of shake_target (shake only on break).
## - Lethal-wall overload (T7.2): after the neuron's OVERLOAD_TIME tremble, a white-violet
##   flash with a shock ring, two particle bursts and a stronger shake.
## - Level complete: a wave of light through the network (NetworkWave schedule, starting at the
##   last moved neuron) and the membrane exhaling. play_completion_wave() returns how long to
##   wait before showing the summary.
## Reduced motion: no burst, no shake, no travelling wave; flashes and glows still fade, and the
## summary is not delayed.
##
## Views only read the model: LevelController calls setup() after building the views.

## Node moved by the screen shake (the Level root; CanvasLayers like the HUD stay still).
@export var shake_target: Node2D

var _model: PuzzleModel
var _neuron_views: Dictionary[int, NeuronView] = {}
var _dendrite_views: Array[DendriteView] = []
var _membranes: Array[MembraneView] = []
var _last_moved_id := PuzzleModel.NO_NEURON
## Each flash: {"a": Vector2, "b": Vector2, "age": float}.
var _flashes: Array[Dictionary] = []
var _burst_count := 0
var _shake_tween: Tween
var _shake_origin := Vector2.ZERO
var _shaking := false
var _wave_end_msec := 0
var _last_wave_duration := 0.0
## Overload explosions waiting for the tremble to end: {"pos": Vector2, "wait": float}.
var _pending_explosions: Array[Dictionary] = []
## Each overload flash: {"pos": Vector2, "age": float}.
var _blasts: Array[Dictionary] = []
var _explosion_count := 0

static var _spark_texture: GradientTexture2D


func setup(model: PuzzleModel, neuron_views: Dictionary[int, NeuronView],
		dendrite_views: Array[DendriteView], membranes: Array[MembraneView]) -> void:
	_model = model
	_neuron_views = neuron_views
	_dendrite_views = dendrite_views
	_membranes = membranes
	_last_moved_id = PuzzleModel.NO_NEURON
	_wave_end_msec = 0
	_pending_explosions.clear()
	model.neuron_moved.connect(_on_neuron_moved)
	model.edge_broke.connect(_on_edge_broke)
	model.neuron_destroyed.connect(_on_neuron_destroyed)


func get_last_moved_id() -> int:
	return _last_moved_id


func is_flashing() -> bool:
	return not _flashes.is_empty() or not _blasts.is_empty()


## Overload explosions played since the scene started (T7.2).
func get_explosion_count() -> int:
	return _explosion_count


## Number of break bursts spawned since the scene started.
func get_burst_count() -> int:
	return _burst_count


func is_shaking() -> bool:
	return _shaking


func is_wave_running() -> bool:
	return Time.get_ticks_msec() < _wave_end_msec


func get_last_wave_duration() -> float:
	return _last_wave_duration


## Starts the completion wave and returns the seconds to wait before showing the summary
## (0 with reduced motion: everything just glows at once).
func play_completion_wave() -> float:
	if _model == null:
		return 0.0
	var motion := VisualTuning.is_motion_enabled()
	var schedule := NetworkWave.schedule(_model, _last_moved_id)
	var neuron_delays: Dictionary = schedule["neurons"]
	for id: int in neuron_delays:
		var view: NeuronView = _neuron_views.get(id)
		if view != null and is_instance_valid(view):
			view.play_wave(neuron_delays[id] if motion else 0.0)
	if motion:
		var edges: Array = schedule["edges"]
		for i in mini(edges.size(), _dendrite_views.size()):
			var view := _dendrite_views[i]
			if is_instance_valid(view):
				view.play_wave(edges[i]["delay"], edges[i]["from_a"], edges[i]["duration"])
	var duration: float = schedule["duration"] if motion else 0.0
	for membrane in _membranes:
		if is_instance_valid(membrane):
			membrane.exhale(maxf(duration, 1.2) + 0.6)
	_last_wave_duration = duration
	_wave_end_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	return duration


func _process(delta: float) -> void:
	if not _pending_explosions.is_empty():
		for pending in _pending_explosions:
			pending["wait"] -= delta
		for pending in _pending_explosions.filter(func(p: Dictionary) -> bool: return p["wait"] <= 0.0):
			_explode(pending["pos"])
		_pending_explosions = _pending_explosions.filter(func(p: Dictionary) -> bool: return p["wait"] > 0.0)
	if _flashes.is_empty() and _blasts.is_empty():
		return
	for flash in _flashes:
		flash["age"] += delta
	for blast in _blasts:
		blast["age"] += delta
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return f["age"] < VisualTuning.BREAK_FLASH_TIME)
	_blasts = _blasts.filter(func(f: Dictionary) -> bool: return f["age"] < VisualTuning.EXPLOSION_FLASH_TIME)
	queue_redraw()


func _draw() -> void:
	for flash in _flashes:
		_draw_break_flash(flash["a"], flash["b"], flash["age"] / VisualTuning.BREAK_FLASH_TIME)
	for blast in _blasts:
		_draw_overload_flash(blast["pos"], blast["age"] / VisualTuning.EXPLOSION_FLASH_TIME)


## Overload flash: a white-violet core, a fast expanding shock ring and a wide fading glow.
func _draw_overload_flash(center: Vector2, t: float) -> void:
	var fade := 1.0 - t
	var color := Palette.OVERLOAD_FLASH
	draw_circle(center, 30.0 + 40.0 * t, Color(1.0, 1.0, 1.0, 0.8 * fade * fade))
	for i in 3:
		draw_circle(center, (60.0 + 220.0 * t) * (1.0 + i * 0.5), Color(color, 0.16 * fade / (i + 1)))
	draw_arc(center, 40.0 + 260.0 * t, 0.0, TAU, 48, Color(Palette.LETHAL_CRACKLE, 0.7 * fade), 4.0 * fade + 1.0, true)


## Snap flash: a bright line that fades and a glow swelling from the snap point.
func _draw_break_flash(a: Vector2, b: Vector2, t: float) -> void:
	var fade := 1.0 - t
	var color := Palette.BREAK_FLASH
	draw_line(a, b, Color(color, 0.25 * fade), 22.0 * fade + 2.0)
	draw_line(a, b, Color(color, 0.9 * fade), 4.0 * fade + 1.0, true)
	var center := (a + b) * 0.5
	for i in 3:
		var radius := (18.0 + 70.0 * t) * (1.0 + i * 0.6)
		draw_circle(center, radius, Color(color, 0.18 * fade / (i + 1)))


func _on_neuron_moved(id: int, _pos: Vector2) -> void:
	_last_moved_id = id


func _on_edge_broke(edge_id: int) -> void:
	var ends := _model.get_edge_endpoints(edge_id)
	var a := _model.get_neuron_position(ends.x)
	var b := _model.get_neuron_position(ends.y)
	_flashes.append({"a": a, "b": b, "age": 0.0})
	queue_redraw()
	if VisualTuning.is_motion_enabled():
		_spawn_burst(a, b)
		_shake()


func _on_neuron_destroyed(_id: int, contact: Vector2) -> void:
	# The neuron trembles (NeuronView overload) first; the explosion follows.
	var center := contact
	if _model != null and _model.get_destroyed_id() != PuzzleModel.NO_NEURON:
		center = _model.get_neuron_position(_model.get_destroyed_id())
	_pending_explosions.append({"pos": center, "wait": VisualTuning.OVERLOAD_TIME})


func _explode(center: Vector2) -> void:
	_explosion_count += 1
	_blasts.append({"pos": center, "age": 0.0})
	queue_redraw()
	if VisualTuning.is_motion_enabled():
		_spawn_burst(center, center, Palette.OVERLOAD_FLASH, 64, 360.0)
		_spawn_burst(center, center, Palette.LETHAL_CRACKLE, 32, 220.0)
		_shake(VisualTuning.EXPLOSION_SHAKE_STRENGTH)


func _spawn_burst(a: Vector2, b: Vector2, color := Palette.TENSION, amount := 32,
		max_speed := 190.0) -> void:
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.amount = amount
	burst.lifetime = 0.8
	burst.texture = _get_spark_texture()
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	var points := PackedVector2Array()
	for i in 12:
		points.append(a.lerp(b, i / 11.0))
	burst.emission_points = points
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = max_speed
	burst.damping_min = 80.0
	burst.damping_max = 140.0
	burst.scale_amount_min = 0.15
	burst.scale_amount_max = 0.4
	burst.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	burst.color_ramp = ramp
	burst.finished.connect(burst.queue_free)
	add_child(burst)
	burst.emitting = true
	_burst_count += 1


func _shake(peak := VisualTuning.SHAKE_STRENGTH) -> void:
	if shake_target == null or not is_inside_tree():
		return
	if _shake_tween != null:
		_shake_tween.kill()
	else:
		_shake_origin = shake_target.position
	_shaking = true
	_shake_tween = create_tween()
	var steps := 6
	for i in steps:
		var strength := peak * (1.0 - float(i) / steps)
		var offset := Vector2.from_angle(randf() * TAU) * strength
		_shake_tween.tween_property(shake_target, ^"position", _shake_origin + offset,
			VisualTuning.SHAKE_TIME / (steps + 1))
	_shake_tween.tween_property(shake_target, ^"position", _shake_origin, VisualTuning.SHAKE_TIME / (steps + 1))
	_shake_tween.finished.connect(_on_shake_finished)


func _on_shake_finished() -> void:
	_shaking = false
	_shake_tween = null
	if shake_target != null:
		shake_target.position = _shake_origin


static func _get_spark_texture() -> GradientTexture2D:
	if _spark_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_spark_texture = GradientTexture2D.new()
		_spark_texture.gradient = gradient
		_spark_texture.width = 32
		_spark_texture.height = 32
		_spark_texture.fill = GradientTexture2D.FILL_RADIAL
		_spark_texture.fill_from = Vector2(0.5, 0.5)
		_spark_texture.fill_to = Vector2(1.0, 0.5)
	return _spark_texture
