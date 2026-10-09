class_name MissionNode
extends BaseButton
## One mission in MissionSelect, drawn procedurally as a neuron-like circle with its number and
## best stars below (SDD 5.5, no images). Locked = dim and disabled, unlocked = bright outline
## with a faint halo, completed = filled soma with a glowing halo and glowing stars.
## Being a BaseButton it gets pressed/focus/hover for free. Placed by MissionMap.
## Boss missions (T8.6) are bigger, wear a ring of red spikes (a "crown") that slowly turns while
## the node is playable, grows when hovered or focused and kicks when pressed (a short tween).

enum State { LOCKED, UNLOCKED, COMPLETED }

const RADIUS := 44.0
const STAR_RADIUS := 11.0
const STAR_SPACING := 28.0
const OUTLINE_WIDTH := 3.0
const FOCUS_GAP := 8.0
const LOCKED_ALPHA := 0.25
const HOVER_FILL := Color(0.6, 0.82, 1.0, 0.18)
const GLOW_COLOR := Color(0.6, 0.82, 1.0)
const NODE_SIZE := Vector2(140.0, 150.0)
const BOSS_RADIUS := 56.0
const BOSS_NODE_SIZE := Vector2(190.0, 196.0)
const CROWN_SPIKES := 18
const PRESS_KICK_TIME := 0.28

var mission_id: StringName = &""
## T8.6: the last mission of a chapter.
var is_boss := false
var _time := 0.0
## 0..1 hover/focus amount of the crown (eased) and the press kick (1 at the press, easing to 0).
var _crown_open := 0.0
var _kick := 0.0
var _kick_tween: Tween
## Mission name as given to setup() (a translation key for campaign missions).
var _name_key := ""
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
	set_process(false)
	button_down.connect(_on_button_down)


func setup(p_mission_id: StringName, p_number: int, p_state: State, p_stars: int,
		p_name: String, p_boss := false) -> void:
	is_boss = p_boss
	custom_minimum_size = BOSS_NODE_SIZE if is_boss else NODE_SIZE
	set_process(is_boss)
	mission_id = p_mission_id
	number = p_number
	state = p_state
	stars = p_stars
	_name_key = p_name
	_apply_tooltip()


## Tooltip: the mission name (a translation key) or "Locked", translated.
func _apply_tooltip() -> void:
	tooltip_text = tr(_name_key) if state != State.LOCKED else tr(&"MISSIONS_LOCKED")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSLATION_CHANGED:
			_apply_tooltip()
		NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, NOTIFICATION_FOCUS_ENTER, \
				NOTIFICATION_FOCUS_EXIT:
			queue_redraw()


## Soma radius (bigger for bosses).
func get_radius() -> float:
	return BOSS_RADIUS if is_boss else RADIUS


## Distance from the soma center to where MissionMap puts the name label.
func get_name_offset() -> float:
	return get_radius() + 68.0


## Offset from the node's top-left corner to the soma center (MissionMap places nodes by it).
func get_center_offset() -> Vector2:
	var box := BOSS_NODE_SIZE if is_boss else NODE_SIZE
	return Vector2(box.x * 0.5, get_radius() + FOCUS_GAP + (20.0 if is_boss else 2.0))


## Crown spikes turn slowly while the node is playable and open up under the pointer or focus.
func _process(delta: float) -> void:
	if not is_boss:
		return
	var active := (is_hovered() and not disabled) or has_focus()
	var motion := VisualTuning.is_motion_enabled()
	if motion and state != State.LOCKED:
		_time += delta
	var target := 1.0 if active else 0.0
	_crown_open = target if not motion else move_toward(_crown_open, target, delta * 5.0)
	if (motion and state != State.LOCKED) or not is_equal_approx(_crown_open, target):
		queue_redraw()


func _on_button_down() -> void:
	if not is_boss or disabled:
		return
	if _kick_tween != null:
		_kick_tween.kill()
	_kick = 1.0
	if not VisualTuning.is_motion_enabled() or not is_inside_tree():
		_kick = 0.0
		queue_redraw()
		return
	_kick_tween = create_tween()
	_kick_tween.tween_property(self, ^"_kick", 0.0, PRESS_KICK_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_kick_tween.tween_callback(queue_redraw)
	queue_redraw()


## Ring of red spikes around the soma (alternating tall and short), drawn under the soma.
func _draw_crown(center: Vector2, radius: float, alpha: float) -> void:
	var open := 0.35 + 0.65 * _crown_open + 0.4 * _kick
	var turn := _time * 0.3
	GlowTexture.draw(self, center, radius * 3.4, Color(Palette.BOSS_GLOW, 0.2 * alpha * (0.6 + _crown_open)))
	for i in CROWN_SPIKES:
		var angle := TAU * i / CROWN_SPIKES + turn
		var direction := Vector2.from_angle(angle)
		var tall := 1.0 if i % 2 == 0 else 0.55
		var base := center + direction * (radius + 4.0)
		var tip := center + direction * (radius + 4.0 + 20.0 * tall * open)
		var side := Vector2(-direction.y, direction.x) * 5.0
		draw_colored_polygon(PackedVector2Array([base - side, tip, base + side]), Color(Palette.BOSS, alpha * 0.9))


func _draw() -> void:
	var center := get_center_offset()
	var radius := get_radius() * (1.0 + 0.06 * _kick)
	var alpha := LOCKED_ALPHA if state == State.LOCKED else 1.0
	var white := Color(1.0, 1.0, 1.0, alpha)
	var active := (is_hovered() and not disabled) or has_focus()
	# Soft halo: completed neurons glow, the next playable one glows faintly, locked ones do not.
	var halo := 0.0
	match state:
		State.COMPLETED:
			halo = 0.42
		State.UNLOCKED:
			halo = 0.2
	if active:
		halo += 0.25
	if is_boss:
		_draw_crown(center, radius, alpha)
	if halo > 0.0:
		GlowTexture.draw(self, center, radius * 2.3, Color(GLOW_COLOR, halo))
	if state == State.COMPLETED:
		draw_circle(center, radius, white, true, -1.0, true)
	else:
		draw_circle(center, radius, Color(0.02, 0.035, 0.055, 0.9 * alpha), true, -1.0, true)
		if active:
			draw_circle(center, radius, HOVER_FILL, true, -1.0, true)
		draw_arc(center, radius, 0.0, TAU, 64, white, OUTLINE_WIDTH, true)
	if has_focus():
		draw_arc(center, radius + FOCUS_GAP, 0.0, TAU, 64, Color(GLOW_COLOR, 0.95), 2.0, true)
	_draw_number(center, Color(0.02, 0.04, 0.08) if state == State.COMPLETED else white)
	_draw_stars(Vector2(center.x, center.y + radius + FOCUS_GAP + STAR_RADIUS + 8.0), alpha)


func _draw_number(center: Vector2, color: Color) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text := str(number)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, color)


func _draw_stars(center: Vector2, alpha: float) -> void:
	# Glows first, shapes after: keeps textured and untextured draws batched.
	for i in stars:
		GlowTexture.draw(self, center + Vector2((i - 1) * STAR_SPACING, 0.0), STAR_RADIUS * 2.2,
			Color(GLOW_COLOR, 0.45 * alpha))
	for i in StarRow.MAX_STARS:
		var star_center := center + Vector2((i - 1) * STAR_SPACING, 0.0)
		var points := StarRow.star_points(star_center, STAR_RADIUS)
		if i < stars:
			draw_colored_polygon(points, Color(1.0, 1.0, 1.0, alpha))
		else:
			points.append(points[0])
			draw_polyline(points, Color(1.0, 1.0, 1.0, alpha * 0.35), 1.5, true)
