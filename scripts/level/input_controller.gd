class_name InputController
extends Node
## Translates pointer input into PuzzleModel calls (SDD 5.2, 8.5, 8.6):
## press near a neuron -> pick_neuron + grab, motion -> drag_to, release -> release.
## Mouse first, touch-ready: InputEventScreenTouch/ScreenDrag are handled per finger index and
## the mouse events emulated from that touch are ignored while the touch drag is active.
## Only one neuron is dragged at a time (the model is single pointer).
##
## Upward signals only; the LevelController binds the model and enables/disables input.

signal grab_started(id: int)
signal grab_ended(id: int)
signal restart_requested()

const MOUSE_POINTER := -1

## Node whose local space is the model space. Null means viewport space.
@export var playfield: Node2D
## Grab radius = neuron radius * this factor (SDD 5.2); bigger on mobile for fingers.
var grab_radius_factor := PlatformProfile.grab_radius_factor()

var _model: PuzzleModel
var _enabled := false
var _dragging_id := PuzzleModel.NO_NEURON
var _pointer := MOUSE_POINTER


func _ready() -> void:
	set_process(false)


## Switches to a new model, dropping any drag on the previous one.
func bind(model: PuzzleModel) -> void:
	cancel_drag()
	_model = model


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		cancel_drag()


func is_enabled() -> bool:
	return _enabled


func get_dragging_id() -> int:
	return _dragging_id


## Ends the current drag (if any) as a normal release.
func cancel_drag() -> void:
	_end_drag()


## Converts a viewport position (InputEvent.position) into playfield coordinates.
func to_playfield(viewport_position: Vector2) -> Vector2:
	if playfield == null:
		return viewport_position
	if playfield.is_inside_tree():
		return playfield.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return playfield.transform.affine_inverse() * viewport_position


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart", false, true):
		restart_requested.emit()
		_mark_handled()
		return
	if not _enabled or _model == null:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_drag(touch.position, touch.index)
		elif touch.index == _pointer:
			_end_drag()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pointer:
			_drag(drag.position)
	elif event is InputEventMouseMotion:
		if _pointer == MOUSE_POINTER:
			_drag((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if event.is_action_pressed(&"grab"):
			_begin_drag(button.position, MOUSE_POINTER)
		elif event.is_action_released(&"grab") and _pointer == MOUSE_POINTER:
			_end_drag()


func _notification(what: int) -> void:
	# A release that happens while the window has no focus never reaches us: end the drag.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_drag()


func _process(_delta: float) -> void:
	_check_lost_release()


## Safety net for a mouse release outside the window: if the grab button is no longer held,
## end the drag. Touch drags are ended by their own release event.
func _check_lost_release() -> void:
	if _dragging_id != PuzzleModel.NO_NEURON and _pointer == MOUSE_POINTER \
			and not Input.is_action_pressed(&"grab"):
		_end_drag()


func _begin_drag(viewport_position: Vector2, pointer: int) -> void:
	if _dragging_id != PuzzleModel.NO_NEURON:
		return
	var grab_radius := _model.get_neuron_radius() * grab_radius_factor
	var id := _model.pick_neuron(to_playfield(viewport_position), grab_radius)
	if id == PuzzleModel.NO_NEURON or not _model.grab(id):
		return
	_dragging_id = id
	_pointer = pointer
	set_process(pointer == MOUSE_POINTER)
	_mark_handled()
	grab_started.emit(id)


func _drag(viewport_position: Vector2) -> void:
	if _dragging_id == PuzzleModel.NO_NEURON:
		return
	_model.drag_to(to_playfield(viewport_position))
	# A tension dendrite may have broken: the model dropped the grab.
	if _model.get_grabbed_id() != _dragging_id:
		_end_drag()


func _end_drag() -> void:
	if _dragging_id == PuzzleModel.NO_NEURON:
		return
	var id := _dragging_id
	# Clear first: release() may emit solved, and its listeners may call back into us.
	_dragging_id = PuzzleModel.NO_NEURON
	_pointer = MOUSE_POINTER
	set_process(false)
	_model.release()
	grab_ended.emit(id)


func _mark_handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()
