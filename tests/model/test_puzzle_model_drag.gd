extends GdUnitTestSuite
## T1.3: grab / drag_to / release with boundary, obstacle and neuron collisions.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const RADIUS := LevelFactory.DEFAULT_RADIUS
const CONTACT_TOLERANCE := 0.05

var _recorder: SignalRecorder


func before_test() -> void:
	_recorder = SignalRecorder.new()


func _watch(model: PuzzleModel) -> PuzzleModel:
	_recorder.watch(model, [&"neuron_moved", &"neuron_blocked", &"crossings_changed"])
	return model


## Neuron 0 (draggable), neuron 1 (other), neuron 2 (fixed), no dendrites.
func _three_neuron_model(obstacles: Array[PackedVector2Array] = []) -> PuzzleModel:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(400, 500)),
		LevelFactory.neuron(2, Vector2(800, 800), null, true),
	]
	return _watch(PuzzleModel.from_level(LevelFactory.level(neurons, [], obstacles)))


func test_grab_returns_true_for_draggable_neuron() -> void:
	var model := _three_neuron_model()
	assert_bool(model.grab(0)).is_true()
	assert_int(model.get_grabbed_id()).is_equal(0)


func test_fixed_neuron_refuses_grab() -> void:
	var model := _three_neuron_model()
	assert_bool(model.grab(2)).is_false()
	assert_int(model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)


func test_unknown_neuron_refuses_grab() -> void:
	var model := _three_neuron_model()
	assert_bool(model.grab(42)).is_false()


func test_grab_refused_while_another_neuron_is_grabbed() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	assert_bool(model.grab(1)).is_false()
	assert_int(model.get_grabbed_id()).is_equal(0)


func test_pick_neuron_returns_nearest_within_radius() -> void:
	var model := _three_neuron_model()
	assert_int(model.pick_neuron(Vector2(130, 500), 40.0)).is_equal(0)
	assert_int(model.pick_neuron(Vector2(250, 500), 40.0)).is_equal(PuzzleModel.NO_NEURON)


func test_pick_neuron_can_return_fixed_neuron() -> void:
	var model := _three_neuron_model()
	assert_int(model.pick_neuron(Vector2(800, 790), 40.0)).is_equal(2)


func test_drag_without_grab_does_nothing() -> void:
	var model := _three_neuron_model()
	model.drag_to(Vector2(200, 200))
	assert_vector(model.get_neuron_position(0)).is_equal(Vector2(100, 500))
	assert_int(_recorder.count(&"neuron_moved")).is_equal(0)


func test_free_drag_moves_neuron_and_emits_moved() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	model.drag_to(Vector2(200, 200))
	assert_vector(model.get_neuron_position(0)).is_equal(Vector2(200, 200))
	assert_array(_recorder.last_args(&"neuron_moved")).is_equal([0, Vector2(200, 200)])
	assert_int(_recorder.count(&"neuron_blocked")).is_equal(0)


func test_moved_signal_via_monitor() -> void:
	var model := _three_neuron_model()
	var monitor := monitor_signals(model, false)
	model.grab(0)
	model.drag_to(Vector2(150, 450))
	await assert_signal(monitor).is_emitted("neuron_moved", [0, Vector2(150, 450)])


func test_boundary_stops_neuron_at_contact() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	model.drag_to(Vector2(-200, 500))
	var pos := model.get_neuron_position(0)
	assert_float(pos.x).is_equal_approx(RADIUS, CONTACT_TOLERANCE)
	assert_float(pos.y).is_equal_approx(500.0, CONTACT_TOLERANCE)
	assert_int(_recorder.count(&"neuron_blocked")).is_equal(1)
	assert_vector(_recorder.last_args(&"neuron_blocked")[1]).is_equal(pos)


func test_blocked_neuron_stays_grabbed_and_moves_again() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	model.drag_to(Vector2(-200, 500))
	assert_int(model.get_grabbed_id()).is_equal(0)
	model.drag_to(Vector2(200, 300))
	assert_vector(model.get_neuron_position(0)).is_equal(Vector2(200, 300))


func test_obstacle_stops_neuron_at_contact() -> void:
	var obstacles: Array[PackedVector2Array] = [LevelFactory.rect(Vector2(200, 600), Vector2(100, 300))]
	var model := _three_neuron_model(obstacles)
	model.grab(0)
	# Straight down-right into the obstacle's left face (x = 200).
	model.drag_to(Vector2(250, 700))
	model.drag_to(Vector2(100, 700))
	model.drag_to(Vector2(250, 700))
	var pos := model.get_neuron_position(0)
	assert_float(pos.x).is_equal_approx(200.0 - RADIUS, CONTACT_TOLERANCE)
	assert_float(pos.y).is_equal_approx(700.0, CONTACT_TOLERANCE)
	assert_int(_recorder.count(&"neuron_blocked")).is_greater(0)


func test_obstacle_cannot_be_tunneled_through() -> void:
	var obstacles: Array[PackedVector2Array] = [LevelFactory.rect(Vector2(200, 400), Vector2(20, 200))]
	var model := _three_neuron_model(obstacles)
	model.grab(0)
	model.drag_to(Vector2(350, 450))
	assert_float(model.get_neuron_position(0).x).is_less_equal(200.0 - RADIUS + CONTACT_TOLERANCE)


func test_other_neuron_stops_drag_at_contact() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	model.drag_to(Vector2(400, 500))
	var pos := model.get_neuron_position(0)
	assert_float(pos.x).is_equal_approx(400.0 - 2.0 * RADIUS, CONTACT_TOLERANCE)
	assert_float(pos.y).is_equal_approx(500.0, CONTACT_TOLERANCE)
	assert_vector(model.get_neuron_position(1)).is_equal(Vector2(400, 500))
	assert_int(_recorder.count(&"neuron_blocked")).is_equal(1)


func test_neuron_cannot_jump_over_another_neuron() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	model.drag_to(Vector2(700, 500))
	assert_float(model.get_neuron_position(0).x).is_equal_approx(400.0 - 2.0 * RADIUS, CONTACT_TOLERANCE)


func test_neuron_blocked_by_neuron_moves_again_toward_free_target() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	model.drag_to(Vector2(400, 500))
	model.drag_to(Vector2(300, 800))
	assert_vector(model.get_neuron_position(0)).is_equal(Vector2(300, 800))


func test_fixed_neuron_blocks_other_neurons() -> void:
	var model := _three_neuron_model()
	model.grab(1)
	model.drag_to(Vector2(800, 800))
	assert_float(model.get_neuron_position(1).distance_to(Vector2(800, 800))).is_equal_approx(
		2.0 * RADIUS, CONTACT_TOLERANCE)


func test_blocked_at_start_emits_blocked_but_not_moved() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	model.drag_to(Vector2(-200, 500))
	_recorder.clear()
	model.drag_to(Vector2(-300, 500))
	assert_int(_recorder.count(&"neuron_moved")).is_equal(0)
	assert_int(_recorder.count(&"neuron_blocked")).is_equal(1)


func test_release_clears_grab() -> void:
	var model := _three_neuron_model()
	model.grab(0)
	model.release()
	assert_int(model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)
	model.drag_to(Vector2(200, 200))
	assert_vector(model.get_neuron_position(0)).is_equal(Vector2(100, 500))


func test_neuron_passes_over_dendrites_freely() -> void:
	# Drag neuron 3 straight across edge 0-1 (a horizontal line at y = 500).
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(900, 500)),
		LevelFactory.neuron(2, Vector2(500, 100)),
		LevelFactory.neuron(3, Vector2(500, 300)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(0, 1), LevelFactory.edge(2, 3)]
	var model := _watch(PuzzleModel.from_level(LevelFactory.level(neurons, dendrites)))
	model.grab(3)
	model.drag_to(Vector2(500, 800))
	assert_vector(model.get_neuron_position(3)).is_equal(Vector2(500, 800))
	assert_int(_recorder.count(&"neuron_blocked")).is_equal(0)


func test_crossings_changed_emitted_only_when_set_changes() -> void:
	var model := _watch(PuzzleModel.from_level(LevelFactory.x_level()))
	model.grab(3)
	# Still crossing: no emission.
	model.drag_to(Vector2(120, 520))
	assert_int(_recorder.count(&"crossings_changed")).is_equal(0)
	# Untangle: neuron 3 goes to the top-right, edge 2-3 becomes horizontal at y = 100.
	model.drag_to(Vector2(900, 100))
	assert_int(_recorder.count(&"crossings_changed")).is_equal(1)
	assert_array(_recorder.last_args(&"crossings_changed")).is_equal([[], []])
	# Tangle again.
	model.drag_to(Vector2(120, 520))
	assert_int(_recorder.count(&"crossings_changed")).is_equal(2)
	assert_array(_recorder.last_args(&"crossings_changed")).is_equal([[0, 1], [0, 1, 2, 3]])
