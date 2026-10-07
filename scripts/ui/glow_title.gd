class_name GlowTitle
extends Control
## Animated title (SDD 5.5): the letters fade in one after another, then the whole word keeps a
## slow bioluminescent glow pulse. The glow is a few soft character outlines layered under the
## letters (draw_char_outline), drawn with an additive material, so no shader or image is needed.
## Reduced motion: fully visible at once and no pulse (static glow).
## T6.2: `text` may be a translation key; the translated text (atr) is drawn and re-measured on
## a live locale switch.

const LETTER_DELAY := 0.07
const LETTER_FADE := 0.45
const PULSE_SPEED := 1.3
const PULSE_DEPTH := 0.3
const GLOW_COLOR := Color(0.62, 0.82, 1.0)
## Glow layers: [outline size, alpha]. Wide and faint to narrow and brighter.
const GLOW_LAYERS := [[36, 0.05], [22, 0.08], [12, 0.14], [5, 0.24]]

@export var text := "":
	set(value):
		text = value
		_measure()
@export var font_size := 104:
	set(value):
		font_size = value
		_measure()

var _elapsed := 0.0
## Translated text actually drawn.
var _display := ""
var _offsets := PackedFloat32Array()
var _text_width := 0.0


## Opacity of letter index after elapsed seconds of the reveal.
static func letter_alpha(index: int, elapsed: float) -> float:
	return clampf((elapsed - index * LETTER_DELAY) / LETTER_FADE, 0.0, 1.0)


## Seconds until the last of letter_count letters is fully visible.
static func reveal_duration(letter_count: int) -> float:
	return maxf(letter_count - 1, 0) * LETTER_DELAY + LETTER_FADE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func _ready() -> void:
	_measure()
	if not VisualTuning.is_motion_enabled():
		_elapsed = reveal_duration(_display.length())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_measure()


## The text as drawn (translated when `text` is a key).
func get_display_text() -> String:
	return atr(text)


## Replays the letter reveal (instantly complete with reduced motion).
func restart() -> void:
	_elapsed = 0.0 if VisualTuning.is_motion_enabled() else reveal_duration(_display.length())
	queue_redraw()


func is_revealed() -> bool:
	return _elapsed >= reveal_duration(_display.length())


## Moves the animation clock forward (used by _process; public for tests).
func advance(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if VisualTuning.is_motion_enabled():
		advance(delta)
	elif not is_revealed():
		_elapsed = reveal_duration(_display.length())
		queue_redraw()


func _measure() -> void:
	if not is_inside_tree():
		return
	_display = get_display_text()
	var font := get_theme_default_font()
	_offsets = PackedFloat32Array()
	for i in _display.length():
		_offsets.append(font.get_string_size(_display.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	_text_width = font.get_string_size(_display, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	custom_minimum_size = Vector2(_text_width + 80.0, font.get_height(font_size) + 40.0)
	queue_redraw()


func _draw() -> void:
	if _display.is_empty() or _offsets.size() != _display.length():
		return
	var font := get_theme_default_font()
	var baseline := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var origin := Vector2((size.x - _text_width) * 0.5, baseline)
	var pulse := 1.0
	if VisualTuning.is_motion_enabled() and is_revealed():
		var t := _elapsed - reveal_duration(_display.length())
		pulse = 1.0 + PULSE_DEPTH * sin(t * PULSE_SPEED - PI * 0.5)
	# Layer by layer (not letter by letter): each outline size lives in its own glyph cache
	# texture, so this order lets the canvas batch every layer into one draw call.
	for layer: Array in GLOW_LAYERS:
		for i in _display.length():
			var alpha := letter_alpha(i, _elapsed)
			if alpha > 0.0:
				draw_char_outline(font, origin + Vector2(_offsets[i], 0.0), _display[i], font_size, layer[0],
					Color(GLOW_COLOR, layer[1] * alpha * pulse))
	for i in _display.length():
		var alpha := letter_alpha(i, _elapsed)
		if alpha > 0.0:
			draw_char(font, origin + Vector2(_offsets[i], 0.0), _display[i], font_size, Color(1, 1, 1, alpha))
