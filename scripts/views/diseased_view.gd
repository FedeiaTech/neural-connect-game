class_name DiseasedView
extends Node2D
## Diseased dendrite extras (T8.3, SDD 5.4), drawn additively over the dendrites (the line itself is
## a DendriteView with a dark orange ember look):
## - Ember crackle: while an intact diseased dendrite is strained past EMBER_START, small hot
##   sparks pop off it, more of them as it nears its break length.
## - Snap: when it breaks the line stretches into two halves that retract with a bright flash, a
##   shock ring and a burst of embers (the screen shake and the particle burst are LevelFx's).
## Reduced motion: no embers and no retraction; the snap is only a fading flash.
## Everything reads the model; positions are in Playfield coordinates.

const EMBER_START := 0.5
const EMBER_LIFETIME := 0.45
const EMBER_MAX_RATE := 26.0
const SNAP_TIME := VisualTuning.DISEASED_SNAP_TIME
const SNAP_SPARKS := 18
const MAX_EMBERS := 160

var _model: PuzzleModel
## Intact diseased edge ids.
var _edges: Array[int] = []
## {"pos": Vector2, "vel": Vector2, "age": float}
var _embers: Array[Dictionary] = []
## {"a": Vector2, "b": Vector2, "age": float}
var _snaps: Array[Dictionary] = []
var _carry := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 8128


func setup(model: PuzzleModel) -> void:
	_model = model
	_edges.clear()
	_embers.clear()
	_snaps.clear()
	_carry = 0.0
	for edge_id in model.get_diseased_edges():
		if not model.is_edge_broken(edge_id):
			_edges.append(edge_id)
	model.diseased_broken.connect(_on_diseased_broken)
	queue_redraw()


func get_spark_count() -> int:
	return _embers.size()


func get_snap_count() -> int:
	return _snaps.size()


func is_snapping() -> bool:
	return not _snaps.is_empty()


func clear_sparks() -> void:
	_embers.clear()


## Number of embers per second a strain ratio spawns on one edge (0 below EMBER_START).
static func ember_rate(ratio: float) -> float:
	var t := clampf((ratio - EMBER_START) / (1.0 - EMBER_START), 0.0, 1.0)
	return EMBER_MAX_RATE * t * t


func _process(delta: float) -> void:
	tick(delta)


## Advances every effect by delta seconds (public for tests).
func tick(delta: float) -> void:
	if _model == null:
		return
	var motion := VisualTuning.is_motion_enabled()
	if motion:
		_spawn_embers(delta)
	for ember in _embers:
		ember["age"] += delta
		ember["pos"] += ember["vel"] * delta
		ember["vel"] *= exp(-4.0 * delta)
	_embers = _embers.filter(func(e: Dictionary) -> bool: return e["age"] < EMBER_LIFETIME)
	for snap in _snaps:
		snap["age"] += delta
	_snaps = _snaps.filter(func(s: Dictionary) -> bool: return s["age"] < SNAP_TIME)
	if not _embers.is_empty() or not _snaps.is_empty() or not _edges.is_empty():
		queue_redraw()


func _draw() -> void:
	for ember in _embers:
		var fade: float = 1.0 - ember["age"] / EMBER_LIFETIME
		var pos: Vector2 = ember["pos"]
		var tail: Vector2 = (ember["vel"] as Vector2) * 0.03
		draw_line(pos - tail, pos, Color(Palette.DISEASED_SPARK, fade), 1.6, true)
		draw_circle(pos, 1.6, Color(Palette.DISEASED_HOT, fade * 0.8), true, -1.0, true)
	for snap in _snaps:
		_draw_snap(snap["a"], snap["b"], snap["age"] / SNAP_TIME)


## Stretched line retracting in two halves with a flash and a shock ring (flash only without motion).
func _draw_snap(a: Vector2, b: Vector2, t: float) -> void:
	var fade := 1.0 - t
	var mid := (a + b) * 0.5
	var motion := VisualTuning.is_motion_enabled()
	draw_circle(mid, 14.0 + 60.0 * t, Color(Palette.DISEASED_HOT, 0.32 * fade), true, -1.0, true)
	if not motion:
		draw_line(a, b, Color(Palette.DISEASED_HOT, 0.7 * fade), 2.0, true)
		return
	draw_arc(mid, 20.0 + 90.0 * t, 0.0, TAU, 32, Color(Palette.DISEASED_SPARK, 0.7 * fade), 2.5 * fade + 0.5, true)
	var end_a := mid.lerp(a, 1.0 - t)
	var end_b := mid.lerp(b, 1.0 - t)
	draw_line(a, end_a, Color(Palette.DISEASED_HOT, 0.95 * fade), 3.0 * fade + 1.0, true)
	draw_line(b, end_b, Color(Palette.DISEASED_HOT, 0.95 * fade), 3.0 * fade + 1.0, true)


func _spawn_embers(delta: float) -> void:
	var expected := 0.0
	for edge_id in _edges:
		expected += ember_rate(_model.get_diseased_ratio(edge_id))
	if expected <= 0.0:
		_carry = 0.0
		return
	_carry += expected * delta
	while _carry >= 1.0 and _embers.size() < MAX_EMBERS:
		_carry -= 1.0
		var edge_id := _pick_edge()
		var ends := _model.get_edge_endpoints(edge_id)
		var a := _model.get_neuron_position(ends.x)
		var b := _model.get_neuron_position(ends.y)
		_embers.append({"pos": a.lerp(b, _rng.randf_range(0.1, 0.9)),
			"vel": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(30.0, 110.0), "age": 0.0})
	_carry = minf(_carry, 1.0)


## An intact edge, weighted by its ember rate.
func _pick_edge() -> int:
	var total := 0.0
	for edge_id in _edges:
		total += ember_rate(_model.get_diseased_ratio(edge_id))
	var roll := _rng.randf() * total
	for edge_id in _edges:
		roll -= ember_rate(_model.get_diseased_ratio(edge_id))
		if roll <= 0.0:
			return edge_id
	return _edges[0]


func _on_diseased_broken(edge_id: int) -> void:
	_edges.erase(edge_id)
	var ends := _model.get_edge_endpoints(edge_id)
	var a := _model.get_neuron_position(ends.x)
	var b := _model.get_neuron_position(ends.y)
	_snaps.append({"a": a, "b": b, "age": 0.0})
	if VisualTuning.is_motion_enabled():
		for i in SNAP_SPARKS:
			_embers.append({"pos": (a + b) * 0.5 + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 10.0),
				"vel": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(80.0, 260.0), "age": 0.0})
	queue_redraw()
