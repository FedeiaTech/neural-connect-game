class_name GlowButton
extends Button
## Reusable menu button (SDD 5.5): glows on hover and keyboard/gamepad focus, swells slightly,
## and sends a ripple of light outward from its border when pressed.
## The glow itself is the theme's hover/focus StyleBox (soft shadow halo); this script adds the
## motion: a hover swell and press punch through the Godot 4.7 offset transform (visual only, so
## containers never re-layout) and a fading ripple ring drawn in _draw.
## Reduced motion: no swell and no ripple; the static glow still marks hover and focus.
## Sounds are not played here: the AudioDirector listens to the standard Button signals.

const RIPPLE_TIME := 0.5
const RIPPLE_SPREAD := 22.0
const RIPPLE_COLOR := Color(0.75, 0.9, 1.0)
const HOVER_SCALE := 1.035
const PRESS_SCALE := 0.965
const SCALE_TIME := 0.14
const CORNER_RADIUS := 10

var _mouse_inside := false
## Seconds since the last press ripple started; negative when idle.
var _ripple_age := -1.0
var _scale_tween: Tween
var _ripple_box := StyleBoxFlat.new()


func _init() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	offset_transform_enabled = true
	_ripple_box.draw_center = false
	_ripple_box.set_border_width_all(2)
	_ripple_box.anti_aliasing = true


func _ready() -> void:
	button_down.connect(_on_button_down)
	set_process(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_mouse_inside = true
			_update_glow()
		NOTIFICATION_MOUSE_EXIT:
			_mouse_inside = false
			_update_glow()
		NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
			_update_glow()


## True while hovered (enabled only) or focused.
func is_glowing() -> bool:
	if disabled:
		return false
	return _mouse_inside or has_focus()


func is_rippling() -> bool:
	return _ripple_age >= 0.0


func _process(delta: float) -> void:
	_ripple_age += delta
	if _ripple_age >= RIPPLE_TIME:
		_ripple_age = -1.0
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _ripple_age < 0.0:
		return
	var t := clampf(_ripple_age / RIPPLE_TIME, 0.0, 1.0)
	var spread := RIPPLE_SPREAD * (1.0 - pow(1.0 - t, 3.0))
	_ripple_box.set_expand_margin_all(spread)
	_ripple_box.set_corner_radius_all(CORNER_RADIUS + int(spread))
	_ripple_box.border_color = Color(RIPPLE_COLOR, 0.85 * (1.0 - t))
	draw_style_box(_ripple_box, Rect2(Vector2.ZERO, size))


func _update_glow() -> void:
	_scale_to(Vector2.ONE * (HOVER_SCALE if is_glowing() else 1.0))


func _on_button_down() -> void:
	if not VisualTuning.is_motion_enabled():
		return
	_ripple_age = 0.0
	set_process(true)
	queue_redraw()
	_scale_to(Vector2.ONE * PRESS_SCALE, Vector2.ONE * (HOVER_SCALE if is_glowing() else 1.0))


## Eases the visual scale to target (then to settle, if given). Instant reset with reduced motion.
func _scale_to(target: Vector2, settle := Vector2.ZERO) -> void:
	if _scale_tween != null:
		_scale_tween.kill()
		_scale_tween = null
	if not VisualTuning.is_motion_enabled() or not is_inside_tree():
		offset_transform_scale = Vector2.ONE
		return
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, ^"offset_transform_scale", target, SCALE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if settle != Vector2.ZERO:
		_scale_tween.tween_property(self, ^"offset_transform_scale", settle, SCALE_TIME * 1.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
