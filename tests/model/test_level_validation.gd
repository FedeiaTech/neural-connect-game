extends GdUnitTestSuite
## T1.6: PuzzleModel.validate_level reports every authoring error class.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const AREA := Vector2(1000, 1000)


func _assert_has_error(errors: PackedStringArray, fragment: String) -> void:
	var found := false
	for error in errors:
		if error.contains(fragment):
			found = true
	assert_bool(found).override_failure_message(
		"Expected an error containing '%s', got %s" % [fragment, errors]).is_true()


func _two_neuron_level(p0: Vector2, p1: Vector2, dendrite: DendriteData = null) -> LevelData:
	var neurons: Array[NeuronData] = [LevelFactory.neuron(0, p0), LevelFactory.neuron(1, p1)]
	var dendrites: Array[DendriteData] = []
	if dendrite != null:
		dendrites.append(dendrite)
	return LevelFactory.level(neurons, dendrites)


func test_valid_four_neuron_level_has_no_errors() -> void:
	assert_array(PuzzleModel.validate_level(LevelFactory.x_level())).is_empty()


func test_empty_play_area() -> void:
	var level := LevelFactory.x_level()
	level.play_area = PackedVector2Array()
	_assert_has_error(PuzzleModel.validate_level(level), "Play area")


func test_non_positive_radius() -> void:
	var level := LevelFactory.x_level()
	level.neuron_radius = 0.0
	_assert_has_error(PuzzleModel.validate_level(level), "radius")


func test_duplicate_neuron_ids() -> void:
	var level := LevelFactory.x_level()
	level.neurons[3].id = 2
	_assert_has_error(PuzzleModel.validate_level(level), "Duplicate neuron id 2")


func test_dendrite_references_missing_neuron() -> void:
	var level := LevelFactory.x_level()
	level.dendrites.append(LevelFactory.edge(0, 9))
	_assert_has_error(PuzzleModel.validate_level(level), "missing neuron 9")


func test_self_loop() -> void:
	var level := LevelFactory.x_level()
	level.dendrites.append(LevelFactory.edge(1, 1))
	_assert_has_error(PuzzleModel.validate_level(level), "self-loop")


func test_duplicate_edge_in_either_direction() -> void:
	var level := LevelFactory.x_level()
	level.dendrites.append(LevelFactory.edge(1, 0))
	_assert_has_error(PuzzleModel.validate_level(level), "duplicates dendrite 0")


func test_null_entries() -> void:
	var level := LevelFactory.x_level()
	level.neurons.append(null)
	level.dendrites.append(null)
	var errors := PuzzleModel.validate_level(level)
	_assert_has_error(errors, "Neuron entry 4 is null")
	_assert_has_error(errors, "Dendrite entry 2 is null")


func test_solution_with_crossings() -> void:
	var level := LevelFactory.x_level()
	# Make the solution an X too: swap the solution positions of neurons 1 and 3.
	level.neurons[1].solution_position = Vector2(500, 500)
	level.neurons[3].solution_position = Vector2(500, 100)
	_assert_has_error(PuzzleModel.validate_level(level), "Solution layout has 1 crossing")


func test_start_position_outside_play_area() -> void:
	var level := LevelFactory.x_level()
	level.neurons[0].position = Vector2(10, 10)
	_assert_has_error(PuzzleModel.validate_level(level), "Neuron 0 start position")


func test_solution_position_inside_obstacle() -> void:
	var level := LevelFactory.x_level()
	level.obstacles = [LevelFactory.rect(Vector2(450, 50), Vector2(100, 100))]
	_assert_has_error(PuzzleModel.validate_level(level), "Neuron 1 solution position")


func test_overlapping_start_positions() -> void:
	var level := _two_neuron_level(Vector2(300, 300), Vector2(320, 300))
	_assert_has_error(PuzzleModel.validate_level(level), "Neurons 0 and 1 overlap at start")


func test_overlapping_solution_positions() -> void:
	var level := _two_neuron_level(Vector2(300, 300), Vector2(600, 300))
	level.neurons[1].solution_position = Vector2(310, 300)
	_assert_has_error(PuzzleModel.validate_level(level), "Neurons 0 and 1 overlap at solution")


func test_fixed_neuron_must_not_move_in_solution() -> void:
	var level := LevelFactory.x_level()
	level.neurons[1].fixed = true
	_assert_has_error(PuzzleModel.validate_level(level), "Fixed neuron 1")


func test_tension_edge_too_long_at_start() -> void:
	var level := _two_neuron_level(Vector2(100, 500), Vector2(600, 500),
		LevelFactory.tension_edge(0, 1, 100.0, 300.0))
	level.neurons[1].solution_position = Vector2(300, 500)
	var errors := PuzzleModel.validate_level(level)
	_assert_has_error(errors, "Tension dendrite 0 exceeds max_length at start")
	assert_int(errors.size()).is_equal(1)


func test_tension_edge_too_long_in_solution() -> void:
	var level := _two_neuron_level(Vector2(100, 500), Vector2(300, 500),
		LevelFactory.tension_edge(0, 1, 100.0, 300.0))
	level.neurons[1].solution_position = Vector2(700, 500)
	_assert_has_error(PuzzleModel.validate_level(level), "Tension dendrite 0 exceeds max_length at solution")


func test_tension_max_not_greater_than_rest() -> void:
	var level := _two_neuron_level(Vector2(100, 500), Vector2(300, 500),
		LevelFactory.tension_edge(0, 1, 300.0, 300.0))
	_assert_has_error(PuzzleModel.validate_level(level), "max_length must be greater than rest_length")


## Guards every authored mission: each LevelData under res://data/levels must validate.
func test_every_authored_level_is_valid() -> void:
	for path in _find_level_files("res://data/levels"):
		var level := load(path) as LevelData
		assert_object(level).override_failure_message("%s is not a LevelData" % path).is_not_null()
		if level != null:
			var errors := PuzzleModel.validate_level(level)
			assert_array(errors).override_failure_message("%s: %s" % [path, errors]).is_empty()


func _find_level_files(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			found.append(dir_path.path_join(file_name))
	for sub_dir in dir.get_directories():
		found.append_array(_find_level_files(dir_path.path_join(sub_dir)))
	return found


func test_validation_does_not_mutate_level() -> void:
	var level := LevelFactory.x_level()
	PuzzleModel.validate_level(level)
	assert_vector(level.neurons[1].position).is_equal(Vector2(500, 500))
	assert_int(level.dendrites.size()).is_equal(2)
