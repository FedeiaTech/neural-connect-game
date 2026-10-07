class_name NeuronView
extends Node2D
## Draws one neuron (SDD 3, 4). Placeholder look: filled circle, white (red when fixed),
## crossing color when involved in a crossing, slightly larger and brighter while grabbed.
##
## Wiring: setup() connects this view to the model signals it needs (neuron_moved,
## crossings_changed, neuron_blocked) and filters them by id. The grabbed state is not a model
## concept, so the LevelController pushes it down with set_grabbed(). Freeing the view drops
## its connections automatically, which is how a restart rebuilds the views.

const GRAB_SCALE := 1.15
const CONTACT_FLASH_TIME := 0.15
const CONTACT_RING_WIDTH := 3.0
const HIGHLIGHT_RING_WIDTH := 4.0

var neuron_id := PuzzleModel.NO_NEURON

var _radius := 28.0
var _fixed := false
var _show_feedback := true
var _highlighted := false
var _grabbed := false
var _contact_flash := 0.0


func _ready() -> void:
	set_process(_contact_flash > 0.0)


func setup(id: int, model: PuzzleModel, show_feedback := true) -> void:
	neuron_id = id
	_radius = model.get_neuron_radius()
	_fixed = model.is_fixed(id)
	_show_feedback = show_feedback
	position = model.get_neuron_position(id)
	_highlighted = show_feedback and model.get_crossing_neurons().has(id)
	model.neuron_moved.connect(_on_neuron_moved)
	model.crossings_changed.connect(_on_crossings_changed)
	model.neuron_blocked.connect(_on_neuron_blocked)
	queue_redraw()


func set_grabbed(value: bool) -> void:
	if _grabbed == value:
		return
	_grabbed = value
	queue_redraw()


func is_grabbed() -> bool:
	return _grabbed


func is_highlighted() -> bool:
	return _highlighted


func is_fixed() -> bool:
	return _fixed


func is_contact_flashing() -> bool:
	return _contact_flash > 0.0


## Model radius (collision size).
func get_radius() -> float:
	return _radius


## Visual radius: grows while grabbed.
func get_draw_radius() -> float:
	return _radius * GRAB_SCALE if _grabbed else _radius


func get_fill_color() -> Color:
	if _fixed:
		return Palette.NEURON_FIXED
	if _grabbed:
		return Palette.NEURON_GRABBED
	return Palette.NEURON


func _process(delta: float) -> void:
	_contact_flash = maxf(_contact_flash - delta, 0.0)
	if _contact_flash == 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	_draw_neuron()


## The only drawing entry point, so Phase 4 can swap the look without touching state.
func _draw_neuron() -> void:
	var radius := get_draw_radius()
	draw_circle(Vector2.ZERO, radius, get_fill_color(), true, -1.0, true)
	if _highlighted:
		draw_circle(Vector2.ZERO, radius + HIGHLIGHT_RING_WIDTH, Palette.CROSSING, false,
			HIGHLIGHT_RING_WIDTH, true)
	if _contact_flash > 0.0:
		var alpha := _contact_flash / CONTACT_FLASH_TIME
		draw_circle(Vector2.ZERO, radius + 2.0 * HIGHLIGHT_RING_WIDTH,
			Color(Palette.CONTACT, Palette.CONTACT.a * alpha), false, CONTACT_RING_WIDTH, true)


func _on_neuron_moved(id: int, pos: Vector2) -> void:
	if id == neuron_id:
		position = pos


func _on_crossings_changed(_crossing_edges: Array[int], involved_neurons: Array[int]) -> void:
	var highlighted := _show_feedback and involved_neurons.has(neuron_id)
	if highlighted != _highlighted:
		_highlighted = highlighted
		queue_redraw()


func _on_neuron_blocked(id: int, _contact: Vector2) -> void:
	if id != neuron_id:
		return
	_contact_flash = CONTACT_FLASH_TIME
	set_process(true)
	queue_redraw()
