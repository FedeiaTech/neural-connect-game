class_name SoftLine
extends RefCounted
## Soft glow bands for wide, faint line glows (membranes, lethal walls, receptor links).
## A plain wide draw_line has hard band edges, and its antialiasing feather only covers about one
## pixel and leaves seams where butt ends overlap. A band is instead a triangle strip across the
## line whose alpha follows PROFILE_ALPHAS (full at the center, zero at both edges), with mitered
## joints, so the glow fades out smoothly. Many strips go into one Band and are submitted with a
## single draw call (Band.draw).

## Columns across the band, from one edge (-1) through the center (0) to the other edge (1),
## and the alpha factor at each (a soft bell, not a linear ramp).
const PROFILE_OFFSETS: Array[float] = [-1.0, -0.45, 0.0, 0.45, 1.0]
const PROFILE_ALPHAS: Array[float] = [0.0, 0.42, 1.0, 0.42, 0.0]
## Longest miter, in half widths, so very sharp joints do not spike.
const MAX_MITER := 2.0


class Band:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func is_empty() -> bool:
		return indices.is_empty()

	## Appends a band along points (a closed outline repeats its first point at the end).
	func add(points: PackedVector2Array, color: Color, half_width: float) -> void:
		var count := points.size()
		if count < 2 or half_width <= 0.0:
			return
		var closed := count > 2 and points[0].is_equal_approx(points[count - 1])
		var normals := SoftLine.joint_normals(points, closed)
		if normals.is_empty():
			return
		var columns := PROFILE_OFFSETS.size()
		var base := vertices.size()
		for i in count:
			for c in columns:
				vertices.append(points[i] + normals[i] * half_width * PROFILE_OFFSETS[c])
				colors.append(Color(color, color.a * PROFILE_ALPHAS[c]))
		for i in count - 1:
			var row := base + i * columns
			var next := row + columns
			for c in columns - 1:
				indices.append_array([row + c, row + c + 1, next + c + 1, row + c, next + c + 1, next + c])

	## Submits every strip added so far in one triangle-array draw call.
	func draw(canvas: CanvasItem) -> void:
		if is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, vertices, colors)


## Convenience: one band, one draw call.
static func draw_band(canvas: CanvasItem, points: PackedVector2Array, color: Color, half_width: float) -> void:
	var band := Band.new()
	band.add(points, color, half_width)
	band.draw(canvas)


## Per-point offset direction, scaled for a miter at joints (length 1 on straight parts).
## Empty when the polyline has no length.
static func joint_normals(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var count := points.size()
	var segment_normals := PackedVector2Array()
	var last := Vector2.ZERO
	for i in count - 1:
		var d := points[i + 1] - points[i]
		if d.length_squared() > 0.0001:
			last = d.normalized().orthogonal()
		segment_normals.append(last)
	if last == Vector2.ZERO:
		return PackedVector2Array()
	# Fill leading zero-length segments with the first real direction.
	for i in range(segment_normals.size() - 1, -1, -1):
		if segment_normals[i] == Vector2.ZERO:
			segment_normals[i] = segment_normals[i + 1]
	var normals := PackedVector2Array()
	normals.resize(count)
	for i in count:
		var before: Vector2
		var after: Vector2
		if i == 0:
			after = segment_normals[0]
			before = segment_normals[count - 2] if closed else after
		elif i == count - 1:
			before = segment_normals[count - 2]
			after = segment_normals[0] if closed else before
		else:
			before = segment_normals[i - 1]
			after = segment_normals[i]
		var sum := before + after
		if sum.length_squared() < 0.0001:
			normals[i] = after
			continue
		var miter := sum.normalized()
		var cos_half := miter.dot(after)
		normals[i] = miter * minf(1.0 / maxf(cos_half, 0.0001), MAX_MITER)
	return normals
