class_name BoundaryView
extends Node2D
## Draws the play area outline in white, thicker than dendrites (SDD 5.3).
## Placeholder for the living membrane (Phase 4). It already listens to neuron_blocked and
## keeps the last contact point, which is where the membrane ripple will start.

const LINE_WIDTH := 6.0

var _outline := PackedVector2Array()
var _last_contact := Vector2.INF


func setup(model: PuzzleModel) -> void:
	_outline = OutlineUtils.closed(model.get_play_area())
	_last_contact = Vector2.INF
	model.neuron_blocked.connect(_on_neuron_blocked)
	queue_redraw()


## Closed outline (first point repeated at the end).
func get_outline() -> PackedVector2Array:
	return _outline.duplicate()


func get_line_width() -> float:
	return LINE_WIDTH


## Last neuron stop position reported by the model, or Vector2.INF if none.
func get_last_contact() -> Vector2:
	return _last_contact


func _draw() -> void:
	_draw_boundary()


func _draw_boundary() -> void:
	if _outline.size() >= 2:
		draw_polyline(_outline, Palette.BOUNDARY, LINE_WIDTH, true)


func _on_neuron_blocked(_id: int, contact: Vector2) -> void:
	_last_contact = contact
