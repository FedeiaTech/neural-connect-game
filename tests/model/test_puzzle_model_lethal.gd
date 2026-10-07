extends GdUnitTestSuite
## T7.2: lethal walls. Touching a lethal play-area edge or lethal obstacle destroys the neuron
## (the level is lost); non-lethal geometry keeps blocking as before.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const RADIUS := 28.0
## Square island 600..700 x 400..600.
const ISLAND := [Vector2(600, 400), Vector2(700, 400), Vector2(700, 600), Vector2(600, 600)]


## Neuron 0 at (500, 500) plus an X tangle (neurons 10-13) far from the walls. Play area
## 0..1000; edge i of the play area goes from point i to point i + 1 (edge 1 = right side x = 1000).
func _level(lethal_edges: Array = [], obstacle := false, lethal_obstacle := false) -> LevelData:
	var neurons: Array[NeuronData] = [LevelFactory.neuron(0, Vector2(500, 500))]
	var dendrites: Array[DendriteData] = []
	neurons.append(LevelFactory.neuron(10, Vector2(100, 700), Vector2(100, 700)))
	neurons.append(LevelFactory.neuron(11, Vector2(400, 900), Vector2(400, 700)))
	neurons.append(LevelFactory.neuron(12, Vector2(400, 700), Vector2(100, 900)))
	neurons.append(LevelFactory.neuron(13, Vector2(100, 900), Vector2(400, 900)))
	dendrites.append(LevelFactory.edge(10, 11))
	dendrites.append(LevelFactory.edge(12, 13))
	var obstacles: Array[PackedVector2Array] = []
	if obstacle:
		obstacles.append(PackedVector2Array(ISLAND))
	var level := LevelFactory.level(neurons, dendrites, obstacles)
	level.lethal_edges = PackedInt32Array(lethal_edges)
	if lethal_obstacle:
		level.lethal_obstacles = PackedInt32Array([0])
	return level


func test_level_data_defaults_have_no_lethal_geometry() -> void:
	var level := LevelData.new()
	assert_int(level.lethal_edges.size()).is_equal(0)
	assert_int(level.lethal_obstacles.size()).is_equal(0)
	var model := PuzzleModel.from_level(_level())
	assert_bool(model.has_lethal_geometry()).is_false()
	assert_float(model.get_hazard_proximity(0)).is_equal(0.0)


func test_lethal_segments_are_exposed_in_pairs() -> void:
	var model := PuzzleModel.from_level(_level([1], true, true))
	var segments := model.get_lethal_segments()
	# Edge 1 plus the 4 sides of the island.
	assert_int(segments.size()).is_equal(10)
	assert_vector(segments[0]).is_equal(Vector2(1000, 0))
	assert_vector(segments[1]).is_equal(Vector2(1000, 1000))
	assert_bool(model.is_lethal_edge(1)).is_true()
	assert_bool(model.is_lethal_edge(0)).is_false()
	assert_bool(model.is_lethal_obstacle(0)).is_true()


func test_touching_a_lethal_edge_destroys_the_neuron_at_contact() -> void:
	var model := PuzzleModel.from_level(_level([1]))
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"neuron_destroyed", &"neuron_blocked"])
	model.grab(0)
	model.drag_to(Vector2(1200, 500))
	assert_float(model.get_neuron_position(0).x).is_equal_approx(1000.0 - RADIUS, 0.05)
	assert_int(recorder.count(&"neuron_destroyed")).is_equal(1)
	assert_int(recorder.count(&"neuron_blocked")).is_equal(0)
	var args := recorder.last_args(&"neuron_destroyed")
	assert_int(args[0]).is_equal(0)
	assert_vector(args[1]).is_equal_approx(Vector2(1000, 500), Vector2(0.05, 0.05))
	assert_bool(model.is_destroyed()).is_true()
	assert_int(model.get_destroyed_id()).is_equal(0)
	assert_bool(model.is_lost()).is_true()
	assert_bool(model.is_broken()).is_false()
	assert_int(model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)


func test_destroyed_model_refuses_input() -> void:
	var model := PuzzleModel.from_level(_level([1]))
	model.grab(0)
	model.drag_to(Vector2(1200, 500))
	var stopped := model.get_neuron_position(0)
	assert_bool(model.grab(0)).is_false()
	assert_bool(model.grab(11)).is_false()
	model.drag_to(Vector2(300, 300))
	model.release()
	assert_vector(model.get_neuron_position(0)).is_equal(stopped)
	assert_bool(model.is_solved()).is_false()


func test_non_lethal_edges_keep_blocking() -> void:
	var model := PuzzleModel.from_level(_level([1]))
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"neuron_destroyed", &"neuron_blocked"])
	model.grab(0)
	model.drag_to(Vector2(-200, 500))
	assert_float(model.get_neuron_position(0).x).is_equal_approx(RADIUS, 0.05)
	assert_int(recorder.count(&"neuron_blocked")).is_equal(1)
	assert_int(recorder.count(&"neuron_destroyed")).is_equal(0)
	assert_bool(model.is_lost()).is_false()


func test_touching_a_lethal_obstacle_destroys_the_neuron() -> void:
	var model := PuzzleModel.from_level(_level([], true, true))
	model.grab(0)
	model.drag_to(Vector2(800, 500))
	assert_bool(model.is_destroyed()).is_true()
	assert_float(model.get_neuron_position(0).x).is_equal_approx(600.0 - RADIUS, 0.05)


func test_plain_obstacle_still_only_blocks() -> void:
	var model := PuzzleModel.from_level(_level([], true, false))
	model.grab(0)
	model.drag_to(Vector2(800, 500))
	assert_bool(model.is_destroyed()).is_false()
	assert_float(model.get_neuron_position(0).x).is_equal_approx(600.0 - RADIUS, 0.05)


func test_neuron_blocking_first_prevents_the_lethal_contact() -> void:
	# Neuron 1 sits between neuron 0 and the lethal right edge.
	var level := _level([1])
	level.neurons.append(LevelFactory.neuron(1, Vector2(800, 500)))
	var model := PuzzleModel.from_level(level)
	model.grab(0)
	model.drag_to(Vector2(1200, 500))
	assert_bool(model.is_destroyed()).is_false()
	assert_float(model.get_neuron_position(0).x).is_equal_approx(800.0 - 2.0 * RADIUS, 0.05)


func test_hazard_proximity_rises_within_the_warning_distance() -> void:
	var model := PuzzleModel.from_level(_level([1]))
	var warning := PuzzleModel.HAZARD_WARNING_RADII * RADIUS
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"hazard_proximity_changed"])
	assert_float(model.get_hazard_proximity(0)).is_equal(0.0)
	model.grab(0)
	# Surface gap = warning / 2 -> proximity 0.5.
	model.drag_to(Vector2(1000.0 - RADIUS - warning * 0.5, 500))
	assert_float(model.get_hazard_proximity(0)).is_equal_approx(0.5, 0.001)
	assert_int(recorder.count(&"hazard_proximity_changed")).is_equal(1)
	assert_array(recorder.last_args(&"hazard_proximity_changed")).is_equal([0, model.get_hazard_proximity(0)])
	# Back out of range: one more notification with 0.
	model.drag_to(Vector2(500, 500))
	assert_int(recorder.count(&"hazard_proximity_changed")).is_equal(2)
	assert_float(recorder.last_args(&"hazard_proximity_changed")[1]).is_equal(0.0)
	model.drag_to(Vector2(480, 500))
	assert_int(recorder.count(&"hazard_proximity_changed")).is_equal(2)


func test_hazard_proximity_is_one_at_contact() -> void:
	var model := PuzzleModel.from_level(_level([1]))
	model.grab(0)
	model.drag_to(Vector2(1200, 500))
	assert_float(model.get_hazard_proximity(0)).is_equal_approx(1.0, 0.01)


func test_hazard_proximity_helper() -> void:
	assert_float(PuzzleModel.proximity_for_gap(0.0, 56.0)).is_equal(1.0)
	assert_float(PuzzleModel.proximity_for_gap(56.0, 56.0)).is_equal(0.0)
	assert_float(PuzzleModel.proximity_for_gap(14.0, 56.0)).is_equal_approx(0.75, 0.0001)
	assert_float(PuzzleModel.proximity_for_gap(INF, 56.0)).is_equal(0.0)


# --- Validation -------------------------------------------------------------------

func _assert_has_error(errors: PackedStringArray, fragment: String) -> void:
	var found := false
	for error in errors:
		if error.contains(fragment):
			found = true
	assert_bool(found).override_failure_message(
		"Expected an error containing '%s', got %s" % [fragment, errors]).is_true()


func test_valid_lethal_level_has_no_errors() -> void:
	assert_array(PuzzleModel.validate_level(_level([1], true, true))).is_empty()


func test_lethal_indices_must_exist() -> void:
	_assert_has_error(PuzzleModel.validate_level(_level([4])), "Lethal edge 4")
	var level := _level([], false, true)
	_assert_has_error(PuzzleModel.validate_level(level), "Lethal obstacle 0")


func test_start_too_close_to_a_lethal_wall() -> void:
	var level := _level([1])
	level.neurons[0].position = Vector2(1000.0 - RADIUS - 5.0, 500)
	level.neurons[0].solution_position = Vector2(500, 500)
	_assert_has_error(PuzzleModel.validate_level(level), "Neuron 0 start position is too close to a lethal wall")


func test_solution_too_close_to_a_lethal_obstacle() -> void:
	var level := _level([], true, true)
	level.neurons[0].solution_position = Vector2(600.0 - RADIUS - 5.0, 500)
	_assert_has_error(PuzzleModel.validate_level(level), "Neuron 0 solution position is too close to a lethal wall")
