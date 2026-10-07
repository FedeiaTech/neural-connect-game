class_name MissionNode
extends BaseButton
## One mission in MissionSelect, drawn procedurally as a neuron-like circle with its number and
## best stars below (SDD 5.5, no images). Locked = dim and disabled, unlocked = bright outline,
## completed = filled. Being a BaseButton it gets pressed/focus/hover for free.

enum State { LOCKED, UNLOCKED, COMPLETED }

const RADIUS := 44.0
const STAR_RADIUS := 11.0
const STAR_SPACING := 28.0
const OUTLINE_WIDTH := 3.0
const FOCUS_GAP := 8.0
const LOCKED_ALPHA := 0.25
const HOVER_FILL := Color(1.0, 1.0, 1.0, 0.15)
const NODE_SIZE := Vector2(140.0, 150.0)

var mission_id: StringName = &""
var number := 0
var state := State.LOCKED:
	set(value):
		state = value
		disabled = value == State.LOCKED
		focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
		queue_redraw()
var stars := 0:
	set(value):
		stars = clampi(value, 0, StarRow.MAX_STARS)
		queue_redraw()


static func state_for(unlocked: bool, completed: bool) -> State:
	if completed:
		return State.COMPLETED
	return State.UNLOCKED if unlocked else State.LOCKED


func _init() -> void:
	custom_minimum_size = NODE_SIZE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	state = State.LOCKED


func setup(p_mission_id: StringName, p_number: int, p_state: State, p_stars: int,
		p_name: String) -> void:
	mission_id = p_mission_id
	number = p_number
	state = p_state
	stars = p_stars
	tooltip_text = p_name if p_state != State.LOCKED else "Locked"


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, NOTIFICATION_FOCUS_ENTER, \
				NOTIFICATION_FOCUS_EXIT:
			queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, RADIUS + FOCUS_GAP + 2.0)
	var alpha := LOCKED_ALPHA if state == State.LOCKED else 1.0
	var white := Color(1.0, 1.0, 1.0, alpha)
	if state == State.COMPLETED:
		draw_circle(center, RADIUS, white)
	else:
		if is_hovered() and not disabled:
			draw_circle(center, RADIUS, HOVER_FILL)
		draw_arc(center, RADIUS, 0.0, TAU, 64, white, OUTLINE_WIDTH, true)
	if has_focus():
		draw_arc(center, RADIUS + FOCUS_GAP, 0.0, TAU, 64, white, 1.5, true)
	_draw_number(center, Color.BLACK if state == State.COMPLETED else white)
	_draw_stars(Vector2(center.x, center.y + RADIUS + FOCUS_GAP + STAR_RADIUS + 6.0), alpha)


func _draw_number(center: Vector2, color: Color) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text := str(number)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, color)


func _draw_stars(center: Vector2, alpha: float) -> void:
	for i in StarRow.MAX_STARS:
		var star_center := center + Vector2((i - 1) * STAR_SPACING, 0.0)
		var points := StarRow.star_points(star_center, STAR_RADIUS)
		if i < stars:
			draw_colored_polygon(points, Color(1.0, 1.0, 1.0, alpha))
		else:
			points.append(points[0])
			draw_polyline(points, Color(1.0, 1.0, 1.0, alpha * 0.35), 1.5, true)
