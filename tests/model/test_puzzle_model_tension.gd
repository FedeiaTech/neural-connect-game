extends GdUnitTestSuite
## T1.4: tension dendrites (ratio, tension_changed, edge_broke).

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")

var _recorder: SignalRecorder


func before_test() -> void:
	_recorder = SignalRecorder.new()


## Edge 0: TENSION 0-1 (rest 100, max 300, starts at length 100). Edge 1: NORMAL 2-3.
func _tension_model() -> PuzzleModel:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(200, 500)),
		LevelFactory.neuron(2, Vector2(100, 100)),
		LevelFactory.neuron(3, Vector2(300, 100)),
	]
	var dendrites: Array[DendriteData] = [
		LevelFactory.tension_edge(0, 1, 100.0, 300.0),
		LevelFactory.edge(2, 3),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	_recorder.watch(model, [&"neuron_moved", &"neuron_blocked", &"tension_changed", &"edge_broke"])
	return model


func test_initial_tension_ratio_is_zero_at_rest_length() -> void:
	var model := _tension_model()
	assert_float(model.get_tension_ratio(0)).is_equal(0.0)


func test_normal_edge_has_zero_tension_ratio() -> void:
	var model := _tension_model()
	assert_float(model.get_tension_ratio(1)).is_equal(0.0)
	assert_bool(model.is_tension_edge(1)).is_false()
	assert_bool(model.is_tension_edge(0)).is_true()


func test_stretching_emits_tension_ratio() -> void:
	var model := _tension_model()
	model.grab(1)
	model.drag_to(Vector2(300, 500))
	assert_float(model.get_tension_ratio(0)).is_equal_approx(0.5, 0.0001)
	assert_int(_recorder.count(&"tension_changed")).is_equal(1)
	var args := _recorder.last_args(&"tension_changed")
	assert_int(args[0]).is_equal(0)
	assert_float(args[1]).is_equal_approx(0.5, 0.0001)


func test_tension_not_emitted_when_ratio_unchanged() -> void:
	var model := _tension_model()
	model.grab(1)
	# Still shorter than rest length: ratio clamps to 0 and stays 0.
	model.drag_to(Vector2(180, 500))
	assert_int(_recorder.count(&"tension_changed")).is_equal(0)


func test_moving_unrelated_neuron_does_not_emit_tension() -> void:
	var model := _tension_model()
	model.grab(3)
	model.drag_to(Vector2(600, 100))
	assert_int(_recorder.count(&"tension_changed")).is_equal(0)


func test_exceeding_max_length_breaks_edge() -> void:
	var model := _tension_model()
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	assert_int(_recorder.count(&"edge_broke")).is_equal(1)
	assert_array(_recorder.last_args(&"edge_broke")).is_equal([0])
	assert_bool(model.is_broken()).is_true()
	assert_int(model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)


func test_edge_broke_via_monitor() -> void:
	var model := _tension_model()
	var monitor := monitor_signals(model, false)
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	await assert_signal(monitor).is_emitted("edge_broke", [0])


func test_exactly_max_length_does_not_break() -> void:
	var model := _tension_model()
	model.grab(1)
	model.drag_to(Vector2(400, 500))
	assert_bool(model.is_broken()).is_false()
	assert_float(model.get_tension_ratio(0)).is_equal_approx(1.0, 0.0001)


func test_broken_model_refuses_grab() -> void:
	var model := _tension_model()
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	# Nothing is grabbed and neuron 3 is free and draggable: only the broken guard refuses it.
	assert_int(model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)
	assert_bool(model.is_fixed(3)).is_false()
	assert_bool(model.grab(3)).is_false()


func test_broken_model_ignores_drag_even_with_a_grab() -> void:
	var model := _tension_model()
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	_recorder.clear()
	# White-box: force a grab past the broken grab() guard so drag_to's own broken guard is
	# the only thing that can stop the move (the no-grab guard would pass).
	model._grabbed_id = 3
	model.drag_to(Vector2(700, 700))
	assert_vector(model.get_neuron_position(3)).is_equal(Vector2(300, 100))
	assert_int(_recorder.count(&"neuron_moved")).is_equal(0)


func test_breaking_drag_that_is_also_blocked_emits_no_neuron_blocked() -> void:
	var model := _tension_model()
	model.grab(1)
	# Past the right edge of the 1000 px play area: blocked at the boundary and, being far
	# beyond max_length (300), broken in the same call.
	model.drag_to(Vector2(1100, 500))
	assert_int(_recorder.count(&"edge_broke")).is_equal(1)
	assert_int(_recorder.count(&"neuron_blocked")).is_equal(0)


func test_broken_release_does_not_count_a_move() -> void:
	var model := _tension_model()
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	model.release()
	assert_int(model.get_move_count()).is_equal(0)


func test_ratio_guards_zero_range() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(200, 500)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.tension_edge(0, 1, 300.0, 300.0)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_float(model.get_tension_ratio(0)).is_equal(0.0)
