extends GdUnitTestSuite
## T8.2: validation rules for toxic neurons.

const LevelFactory := preload("res://tests/model/level_factory.gd")


func _assert_has_error(errors: PackedStringArray, fragment: String) -> void:
	var found := false
	for error in errors:
		if error.contains(fragment):
			found = true
	assert_bool(found).override_failure_message(
		"Expected an error containing '%s', got %s" % [fragment, errors]).is_true()


## Receptor 0 (700, 200) reach 120, normal neuron 1 (start out of reach, solution linked),
## toxic neuron 2 (start and solution out of reach) and a tangled X (10-13) so the start is tangled.
func _level() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(700, 200), 120.0, 1),
		LevelFactory.neuron(1, Vector2(900, 200), Vector2(800, 200)),
		LevelFactory.toxic(2, Vector2(700, 500), Vector2(700, 600)),
		LevelFactory.neuron(10, Vector2(100, 700)),
		LevelFactory.neuron(11, Vector2(400, 900), Vector2(400, 700)),
		LevelFactory.neuron(12, Vector2(400, 700), Vector2(100, 900)),
		LevelFactory.neuron(13, Vector2(100, 900), Vector2(400, 900)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(10, 11), LevelFactory.edge(12, 13)]
	return LevelFactory.level(neurons, dendrites)


func test_a_valid_toxic_level_has_no_errors() -> void:
	assert_array(PuzzleModel.validate_level(_level())).is_empty()


func test_toxic_starting_inside_a_receptor_reach_is_rejected() -> void:
	var level := _level()
	level.neurons[2].position = Vector2(700, 300)
	_assert_has_error(PuzzleModel.validate_level(level), "Start layout has contamination")


func test_toxic_solution_inside_a_receptor_reach_is_rejected() -> void:
	var level := _level()
	level.neurons[2].solution_position = Vector2(700, 300)
	_assert_has_error(PuzzleModel.validate_level(level), "Solution layout has contamination")


func test_toxic_neuron_must_be_movable() -> void:
	var level := _level()
	level.neurons[2].fixed = true
	level.neurons[2].solution_position = level.neurons[2].position
	_assert_has_error(PuzzleModel.validate_level(level), "Toxic neuron 2 must be movable")


func test_toxic_solution_must_not_overlap_other_neurons() -> void:
	var level := _level()
	level.neurons[2].solution_position = Vector2(800, 200)
	_assert_has_error(PuzzleModel.validate_level(level), "Neurons 1 and 2 overlap at solution")


## Decision (documented in the feature doc): a toxic neuron in a level without receptors is a
## harmless decoy; it is allowed.
func test_a_toxic_neuron_without_receptors_is_allowed() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.toxic(0, Vector2(700, 200)),
		LevelFactory.neuron(10, Vector2(100, 700)),
		LevelFactory.neuron(11, Vector2(400, 900), Vector2(400, 700)),
		LevelFactory.neuron(12, Vector2(400, 700), Vector2(100, 900)),
		LevelFactory.neuron(13, Vector2(100, 900), Vector2(400, 900)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(10, 11), LevelFactory.edge(12, 13)]
	assert_array(PuzzleModel.validate_level(LevelFactory.level(neurons, dendrites))).is_empty()
