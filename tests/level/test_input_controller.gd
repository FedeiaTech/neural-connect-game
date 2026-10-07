extends GdUnitTestSuite
## T2.2: InputController turns pointer events into PuzzleModel calls.
## Events are fed straight into _unhandled_input; the playfield is offset by PLAYFIELD_OFFSET
## so every test also checks the viewport -> playfield conversion.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const PLAYFIELD_OFFSET := Vector2(100, 50)

var _model: PuzzleModel
var _input: InputController
var _recorder: SignalRecorder


func before_test() -> void:
	_model = PuzzleModel.from_level(LevelFactory.x_level())
	var playfield: Node2D = auto_free(Node2D.new())
	playfield.position = PLAYFIELD_OFFSET
	_input = auto_free(InputController.new())
	_input.playfield = playfield
	_input.bind(_model)
	_input.set_enabled(true)
	_recorder = SignalRecorder.new()
	_recorder.watch(_input, [&"grab_started", &"grab_ended", &"restart_requested"])


## Viewport position of a playfield point.
func _screen(local: Vector2) -> Vector2:
	return local + PLAYFIELD_OFFSET


func _mouse_button(local: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = _screen(local)
	return event


func _mouse_motion(local: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = _screen(local)
	return event


func _touch(local: Vector2, pressed: bool, index := 0) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = _screen(local)
	return event


func _touch_drag(local: Vector2, index := 0) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = _screen(local)
	return event


func test_press_within_generous_radius_grabs_neuron() -> void:
	# 40 px from neuron 0: outside its 28 px radius, inside the 1.6x grab radius.
	_input._unhandled_input(_mouse_button(Vector2(140, 100), true))
	assert_int(_input.get_dragging_id()).is_equal(0)
	assert_int(_model.get_grabbed_id()).is_equal(0)
	assert_array(_recorder.last_args(&"grab_started")).is_equal([0])


func test_press_far_from_any_neuron_grabs_nothing() -> void:
	_input._unhandled_input(_mouse_button(Vector2(300, 300), true))
	assert_int(_input.get_dragging_id()).is_equal(PuzzleModel.NO_NEURON)
	assert_int(_recorder.count(&"grab_started")).is_equal(0)


func test_disabled_controller_ignores_pointer() -> void:
	_input.set_enabled(false)
	_input._unhandled_input(_mouse_button(Vector2(100, 100), true))
	assert_int(_model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)


func test_mouse_motion_drags_in_playfield_coordinates() -> void:
	_input._unhandled_input(_mouse_button(Vector2(100, 100), true))
	_input._unhandled_input(_mouse_motion(Vector2(300, 180)))
	assert_vector(_model.get_neuron_position(0)).is_equal(Vector2(300, 180))


func test_motion_without_grab_does_nothing() -> void:
	_input._unhandled_input(_mouse_motion(Vector2(300, 180)))
	assert_vector(_model.get_neuron_position(0)).is_equal(Vector2(100, 100))


func test_release_ends_drag_and_counts_a_move() -> void:
	_input._unhandled_input(_mouse_button(Vector2(100, 100), true))
	_input._unhandled_input(_mouse_motion(Vector2(300, 180)))
	_input._unhandled_input(_mouse_button(Vector2(300, 180), false))
	assert_int(_input.get_dragging_id()).is_equal(PuzzleModel.NO_NEURON)
	assert_int(_model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)
	assert_int(_model.get_move_count()).is_equal(1)
	assert_array(_recorder.last_args(&"grab_ended")).is_equal([0])


func test_touch_drag_flow_ignores_emulated_mouse() -> void:
	_input._unhandled_input(_touch(Vector2(100, 100), true))
	# Emulated mouse events from the same touch must not start a second grab or move it.
	_input._unhandled_input(_mouse_button(Vector2(500, 500), true))
	_input._unhandled_input(_mouse_motion(Vector2(900, 900)))
	_input._unhandled_input(_touch_drag(Vector2(300, 180)))
	assert_int(_input.get_dragging_id()).is_equal(0)
	assert_vector(_model.get_neuron_position(0)).is_equal(Vector2(300, 180))
	_input._unhandled_input(_touch(Vector2(300, 180), false))
	assert_int(_model.get_move_count()).is_equal(1)
	assert_int(_recorder.count(&"grab_started")).is_equal(1)


func test_other_touch_index_is_ignored() -> void:
	_input._unhandled_input(_touch(Vector2(100, 100), true, 0))
	_input._unhandled_input(_touch_drag(Vector2(300, 180), 1))
	_input._unhandled_input(_touch(Vector2(300, 180), false, 1))
	assert_int(_input.get_dragging_id()).is_equal(0)
	assert_vector(_model.get_neuron_position(0)).is_equal(Vector2(100, 100))


func test_focus_loss_releases_the_drag() -> void:
	_input._unhandled_input(_mouse_button(Vector2(100, 100), true))
	_input._unhandled_input(_mouse_motion(Vector2(300, 180)))
	_input._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_int(_model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)
	assert_int(_model.get_move_count()).is_equal(1)
	assert_int(_recorder.count(&"grab_ended")).is_equal(1)


func test_lost_mouse_release_is_detected() -> void:
	_input._unhandled_input(_mouse_button(Vector2(100, 100), true))
	# The grab button is not held according to Input: the release happened outside the window.
	_input._check_lost_release()
	assert_int(_input.get_dragging_id()).is_equal(PuzzleModel.NO_NEURON)


func test_disabling_mid_drag_releases() -> void:
	_input._unhandled_input(_mouse_button(Vector2(100, 100), true))
	_input.set_enabled(false)
	assert_int(_model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)
	assert_int(_recorder.count(&"grab_ended")).is_equal(1)


func test_restart_action_emits_even_when_disabled() -> void:
	_input.set_enabled(false)
	var event := InputEventAction.new()
	event.action = &"restart"
	event.pressed = true
	_input._unhandled_input(event)
	assert_int(_recorder.count(&"restart_requested")).is_equal(1)


func test_rebinding_a_new_model_drops_the_old_drag() -> void:
	_input._unhandled_input(_mouse_button(Vector2(100, 100), true))
	var fresh := PuzzleModel.from_level(LevelFactory.x_level())
	_input.bind(fresh)
	assert_int(_input.get_dragging_id()).is_equal(PuzzleModel.NO_NEURON)
	assert_int(_model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)
