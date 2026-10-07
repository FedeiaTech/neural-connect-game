class_name StarRow
extends Control
## Draws MAX_STARS five-point stars, the first `stars` filled (no image assets, SDD 5.5).

const MAX_STARS := 3
const INNER_RATIO := 0.45
const OUTLINE_WIDTH := 2.0
const EMPTY_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const FILLED_COLOR := Color(1.0, 1.0, 1.0)

var stars := 0:
	set(value):
		stars = clampi(value, 0, MAX_STARS)
		queue_redraw()


## Ten vertices of a five-point star, first point straight up.
static func star_points(center: Vector2, outer_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var radius := outer_radius if i % 2 == 0 else outer_radius * INNER_RATIO
		var angle := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2.from_angle(angle) * radius)
	return points


func _draw() -> void:
	var spacing := size.x / MAX_STARS
	var radius := minf(spacing, size.y) * 0.4
	for i in MAX_STARS:
		var points := star_points(Vector2(spacing * (i + 0.5), size.y * 0.5), radius)
		if i < stars:
			draw_colored_polygon(points, FILLED_COLOR)
		else:
			points.append(points[0])
			draw_polyline(points, EMPTY_COLOR, OUTLINE_WIDTH, true)
