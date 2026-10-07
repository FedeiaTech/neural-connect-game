class_name ObstacleView
extends Node2D
## Draws one obstacle polygon as a thick white outline (SDD 5.3). Static: obstacles never move.

const LINE_WIDTH := 5.0

var _outline := PackedVector2Array()


func setup(polygon: PackedVector2Array) -> void:
	_outline = OutlineUtils.closed(polygon)
	queue_redraw()


## Closed outline (first point repeated at the end).
func get_outline() -> PackedVector2Array:
	return _outline.duplicate()


func get_line_width() -> float:
	return LINE_WIDTH


func _draw() -> void:
	_draw_obstacle()


func _draw_obstacle() -> void:
	if _outline.size() >= 2:
		draw_polyline(_outline, Palette.OBSTACLE, LINE_WIDTH, true)
