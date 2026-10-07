class_name MembraneOutline
extends RefCounted
## Living membrane outline (SDD 5.3, 5.4), shared by BoundaryView and ObstacleView.
## Cosmetic only: the collision polygon in the model never changes.
##
## build() resamples a polygon into evenly spaced points with outward normals (pointing out of
## the given polygon). displaced() offsets each point along its normal by:
##   - a slow undulation (two waves travelling around the outline plus a breath), bounded by
##     the amplitude and seamless where the outline closes;
##   - local ripples started by add_ripple() at a contact point (bulge, then a fading ring);
##   - an "exhale" push (completion).
## All offsets are multiplied by motion (0 with reduced motion = static outline).

var _base := PackedVector2Array()
var _normals := PackedVector2Array()
## Arc length position of each point.
var _arc := PackedFloat32Array()
var _perimeter := 0.0
var _cycles_a := 1
var _cycles_b := 1
## x = arc position, y = start time.
var _ripples: Array[Vector2] = []


func build(polygon: PackedVector2Array, spacing := VisualTuning.MEMBRANE_SPACING) -> void:
	_base = PackedVector2Array()
	_normals = PackedVector2Array()
	_arc = PackedFloat32Array()
	_ripples.clear()
	_perimeter = 0.0
	var count := polygon.size()
	if count < 2:
		return
	var orientation := 1.0 if _signed_area(polygon) >= 0.0 else -1.0
	var edge_normals := PackedVector2Array()
	for i in count:
		var direction := (polygon[(i + 1) % count] - polygon[i]).normalized()
		edge_normals.append(Vector2(direction.y, -direction.x) * orientation)
	for i in count:
		var from := polygon[i]
		var to := polygon[(i + 1) % count]
		var length := from.distance_to(to)
		var steps := maxi(1, ceili(length / spacing))
		for k in steps:
			_base.append(from.lerp(to, float(k) / steps))
			_arc.append(_perimeter + length * k / steps)
			if k == 0:
				var previous := edge_normals[(i - 1 + count) % count]
				_normals.append((previous + edge_normals[i]).normalized())
			else:
				_normals.append(edge_normals[i])
		_perimeter += length
	_cycles_a = maxi(1, roundi(_perimeter / VisualTuning.MEMBRANE_WAVELENGTH_A))
	_cycles_b = maxi(1, roundi(_perimeter / VisualTuning.MEMBRANE_WAVELENGTH_B))


func get_base_points() -> PackedVector2Array:
	return _base.duplicate()


func get_normals() -> PackedVector2Array:
	return _normals.duplicate()


func get_perimeter() -> float:
	return _perimeter


## Starts a ripple at the outline point nearest to point, if it is within max_distance and no
## recent ripple is already running there. Returns true when a ripple started.
func add_ripple(point: Vector2, now: float, max_distance: float) -> bool:
	var nearest := _nearest(point)
	if nearest.y > max_distance:
		return false
	_prune(now)
	for ripple in _ripples:
		if now - ripple.y < VisualTuning.RIPPLE_COOLDOWN \
				and _arc_distance(nearest.x, ripple.x) < VisualTuning.RIPPLE_WIDTH * 1.5:
			return false
	_ripples.append(Vector2(nearest.x, now))
	while _ripples.size() > VisualTuning.RIPPLE_MAX:
		_ripples.remove_at(0)
	return true


func has_ripples(now: float) -> bool:
	for ripple in _ripples:
		if now - ripple.y < VisualTuning.RIPPLE_LIFETIME:
			return true
	return false


## Closed outline (first point repeated) displaced along the normals at time now.
func displaced(now: float, amplitude: float, motion: float, exhale: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(_base.size() + 1)
	for i in _base.size():
		var offset := 0.0
		if motion > 0.0:
			var u := _arc[i] / _perimeter
			offset = wave_offset(u, now, amplitude, _cycles_a, _cycles_b) + _ripple_sum(_arc[i], now) \
				+ exhale * VisualTuning.EXHALE_AMPLITUDE
			offset *= motion
		points[i] = _base[i] + _normals[i] * offset
	if not _base.is_empty():
		points[_base.size()] = points[0]
	return points


## Undulation at normalized arc position u (0..1) and time t. |result| <= amplitude and
## u = 0 and u = 1 give the same value (whole cycles around the outline).
static func wave_offset(u: float, t: float, amplitude: float, cycles_a: int, cycles_b: int) -> float:
	return amplitude * (
		0.55 * sin(TAU * cycles_a * u + t * VisualTuning.MEMBRANE_SPEED_A)
		+ 0.3 * sin(TAU * cycles_b * u - t * VisualTuning.MEMBRANE_SPEED_B + 1.3)
		+ 0.15 * sin(t * VisualTuning.MEMBRANE_BREATH_SPEED))


## Ripple displacement at arc distance from its center, age seconds after it started:
## a bulge of RIPPLE_AMPLITUDE at the center that spreads into a fading ring, 0 after its lifetime.
static func ripple_offset(distance: float, age: float) -> float:
	if age < 0.0 or age >= VisualTuning.RIPPLE_LIFETIME:
		return 0.0
	var envelope := exp(-age * 2.5) * (1.0 - age / VisualTuning.RIPPLE_LIFETIME)
	var width := VisualTuning.RIPPLE_WIDTH + age * VisualTuning.RIPPLE_SPREAD
	var spatial := exp(-pow(distance / width, 2.0))
	return VisualTuning.RIPPLE_AMPLITUDE * envelope * spatial * cos(distance * 0.05 - age * 9.0)


func _ripple_sum(arc: float, now: float) -> float:
	var total := 0.0
	for ripple in _ripples:
		total += ripple_offset(_arc_distance(arc, ripple.x), now - ripple.y)
	return clampf(total, -VisualTuning.RIPPLE_AMPLITUDE, VisualTuning.RIPPLE_AMPLITUDE)


func _prune(now: float) -> void:
	_ripples = _ripples.filter(func(r: Vector2) -> bool: return now - r.y < VisualTuning.RIPPLE_LIFETIME)


## x = arc position of the nearest outline point, y = its distance to point.
func _nearest(point: Vector2) -> Vector2:
	var best := Vector2(0.0, INF)
	var count := _base.size()
	for i in count:
		var a := _base[i]
		var b := _base[(i + 1) % count]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := point.distance_to(closest)
		if distance < best.y:
			best = Vector2(fposmod(_arc[i] + a.distance_to(closest), _perimeter), distance)
	return best


func _arc_distance(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, _perimeter - d)


static func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
