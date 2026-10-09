class_name BossIntro
extends Control
## Boss intro card (T8.6), drawn in code: the screen darkens, two red bars sweep out from the
## center, a spiky red crown spins up behind the title, the "BOSS" tag spreads its letters and the
## mission name (a translation key) fades in letter by letter (GlowTitle). It runs for DURATION
## seconds (REDUCED_DURATION with reduced motion: a still card), then hides itself and emits
## `finished`. A press or Accept after SKIP_AFTER seconds skips it. The Level plays the stinger
## (AudioDirector, boss_stinger) when it emits boss_intro_started.
##
## advance(delta) drives the clock (called by _process; public for tests). Everything is derived
## from the elapsed time by the static helpers below, so the sequencing is testable without frames.

signal finished()

const DURATION := 3.2
const REDUCED_DURATION := 1.4
const FADE_IN := 0.45
const FADE_OUT := 0.45
const SKIP_AFTER := 0.6
const TITLE_DELAY := 0.4
const TITLE_SIZE := 96
const SPIKES := 28
const BAR_OFFSET := 130.0
const TAG_SIZE := 34
## Distance of the lines from the center row and their maximum half length.
const BAR_HALF_LENGTH := 760.0

var _elapsed := 0.0
var _duration := DURATION
var _playing := false
var _title := GlowTitle.new()
var _title_key := ""


## 0..1 overall opacity of the card at elapsed seconds (fade in, hold, fade out).
static func card_alpha(elapsed: float, duration: float) -> float:
	var fade_in := clampf(elapsed / FADE_IN, 0.0, 1.0)
	var fade_out := clampf((duration - elapsed) / FADE_OUT, 0.0, 1.0)
	return minf(fade_in, fade_out)


## 0..1 growth of the bars and the crown (eased out), 1 with reduced motion handled by the caller.
static func sweep(elapsed: float) -> float:
	var t := clampf(elapsed / (FADE_IN * 2.0), 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_title.font_size = TITLE_SIZE
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)


## Starts the card for a boss mission (title_key is the LevelData.mission_name key).
func play(title_key: String) -> void:
	_title_key = title_key
	_title.text = title_key
	_elapsed = 0.0
	_duration = DURATION if VisualTuning.is_motion_enabled() else REDUCED_DURATION
	_playing = true
	visible = true
	_layout_title()
	_title.restart()
	queue_redraw()


func is_playing() -> bool:
	return _playing


func get_elapsed() -> float:
	return _elapsed


func get_duration() -> float:
	return _duration


func get_title_key() -> String:
	return _title_key


func get_title() -> GlowTitle:
	return _title


## Ends the card now (emits finished once).
func skip() -> void:
	if _playing:
		_finish()


func advance(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		_finish()
		return
	_title.modulate.a = card_alpha(_elapsed, _duration)
	queue_redraw()


func _process(delta: float) -> void:
	if _playing:
		advance(delta)


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed and _elapsed >= SKIP_AFTER:
		accept_event()
		skip()


func _unhandled_input(event: InputEvent) -> void:
	if _playing and _elapsed >= SKIP_AFTER and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		skip()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _title != null:
		_layout_title()


func _finish() -> void:
	_playing = false
	visible = false
	finished.emit()


func _layout_title() -> void:
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title.custom_minimum_size = Vector2(1500.0, 160.0)
	_title.size = Vector2(1500.0, 160.0)
	_title.position = size * 0.5 - _title.size * 0.5 + Vector2(0.0, 10.0)


func _draw() -> void:
	if not _playing:
		return
	var motion := VisualTuning.is_motion_enabled()
	var alpha := card_alpha(_elapsed, _duration)
	var grow := sweep(_elapsed) if motion else 1.0
	var center := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.86 * alpha))
	_draw_crown(center, alpha, grow, motion)
	for side in [-1.0, 1.0]:
		var y: float = center.y + side * BAR_OFFSET
		var half := BAR_HALF_LENGTH * grow
		draw_line(Vector2(center.x - half, y), Vector2(center.x + half, y), Color(Palette.BOSS_GLOW, 0.18 * alpha), 14.0, true)
		draw_line(Vector2(center.x - half, y), Vector2(center.x + half, y), Color(Palette.BOSS, 0.9 * alpha), 3.0, true)
	_draw_tag(center + Vector2(0.0, -BAR_OFFSET - 44.0), alpha, grow)


## Spinning ring of red spikes behind the title with a soft red core glow.
func _draw_crown(center: Vector2, alpha: float, grow: float, motion: bool) -> void:
	var turn := _elapsed * 0.35 if motion else 0.0
	var radius := 200.0 + 70.0 * grow
	GlowTexture.draw(self, center, radius * 3.2, Color(Palette.BOSS_GLOW, 0.22 * alpha * grow))
	for i in SPIKES:
		var angle := TAU * i / SPIKES + turn
		var tall := 1.0 + 0.5 * float(i % 2 == 0)
		var direction := Vector2.from_angle(angle)
		var base := center + direction * radius
		var tip := center + direction * (radius + 46.0 * tall * grow)
		var side := Vector2(-direction.y, direction.x) * 9.0
		draw_colored_polygon(PackedVector2Array([base - side, tip, base + side]), Color(Palette.BOSS, 0.75 * alpha * grow))
	draw_arc(center, radius, 0.0, TAU, 96, Color(Palette.BOSS_GLOW, 0.5 * alpha * grow), 3.0, true)


## "BOSS" with spread letters (the spacing eases from wide to tight).
func _draw_tag(center: Vector2, alpha: float, grow: float) -> void:
	var font := get_theme_default_font()
	var text := tr(&"BOSS_TAG")
	var spacing := lerpf(40.0, 12.0, grow)
	var total := 0.0
	var widths := PackedFloat32Array()
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x
		widths.append(w)
		total += w + spacing
	total -= spacing
	var x := center.x - total * 0.5
	for i in text.length():
		draw_string(font, Vector2(x, center.y), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE,
			Color(Palette.BOSS, alpha))
		x += widths[i] + spacing
