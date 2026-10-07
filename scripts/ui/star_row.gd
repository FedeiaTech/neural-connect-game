class_name StarRow
extends Control
## Draws MAX_STARS five-point stars (no image assets, SDD 5.5). `stars` is the score; `lit` is how
## many are shown lit, so the summary can light them one by one with light(). Setting `stars`
## lights them all at once (static use). Lit stars glow; a newly lit star pops (swells and
## flashes) unless reduced motion is on.

signal star_revealed(index: int)

const MAX_STARS := 3
const INNER_RATIO := 0.45
const OUTLINE_WIDTH := 2.0
const EMPTY_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const FILLED_COLOR := Color(1.0, 1.0, 1.0)
const GLOW_COLOR := Color(0.6, 0.82, 1.0)
const POP_TIME := 0.45
const POP_SCALE := 0.55

var stars := 0:
	set(value):
		stars = clampi(value, 0, MAX_STARS)
		_lit = stars
		queue_redraw()

var _lit := 0
var _pop_age := PackedFloat32Array([-1.0, -1.0, -1.0])


## Ten vertices of a five-point star, first point straight up.
static func star_points(center: Vector2, outer_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var radius := outer_radius if i % 2 == 0 else outer_radius * INNER_RATIO
		var angle := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2.from_angle(angle) * radius)
	return points


func _ready() -> void:
	set_process(false)


func get_lit_count() -> int:
	return _lit


## Shows no star lit (the score stays); used before a one-by-one reveal.
func clear_lit() -> void:
	_lit = 0
	_pop_age.fill(-1.0)
	queue_redraw()


## Lights star index (and every star before it) and announces it.
func light(index: int) -> void:
	if index < 0 or index >= MAX_STARS:
		return
	_lit = maxi(_lit, index + 1)
	if VisualTuning.is_motion_enabled():
		_pop_age[index] = 0.0
		set_process(true)
	queue_redraw()
	star_revealed.emit(index)


func _process(delta: float) -> void:
	var popping := false
	for i in MAX_STARS:
		if _pop_age[i] >= 0.0:
			_pop_age[i] += delta
			if _pop_age[i] >= POP_TIME:
				_pop_age[i] = -1.0
			else:
				popping = true
	if not popping:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var spacing := size.x / MAX_STARS
	var radius := minf(spacing, size.y) * 0.4
	for i in MAX_STARS:
		var center := Vector2(spacing * (i + 0.5), size.y * 0.5)
		if i < _lit:
			var pop := 0.0
			if _pop_age[i] >= 0.0:
				var t := _pop_age[i] / POP_TIME
				pop = (1.0 - t) * (1.0 - t)
			GlowTexture.draw(self, center, radius * (1.9 + pop * 1.6), Color(GLOW_COLOR, 0.4 + 0.5 * pop))
			draw_colored_polygon(star_points(center, radius * (1.0 + POP_SCALE * pop)), FILLED_COLOR)
		else:
			var points := star_points(center, radius)
			points.append(points[0])
			draw_polyline(points, EMPTY_COLOR, OUTLINE_WIDTH, true)
