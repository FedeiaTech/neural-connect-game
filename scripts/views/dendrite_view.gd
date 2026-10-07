class_name DendriteView
extends Node2D
## Draws one dendrite as a straight line between its neurons (SDD 2, 3, 4).
## NORMAL: white. TENSION: light green, thinning from WIDTH to MIN_TENSION_WIDTH as the
## tension ratio goes 0 -> 1, hidden once broken. Crossing color when involved in a crossing.
##
## Wiring: setup() connects to neuron_moved, crossings_changed, tension_changed and edge_broke
## and filters by its own edge / endpoint ids. Positions are in Playfield coordinates, so the
## node itself stays at the origin. All drawing lives in _draw_dendrite() so curved or glowing
## dendrites (Phase 4) only replace that method.

const WIDTH := 3.0
const MIN_TENSION_WIDTH := 1.0

var edge_id := -1

var _a_id := PuzzleModel.NO_NEURON
var _b_id := PuzzleModel.NO_NEURON
var _a_pos := Vector2.ZERO
var _b_pos := Vector2.ZERO
var _tension := false
var _ratio := 0.0
var _show_feedback := true
var _highlighted := false
var _broken := false


func setup(id: int, model: PuzzleModel, show_feedback := true) -> void:
	edge_id = id
	var endpoints := model.get_edge_endpoints(id)
	_a_id = endpoints.x
	_b_id = endpoints.y
	_a_pos = model.get_neuron_position(_a_id)
	_b_pos = model.get_neuron_position(_b_id)
	_tension = model.is_tension_edge(id)
	_ratio = model.get_tension_ratio(id)
	_show_feedback = show_feedback
	_highlighted = show_feedback and model.get_crossing_edges().has(id)
	model.neuron_moved.connect(_on_neuron_moved)
	model.crossings_changed.connect(_on_crossings_changed)
	model.tension_changed.connect(_on_tension_changed)
	model.edge_broke.connect(_on_edge_broke)
	queue_redraw()


func get_endpoints() -> PackedVector2Array:
	return PackedVector2Array([_a_pos, _b_pos])


func is_highlighted() -> bool:
	return _highlighted


func is_broken() -> bool:
	return _broken


func get_line_width() -> float:
	if _tension:
		return lerpf(WIDTH, MIN_TENSION_WIDTH, _ratio)
	return WIDTH


func get_line_color() -> Color:
	if _highlighted:
		return Palette.CROSSING
	return Palette.TENSION if _tension else Palette.DENDRITE


func _draw() -> void:
	_draw_dendrite(_a_pos, _b_pos, get_line_color(), get_line_width())


## The only drawing entry point; replace it to change the dendrite look.
func _draw_dendrite(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width, true)


func _on_neuron_moved(id: int, pos: Vector2) -> void:
	if id == _a_id:
		_a_pos = pos
	elif id == _b_id:
		_b_pos = pos
	else:
		return
	queue_redraw()


func _on_crossings_changed(crossing_edges: Array[int], _involved_neurons: Array[int]) -> void:
	var highlighted := _show_feedback and crossing_edges.has(edge_id)
	if highlighted != _highlighted:
		_highlighted = highlighted
		queue_redraw()


func _on_tension_changed(id: int, ratio: float) -> void:
	if id == edge_id:
		_ratio = ratio
		queue_redraw()


func _on_edge_broke(id: int) -> void:
	if id == edge_id:
		_broken = true
		visible = false
