class_name DriftNetwork
extends RefCounted
## Pure state of the decorative neuron network behind the main menu (SDD 5.5): neurons scattered
## with a minimum spacing (seeded, deterministic), each linked to its nearest neighbours, drifting
## slowly around their anchors. Neurons near the cursor brighten and drift away gently.
## No nodes here: MenuNetworkView steps it every frame and draws it.
##
## motion (0..1) scales every displacement: with reduced motion the network stays at its anchors
## but still brightens under the cursor.

const NEIGHBOURS := 2
const MIN_SPACING := 150.0
## Edges longer than this are dropped (keeps the web local and readable).
const MAX_EDGE_LENGTH := 420.0
const PLACEMENT_ATTEMPTS := 40
const CURSOR_RADIUS := 230.0
const CURSOR_PUSH := 42.0
const DRIFT_AMPLITUDE := 24.0
const DRIFT_SPEED_MIN := 0.08
const DRIFT_SPEED_MAX := 0.2
## Exponential easing rates (per second) for the cursor push and the brightness.
const PUSH_RATE := 3.5
const GLOW_RATE := 5.0

var _rect := Rect2()
var _keep_clear := Rect2()
var _anchors := PackedVector2Array()
var _positions := PackedVector2Array()
var _push := PackedVector2Array()
var _brightness := PackedFloat32Array()
var _phases := PackedFloat32Array()
var _speeds := PackedFloat32Array()
var _edges: Array[Vector2i] = []
var _time := 0.0


## Scatters count neurons inside rect (fewer if they do not fit), never inside keep_clear (e.g.
## the title and buttons), and links them.
func build(rect: Rect2, count: int, seed: int, keep_clear := Rect2()) -> void:
	_keep_clear = keep_clear
	_rect = rect
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_anchors = PackedVector2Array()
	for i in count:
		for attempt in PLACEMENT_ATTEMPTS:
			var candidate := Vector2(rng.randf_range(rect.position.x, rect.end.x),
				rng.randf_range(rect.position.y, rect.end.y))
			if _is_free(candidate):
				_anchors.append(candidate)
				break
	var n := _anchors.size()
	_positions = _anchors.duplicate()
	_push = PackedVector2Array()
	_push.resize(n)
	_brightness = PackedFloat32Array()
	_brightness.resize(n)
	_phases = PackedFloat32Array()
	_speeds = PackedFloat32Array()
	for i in n:
		_phases.append(rng.randf() * TAU)
		_speeds.append(rng.randf_range(DRIFT_SPEED_MIN, DRIFT_SPEED_MAX))
	_time = 0.0
	_link()


## Cursor influence 0..1 on a point: 1 under the cursor, 0 at CURSOR_RADIUS and beyond.
static func influence(point: Vector2, cursor: Vector2) -> float:
	var t := clampf(1.0 - point.distance_to(cursor) / CURSOR_RADIUS, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Advances the drift and eases the cursor reaction. has_cursor false = cursor away.
func step(delta: float, cursor: Vector2, has_cursor: bool, motion: float) -> void:
	_time += delta * motion
	var push_k := 1.0 - exp(-PUSH_RATE * delta)
	var glow_k := 1.0 - exp(-GLOW_RATE * delta)
	for i in _anchors.size():
		var t := _time * _speeds[i] * TAU + _phases[i]
		var drift := Vector2(sin(t), cos(t * 0.83 + _phases[i] * 1.7)) * DRIFT_AMPLITUDE * motion
		var base := _anchors[i] + drift
		var glow_target := 0.0
		var push_target := Vector2.ZERO
		if has_cursor:
			var k := influence(base, cursor)
			glow_target = k
			var away := base - cursor
			if k > 0.0 and away.length_squared() > 0.0001:
				push_target = away.normalized() * CURSOR_PUSH * k * motion
		_push[i] = _push[i].lerp(push_target, push_k)
		if motion <= 0.0:
			_push[i] = Vector2.ZERO
		_brightness[i] = lerpf(_brightness[i], glow_target, glow_k)
		_positions[i] = base + _push[i]


func get_count() -> int:
	return _anchors.size()


func get_anchors() -> PackedVector2Array:
	return _anchors


func get_positions() -> PackedVector2Array:
	return _positions


func get_position(index: int) -> Vector2:
	return _positions[index]


func get_brightness(index: int) -> float:
	return _brightness[index]


func get_edges() -> Array[Vector2i]:
	return _edges


## Elapsed drift time (scaled by motion); the view uses it for the dendrite pulses.
func get_time() -> float:
	return _time


func _is_free(candidate: Vector2) -> bool:
	if _keep_clear.has_area() and _keep_clear.has_point(candidate):
		return false
	for anchor in _anchors:
		if anchor.distance_to(candidate) < MIN_SPACING:
			return false
	return true


## Each neuron links to its NEIGHBOURS nearest (within MAX_EDGE_LENGTH, else its nearest one).
func _link() -> void:
	_edges = []
	var seen := {}
	var n := _anchors.size()
	for i in n:
		var order: Array[int] = []
		for j in n:
			if j != i:
				order.append(j)
		order.sort_custom(func(a: int, b: int) -> bool:
			return _anchors[i].distance_squared_to(_anchors[a]) < _anchors[i].distance_squared_to(_anchors[b]))
		for k in mini(NEIGHBOURS, order.size()):
			var j := order[k]
			if k > 0 and _anchors[i].distance_to(_anchors[j]) > MAX_EDGE_LENGTH:
				continue
			var edge := Vector2i(mini(i, j), maxi(i, j))
			if not seen.has(edge):
				seen[edge] = true
				_edges.append(edge)
