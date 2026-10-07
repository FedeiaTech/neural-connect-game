class_name OutlineUtils
extends RefCounted
## Helpers shared by outline views.


## Returns the polygon with its first point appended, ready for draw_polyline.
static func closed(polygon: PackedVector2Array) -> PackedVector2Array:
	var outline := polygon.duplicate()
	if outline.size() >= 2:
		outline.append(outline[0])
	return outline
