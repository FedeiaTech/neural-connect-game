class_name PlatformProfile
extends RefCounted
## Per-platform UI sizing. One project serves desktop and mobile; the platform is detected with
## OS.has_feature("mobile") (Android/iOS exports), so nothing has to be chosen by hand.
## To preview the touch layout on a PC, run the game with the user arg: godot --path . -- --mobile-ui
## Desktop keeps the values authored in the scenes and theme.tres; mobile enlarges touch targets.

const FORCE_MOBILE_ARG := "--mobile-ui"

## Fingertip-sized targets (design pixels at the 1920x1080 canvas, about 7 mm on a phone).
const MOBILE_MIN_BUTTON_SIZE := Vector2(240, 110)
## Buttons in the "touch_compact" group share a bar with the play area (HUD top bar): a little
## smaller so they do not cover its frame.
const COMPACT_GROUP := &"touch_compact"
const MOBILE_COMPACT_BUTTON_SIZE := Vector2(200, 88)
const MOBILE_FONT_SIZE := 34
const MOBILE_BUTTON_MARGIN := Vector2(44, 28)


## Neuron grab radius = neuron radius * factor. A fingertip covers the neuron, so mobile is
## much more generous (about 4.5 mm of reach around the center on a phone).
const DESKTOP_GRAB_RADIUS_FACTOR := 1.6
const MOBILE_GRAB_RADIUS_FACTOR := 2.6


static func grab_radius_factor(mobile := is_mobile()) -> float:
	return MOBILE_GRAB_RADIUS_FACTOR if mobile else DESKTOP_GRAB_RADIUS_FACTOR


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has(FORCE_MOBILE_ARG)


## Bigger default font and roomier Button styles. No-op on desktop. Idempotent.
static func apply_to_theme(theme: Theme, mobile := is_mobile()) -> void:
	if not mobile or theme == null:
		return
	theme.default_font_size = MOBILE_FONT_SIZE
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style: StyleBox = theme.get_stylebox(style_name, &"Button")
		style.content_margin_left = MOBILE_BUTTON_MARGIN.x
		style.content_margin_right = MOBILE_BUTTON_MARGIN.x
		style.content_margin_top = MOBILE_BUTTON_MARGIN.y
		style.content_margin_bottom = MOBILE_BUTTON_MARGIN.y


## Raises the minimum size of every button under root to the touch minimum (never shrinks one).
## No-op on desktop. Call after a screen has been built.
static func adapt_buttons(root: Node, mobile := is_mobile()) -> void:
	if not mobile or root == null:
		return
	if root is BaseButton and not root is CheckButton:
		var button := root as Control
		var minimum := MOBILE_COMPACT_BUTTON_SIZE if button.is_in_group(COMPACT_GROUP) \
			else MOBILE_MIN_BUTTON_SIZE
		button.custom_minimum_size = button.custom_minimum_size.max(minimum)
	for child in root.get_children():
		adapt_buttons(child, mobile)
