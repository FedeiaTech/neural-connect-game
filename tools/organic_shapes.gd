extends RefCounted
## Authoring helpers (T8.5), not game code: deterministic generators for the organic play areas
## and obstacles of tools/level_specs.gd. Every function is pure (same input, same polygon), so
## the committed data/levels/*.tres stay byte-stable across rebuilds.
##
## Polygons are plain PackedVector2Array outlines in playfield units, oriented like the default
## rectangle (positive shoelace area). The generators return many-vertex outlines (a vertex every
## STEP px or so) so the membrane, collision and lethal-edge indices all work on a smooth curve.
##
## Shapes: polar() blobs with lobes, hourglass(), crescent(), cell() (the smooth hull of a point
## set with a bulge around every outer point), closed_spline(), rounded() (soften the corners of
## a hand-drawn polygon), wobble() (outward-only membrane bulges) and edges_where() (pick the
## polygon edges that should be lethal).

## Typical vertex spacing of generated outlines.
const STEP := 30.0


## Closed polar curve around center: radius(theta) = 1 + sum(amp * cos(k * theta + phase)) scaled by
## rx / ry. harmonics: Array of [k, amplitude, phase]. count vertices.
static func polar(center: Vector2, rx: float, ry: float, harmonics: Array, count := 120) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		var theta := TAU * i / count
		var scale := 1.0
		for h: Array in harmonics:
			scale += float(h[1]) * cos(float(h[0]) * theta + float(h[2]))
		points.append(center + Vector2(cos(theta) * rx * scale, sin(theta) * ry * scale))
	return oriented(points)


static func circle(center: Vector2, radius: float, count := 32) -> PackedVector2Array:
	return polar(center, radius, radius, [], count)


## Two bulbs joined by a narrow neck (along x). half_width: distance from the center to the tips,
## neck: half height at the neck, bulb: half height of the bulbs.
static func hourglass(center: Vector2, half_width: float, neck: float, bulb: float, count := 140) -> PackedVector2Array:
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var steps := count / 2
	for i in steps + 1:
		var u := -1.0 + 2.0 * i / steps
		var x := center.x + u * half_width
		# Bulb profile: smooth from the neck at u = 0 to the bulbs at |u| ~ 0.62, rounded tips.
		var swell := smoothstep(0.0, 0.62, absf(u))
		var h := lerpf(neck, bulb, swell)
		var tip := 1.0
		if absf(u) > 0.7:
			tip = sqrt(maxf(1.0 - pow((absf(u) - 0.7) / 0.3, 2.0), 0.0))
		top.append(Vector2(x, center.y - h * tip))
		bottom.append(Vector2(x, center.y + h * tip))
	bottom.reverse()
	var outline := PackedVector2Array()
	outline.append_array(top)
	outline.append_array(bottom)
	return resample(dedupe(outline), STEP)


## Big ellipse with a bay bitten out of one side (a crescent opening towards bay_center).
static func crescent(center: Vector2, rx: float, ry: float, bay_center: Vector2, bay_rx: float, bay_ry: float) -> PackedVector2Array:
	var outer := polar(center, rx, ry, [[3, 0.05, 0.4]], 160)
	var bay := polar(bay_center, bay_rx, bay_ry, [], 100)
	var parts := Geometry2D.clip_polygons(outer, bay)
	return rounded(largest(parts), 26.0)


## The outline of two overlapping shapes merged (two bubbles with a waist between them).
static func union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	return rounded(largest(Geometry2D.merge_polygons(a, b)), 30.0)


## Catmull-Rom spline through the control points (closed), sampled per_segment times per span.
static func closed_spline(controls: PackedVector2Array, per_segment := 10) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := controls.size()
	for i in count:
		var p0 := controls[(i - 1 + count) % count]
		var p1 := controls[i]
		var p2 := controls[(i + 1) % count]
		var p3 := controls[(i + 2) % count]
		for k in per_segment:
			var t := float(k) / per_segment
			var t2 := t * t
			var t3 := t2 * t
			points.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return oriented(points)


## A cell membrane around a point set: the union of a disc of disc_radius around every point and
## the convex hull of the points shrunk by `shrink` (so the inside is open), closed and opened by
## `smooth` px so it has no cracks or spikes, resampled every STEP px and bulged outward by
## `bulge` px (see wobble). `clip`, when given, trims the outline to that rectangle with soft corners. Concave "bays" appear between the outer points, lobes around them.
static func cell(points: PackedVector2Array, disc_radius: float, shrink: float, smooth := 40.0,
		bulge := 10.0, cycles := 7.0, phase := 0.0, clip := Rect2()) -> PackedVector2Array:
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 0 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	var union := PackedVector2Array()
	var cores := Geometry2D.offset_polygon(hull, -shrink, Geometry2D.JOIN_ROUND)
	if not cores.is_empty():
		union = largest(cores)
	# Bridges: a narrow capsule from every point to the middle keeps the shape in one piece even where
	# the hull is a thin sliver (the shrunken core would not reach the disc of an acute tip).
	var middle := Vector2.ZERO
	for point in points:
		middle += point / points.size()
	for point in points:
		var along := (middle - point)
		if along.length() > 1.0:
			var side := Vector2(-along.y, along.x).normalized() * shrink * 0.8
			var capsule := PackedVector2Array([point - side, point + side, middle + side, middle - side])
			union = largest(Geometry2D.merge_polygons(union, capsule)) if not union.is_empty() else capsule
	for point in points:
		var disc := circle(point, disc_radius, 28)
		if union.is_empty():
			union = disc
		else:
			union = largest(Geometry2D.merge_polygons(union, disc))
	union = closing(union, smooth)
	union = rounded(union, smooth * 0.5)
	if clip.has_area():
		# Keep the arena inside the view: intersect with a rounded rectangle (soft corners).
		var frame := rounded(PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end,
			Vector2(clip.position.x, clip.end.y)]), 150.0)
		union = rounded(largest(Geometry2D.intersect_polygons(union, frame)), smooth * 0.5)
	return wobble(resample(union, STEP), bulge, cycles, phase)


## Soften every corner of a polygon within radius px: a morphological opening (rounds convex
## corners) then a closing (rounds concave ones).
static func rounded(polygon: PackedVector2Array, radius: float) -> PackedVector2Array:
	var opened := Geometry2D.offset_polygon(polygon, -radius, Geometry2D.JOIN_ROUND)
	if opened.is_empty():
		return resample(polygon, STEP)
	var shape := largest(Geometry2D.offset_polygon(largest(opened), radius, Geometry2D.JOIN_ROUND))
	return resample(closing(shape, radius), STEP)


## Morphological closing: fills cracks and notches narrower than 2 * radius.
static func closing(polygon: PackedVector2Array, radius: float) -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(polygon, radius, Geometry2D.JOIN_ROUND)
	if grown.is_empty():
		return polygon
	var shrunk := Geometry2D.offset_polygon(largest(grown), -radius, Geometry2D.JOIN_ROUND)
	return largest(shrunk) if not shrunk.is_empty() else polygon


## Outward-only undulation of amplitude px along the outline: the free space only ever grows, so
## every point that was inside stays inside. cycles = bulges around the whole outline.
static func wobble(polygon: PackedVector2Array, amplitude: float, cycles: float, phase := 0.0) -> PackedVector2Array:
	var points := resample(polygon, STEP)
	var count := points.size()
	if count < 3 or amplitude <= 0.0:
		return points
	var orientation := 1.0 if signed_area(points) >= 0.0 else -1.0
	var result := PackedVector2Array()
	for i in count:
		var u := float(i) / count
		var tangent := (points[(i + 1) % count] - points[(i - 1 + count) % count]).normalized()
		var outward := Vector2(tangent.y, -tangent.x) * orientation
		var a := 0.5 + 0.5 * sin(TAU * cycles * u + phase)
		var b := 0.6 + 0.4 * sin(TAU * (cycles * 2.0 + 1.0) * u + 2.0 * phase)
		result.append((points[i] + outward * amplitude * a * b).round())
	return result


## Even resampling of a closed polygon: a vertex every `step` px along its perimeter.
static func resample(polygon: PackedVector2Array, step: float) -> PackedVector2Array:
	var count := polygon.size()
	if count < 3:
		return polygon
	var perimeter := 0.0
	for i in count:
		perimeter += polygon[i].distance_to(polygon[(i + 1) % count])
	var target := maxi(int(round(perimeter / step)), 8)
	var spacing := perimeter / target
	var result := PackedVector2Array()
	var edge := 0
	var edge_start := 0.0
	var edge_length := polygon[0].distance_to(polygon[1 % count])
	for k in target:
		var distance := spacing * k
		while distance > edge_start + edge_length and edge < count - 1:
			edge_start += edge_length
			edge += 1
			edge_length = polygon[edge].distance_to(polygon[(edge + 1) % count])
		var t := 0.0 if edge_length <= 0.0 else clampf((distance - edge_start) / edge_length, 0.0, 1.0)
		result.append(polygon[edge].lerp(polygon[(edge + 1) % count], t).round())
	return result


## Indices of the polygon edges (edge i = point i -> i + 1) for which predicate(midpoint,
## outward_normal) is true. Used to pick lethal sides of an organic outline.
static func edges_where(polygon: PackedVector2Array, predicate: Callable) -> Array:
	var result := []
	var count := polygon.size()
	var orientation := 1.0 if signed_area(polygon) >= 0.0 else -1.0
	for i in count:
		var a := polygon[i]
		var b := polygon[(i + 1) % count]
		var direction := (b - a).normalized()
		var outward := Vector2(direction.y, -direction.x) * orientation
		if predicate.call((a + b) * 0.5, outward):
			result.append(i)
	return result


## Segment pairs (a0, b0, a1, b1, ...) of the given polygon edges (for placement margins).
static func edge_segments(polygon: PackedVector2Array, indices: Array) -> PackedVector2Array:
	var segments := PackedVector2Array()
	for index: int in indices:
		segments.append(polygon[index])
		segments.append(polygon[(index + 1) % polygon.size()])
	return segments


static func signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


## Same outline, oriented like the default rectangle (positive shoelace area).
static func oriented(polygon: PackedVector2Array) -> PackedVector2Array:
	if signed_area(polygon) >= 0.0:
		return polygon
	var flipped := polygon.duplicate()
	flipped.reverse()
	return flipped


## The polygon with the largest area (outer outlines; holes have the opposite winding and are
## smaller than the shape that contains them).
static func largest(polygons: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for polygon: PackedVector2Array in polygons:
		var area := absf(signed_area(polygon))
		if area > best_area:
			best = polygon
			best_area = area
	return oriented(best)


## Removes consecutive duplicate vertices (and a repeated closing vertex).
static func dedupe(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in polygon:
		if result.is_empty() or not result[result.size() - 1].is_equal_approx(point):
			result.append(point)
	if result.size() > 1 and result[0].is_equal_approx(result[result.size() - 1]):
		result.remove_at(result.size() - 1)
	return result
