extends GdUnitTestSuite
## T8.3: validation rules for diseased dendrites. The reference solution must stretch each one
## beyond max_length (that is how it breaks) while the start layout keeps it within max_length.

const LevelFactory := preload("res://tests/model/level_factory.gd")


func _assert_has_error(errors: PackedStringArray, fragment: String) -> void:
	var found := false
	for error in errors:
		if error.contains(fragment):
			found = true
	assert_bool(found).override_failure_message(
		"Expected an error containing '%s', got %s" % [fragment, errors]).is_true()


## Tangled X (10-13) plus neurons 20-21 joined by a diseased dendrite (rest 100, max 300):
## start length 150, solution length 350.
func _level() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(10, Vector2(100, 700)),
		LevelFactory.neuron(11, Vector2(400, 900), Vector2(400, 700)),
		LevelFactory.neuron(12, Vector2(400, 700), Vector2(100, 900)),
		LevelFactory.neuron(13, Vector2(100, 900), Vector2(400, 900)),
		LevelFactory.neuron(20, Vector2(100, 300)),
		LevelFactory.neuron(21, Vector2(250, 300), Vector2(450, 300)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(10, 11), LevelFactory.edge(12, 13),
		LevelFactory.diseased_edge(20, 21, 100.0, 300.0)]
	return LevelFactory.level(neurons, dendrites)


func test_a_valid_diseased_level_has_no_errors() -> void:
	assert_array(PuzzleModel.validate_level(_level())).is_empty()


func test_solution_must_stretch_the_dendrite_past_max_length() -> void:
	var level := _level()
	level.neurons[5].solution_position = Vector2(350, 300)
	_assert_has_error(PuzzleModel.validate_level(level), "Diseased dendrite 2 cannot break in the solution")


func test_start_must_be_within_max_length() -> void:
	var level := _level()
	level.neurons[5].position = Vector2(450, 300)
	_assert_has_error(PuzzleModel.validate_level(level), "Diseased dendrite 2 exceeds max_length at start")


func test_max_length_must_exceed_rest_length() -> void:
	var level := _level()
	level.dendrites[2].max_length = 100.0
	_assert_has_error(PuzzleModel.validate_level(level), "Diseased dendrite 2: max_length must be greater than rest_length")


func test_other_tension_dendrites_must_stay_within_their_limits() -> void:
	var level := _level()
	# A tension dendrite whose solution length exceeds its own limit is still rejected.
	level.dendrites.append(LevelFactory.tension_edge(11, 12, 100.0, 200.0))
	level.neurons[1].solution_position = Vector2(400, 700)
	level.neurons[2].solution_position = Vector2(100, 900)
	_assert_has_error(PuzzleModel.validate_level(level), "Tension dendrite 3 exceeds max_length at solution")


func test_a_level_with_only_a_diseased_dendrite_may_start_without_crossings() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 300)),
		LevelFactory.neuron(1, Vector2(250, 300), Vector2(450, 300)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(0, 1, 100.0, 300.0)]
	assert_array(PuzzleModel.validate_level(LevelFactory.level(neurons, dendrites))).is_empty()


func test_solution_crossings_of_a_broken_dendrite_do_not_count() -> void:
	var level := _level()
	# In the solution the stretched diseased dendrite runs through dendrite 10-11 (y = 700): it is
	# broken there, so it does not count as a crossing.
	level.neurons[4].solution_position = Vector2(250, 500)
	level.neurons[5].solution_position = Vector2(250, 850)
	var errors := PuzzleModel.validate_level(level)
	assert_array(Array(errors).filter(func(e: String) -> bool: return e.contains("crossing"))).is_empty()
