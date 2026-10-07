class_name GlowTexture
extends RefCounted
## Shared procedural glow sprites (no image files, SDD 5.5): a soft radial falloff built once
## from a GradientTexture2D and reused by every _draw-based glow, so many glows batch into few
## draw calls (same texture, same additive material).

const SIZE := 64

static var _radial: GradientTexture2D


## White center fading to transparent at the edge; tint with the modulate color when drawing.
static func radial() -> GradientTexture2D:
	if _radial == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		_radial = GradientTexture2D.new()
		_radial.gradient = gradient
		_radial.width = SIZE
		_radial.height = SIZE
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
	return _radial


## Draws the radial glow centered at center with the given radius on any CanvasItem.
static func draw(item: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	item.draw_texture_rect(radial(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
		false, color)
