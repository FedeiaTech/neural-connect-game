class_name GeometryUtils
extends RefCounted
## Stateless 2D geometry helpers for the puzzle rules. No nodes.

## Tolerance used for contacts and collinearity, in playfield units.
const EPSILON := 0.001


## True when segments a1-a2 and b1-b2 intersect, including touching endpoints and
## collinear overlaps (Geometry2D returns null for parallel segments, so those are handled here).
static func segments_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null:
		return true
	return _collinear_overlap(a1, a2, b1, b2)


## Shortest distance from point to the outline (edges) of a closed polygon.
static func distance_to_outline(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	var count := polygon.size()
	for i in count:
		var from := polygon[i]
		var to := polygon[(i + 1) % count]
		var closest := Geometry2D.get_closest_point_to_segment(point, from, to)
		best = minf(best, point.distance_to(closest))
	return best


## True when the whole circle lies inside the polygon (touching the outline is allowed).
static func is_circle_inside_polygon(center: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3 or not Geometry2D.is_point_in_polygon(center, polygon):
		return false
	return distance_to_outline(center, polygon) >= radius - EPSILON


## True when the circle and the polygon share any area (touching the outline is not overlap).
static func does_circle_overlap_polygon(center: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(center, polygon):
		return true
	return distance_to_outline(center, polygon) < radius - EPSILON


## True when a circle is fully inside the play area and outside every obstacle.
static func is_circle_in_playfield(
	center: Vector2,
	radius: float,
	play_area: PackedVector2Array,
	obstacles: Array[PackedVector2Array],
) -> bool:
	if not is_circle_inside_polygon(center, radius, play_area):
		return false
	for obstacle: PackedVector2Array in obstacles:
		if does_circle_overlap_polygon(center, radius, obstacle):
			return false
	return true


static func _collinear_overlap(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var direction := a2 - a1
	var length := direction.length()
	if length < EPSILON:
		return false
	var unit := direction / length
	# Both b endpoints must lie on the infinite line through a.
	if absf(unit.cross(b1 - a1)) > EPSILON or absf(unit.cross(b2 - a1)) > EPSILON:
		return false
	var t1 := unit.dot(b1 - a1)
	var t2 := unit.dot(b2 - a1)
	return maxf(t1, t2) >= -EPSILON and minf(t1, t2) <= length + EPSILON
