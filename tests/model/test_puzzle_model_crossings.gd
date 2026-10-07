extends GdUnitTestSuite
## T1.2: crossing detection on the pure model.

const LevelFactory := preload("res://tests/model/level_factory.gd")


func test_from_level_copies_positions_and_edges() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	assert_array(model.get_neuron_ids()).is_equal([0, 1, 2, 3])
	assert_int(model.get_edge_count()).is_equal(2)
	assert_vector(model.get_neuron_position(1)).is_equal(Vector2(500, 500))
	assert_that(model.get_edge_endpoints(1)).is_equal(Vector2i(2, 3))
	assert_float(model.get_neuron_radius()).is_equal(28.0)


func test_from_level_with_solution_uses_solution_positions() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level(), true)
	assert_vector(model.get_neuron_position(1)).is_equal(Vector2(500, 100))


func test_from_level_does_not_keep_a_reference_to_resource_arrays() -> void:
	var level := LevelFactory.x_level()
	var model := PuzzleModel.from_level(level)
	level.neurons[1].position = Vector2(900, 900)
	assert_vector(model.get_neuron_position(1)).is_equal(Vector2(500, 500))


func test_x_layout_has_one_crossing() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	assert_array(model.get_crossing_edges()).is_equal([0, 1])
	assert_array(model.get_crossing_neurons()).is_equal([0, 1, 2, 3])
	assert_int(model.get_crossing_count()).is_equal(1)


func test_solution_layout_has_no_crossings() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level(), true)
	assert_array(model.get_crossing_edges()).is_empty()
	assert_int(model.get_crossing_count()).is_equal(0)


func test_edges_sharing_a_neuron_never_cross() -> void:
	# A fan from neuron 0 plus a triangle: every pair shares a neuron.
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(500, 500)),
		LevelFactory.neuron(1, Vector2(200, 200)),
		LevelFactory.neuron(2, Vector2(800, 200)),
	]
	var dendrites: Array[DendriteData] = [
		LevelFactory.edge(0, 1), LevelFactory.edge(1, 2), LevelFactory.edge(2, 0),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_int(model.get_crossing_count()).is_equal(0)


func test_collinear_overlap_counts_as_crossing() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 100)),
		LevelFactory.neuron(1, Vector2(500, 100)),
		LevelFactory.neuron(2, Vector2(300, 100)),
		LevelFactory.neuron(3, Vector2(700, 100)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(0, 1), LevelFactory.edge(2, 3)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_array(model.get_crossing_edges()).is_equal([0, 1])


func test_compute_crossings_counts_each_pair_once() -> void:
	# Edge 0 is crossed by edges 1 and 2 (two pairs, three edges).
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(900, 500)),
		LevelFactory.neuron(2, Vector2(300, 100)),
		LevelFactory.neuron(3, Vector2(300, 900)),
		LevelFactory.neuron(4, Vector2(600, 100)),
		LevelFactory.neuron(5, Vector2(600, 900)),
	]
	var dendrites: Array[DendriteData] = [
		LevelFactory.edge(0, 1), LevelFactory.edge(2, 3), LevelFactory.edge(4, 5),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_int(model.get_crossing_count()).is_equal(2)
	assert_array(model.compute_crossings()).is_equal([0, 1, 2])
	assert_array(model.get_crossing_neurons()).is_equal([0, 1, 2, 3, 4, 5])
