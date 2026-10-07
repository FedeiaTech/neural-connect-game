class_name LethalWallView
extends Node2D
## Electric look of the lethal walls (T7.2, SDD 5.4), drawn additively over the boundary and
## obstacle membranes (which already draw lethal parts violet): a violet glow along every lethal
## segment, magenta lightning crackling along it (re-rolled every CRACKLE_INTERVAL) and a hot
## spot on the wall nearest to the most endangered neuron. Everything gets brighter as the
## hazard proximity reported by the model rises (hazard_proximity_changed).
## Reduced motion: no crackle, the glow still follows the proximity (snapped, not eased).

const CRACKLE_INTERVAL := 0.07
## Lightning joint spacing along a segment (px) and base sideways jitter.
const CRACKLE_STEP := 16.0
const CRACKLE_JITTER := 3.0
## Extra jitter at full proximity.
const CRACKLE_JITTER_DANGER := 7.0
## Glow 0..1 eases toward the proximity at this rate (per second).
const GLOW_RATE := 6.0
const BASE_GLOW := 0.45

var _model: PuzzleModel
var _segments := PackedVector2Array()
## Segments joined into polylines where they share endpoints (soft glow with mitered corners).
var _chains: Array[PackedVector2Array] = []
var _proximity: Dictionary[int, float] = {}
var _danger := 0.0
var _glow := BASE_GLOW
var _hotspot := Vector2.INF
var _crackles: Array[PackedVector2Array] = []
var _crackle_timer := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 9091


func setup(model: PuzzleModel) -> void:
	_model = model
	_segments = model.get_lethal_segments()
	_chains = chain_segments(_segments)
	_proximity.clear()
	_danger = 0.0
	_glow = BASE_GLOW
	_hotspot = Vector2.INF
	_crackles.clear()
	visible = not _segments.is_empty()
	model.hazard_proximity_changed.connect(_on_proximity_changed)
	model.neuron_destroyed.connect(_on_destroyed)
	queue_redraw()


func get_segment_count() -> int:
	return _segments.size() / 2


## Current glow 0..1 (BASE_GLOW when nothing is close).
func get_glow() -> float:
	return _glow


## Wall point nearest to the most endangered neuron, or Vector2.INF when none is close.
func get_hotspot() -> Vector2:
	return _hotspot


func get_crackle_count() -> int:
	return _crackles.size()


## Joins segment pairs (a0, b0, a1, b1, ...) into polylines: a pair continues the current chain
## when it starts where the chain ends. A chain that returns to its start is closed (its last
## point equals its first).
static func chain_segments(segments: PackedVector2Array) -> Array[PackedVector2Array]:
	var chains: Array[PackedVector2Array] = []
	for i in range(0, segments.size() - 1, 2):
		var a := segments[i]
		var b := segments[i + 1]
		if not chains.is_empty():
			var last := chains[chains.size() - 1]
			if last[last.size() - 1].is_equal_approx(a):
				last.append(b)
				chains[chains.size() - 1] = last
				continue
		chains.append(PackedVector2Array([a, b]))
	# A closed loop split at index 0 (e.g. the last edge of a polygon listed first).
	if chains.size() > 1:
		var first := chains[0]
		var tail := chains[chains.size() - 1]
		if tail[tail.size() - 1].is_equal_approx(first[0]):
			tail.append_array(first.slice(1))
			chains[chains.size() - 1] = tail
			chains.remove_at(0)
	return chains


func _process(delta: float) -> void:
	if _segments.is_empty():
		return
	_time += delta
	var target := lerpf(BASE_GLOW, 1.0, _danger)
	if VisualTuning.is_motion_enabled():
		_glow = VisualTuning.approach(_glow, target, GLOW_RATE, delta)
		_crackle_timer -= delta
		if _crackle_timer <= 0.0:
			_crackle_timer = CRACKLE_INTERVAL
			_regenerate()
	else:
		_glow = target
		_crackles.clear()
	queue_redraw()


func _regenerate() -> void:
	_crackles.clear()
	var jitter := CRACKLE_JITTER + CRACKLE_JITTER_DANGER * _danger
	for i in range(0, _segments.size() - 1, 2):
		var a := _segments[i]
		var b := _segments[i + 1]
		var length := a.distance_to(b)
		if length < 1.0:
			continue
		# A few broken strands per segment: more of them when danger is high.
		var strands := 1 + int(_danger * 2.0 + 0.5)
		for s in strands:
			_crackles.append(_bolt(a, b, length, jitter))


func _bolt(a: Vector2, b: Vector2, length: float, jitter: float) -> PackedVector2Array:
	var direction := (b - a) / length
	var side := direction.orthogonal()
	var start := _rng.randf_range(0.0, length * 0.6)
	var span := minf(_rng.randf_range(60.0, 220.0), length - start)
	var steps := maxi(2, int(span / CRACKLE_STEP))
	var bolt := PackedVector2Array()
	for k in steps + 1:
		var along := start + span * float(k) / steps
		var offset := 0.0 if k == 0 or k == steps else _rng.randf_range(-jitter, jitter)
		bolt.append(a + direction * along + side * offset)
	return bolt


func _draw() -> void:
	var glow := _glow
	# Soft glow bands (fade to zero at the edges) for all segments in one draw call, then the
	# thin antialiased cores.
	var band := SoftLine.Band.new()
	for chain in _chains:
		band.add(chain, Color(Palette.LETHAL, 0.3 + 0.45 * glow), 21.0 + 10.0 * glow)
		band.add(chain, Color(Palette.LETHAL, 0.5 + 0.5 * glow), 8.0)
	band.draw(self)
	for i in range(0, _segments.size() - 1, 2):
		draw_line(_segments[i], _segments[i + 1], Color(Palette.LETHAL_CRACKLE, 0.35 + 0.45 * glow), 3.0, true)
	for bolt in _crackles:
		draw_polyline(bolt, Color(Palette.LETHAL_CRACKLE, 0.45 + 0.45 * glow), 3.5, true)
		draw_polyline(bolt, Color(1.0, 0.9, 1.0, 0.55 + 0.45 * glow), 1.4, true)
	if _hotspot != Vector2.INF and _danger > 0.0:
		var flicker := 1.0 if not VisualTuning.is_motion_enabled() else 0.8 + 0.2 * sin(_time * 41.0)
		for k in 3:
			draw_circle(_hotspot, (14.0 + 18.0 * k) * (0.6 + _danger),
				Color(Palette.LETHAL_CRACKLE, 0.22 * _danger * flicker / (k + 1)), true, -1.0, true)


func _on_proximity_changed(id: int, proximity: float) -> void:
	_proximity[id] = proximity
	_danger = 0.0
	var worst := PuzzleModel.NO_NEURON
	for other: int in _proximity:
		if _proximity[other] > _danger:
			_danger = _proximity[other]
			worst = other
	_hotspot = Vector2.INF if worst == PuzzleModel.NO_NEURON \
		else _model.nearest_lethal_point(_model.get_neuron_position(worst))


func _on_destroyed(_id: int, contact: Vector2) -> void:
	_danger = 1.0
	_hotspot = contact
