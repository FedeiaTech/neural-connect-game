extends GdUnitTestSuite
## T1.1: LevelData, NeuronData and DendriteData resources.

const LevelFactory := preload("res://tests/model/level_factory.gd")


func test_neuron_data_defaults() -> void:
	var neuron := NeuronData.new()
	assert_int(neuron.id).is_equal(0)
	assert_vector(neuron.position).is_equal(Vector2.ZERO)
	assert_vector(neuron.solution_position).is_equal(Vector2.ZERO)
	assert_bool(neuron.fixed).is_false()


func test_dendrite_data_defaults_to_normal_kind() -> void:
	var dendrite := DendriteData.new()
	assert_int(dendrite.kind).is_equal(DendriteData.Kind.NORMAL)
	assert_bool(dendrite.is_tension()).is_false()


func test_tension_dendrite_reports_tension() -> void:
	var dendrite := LevelFactory.tension_edge(0, 1, 100.0, 300.0)
	assert_bool(dendrite.is_tension()).is_true()
	assert_float(dendrite.rest_length).is_equal(100.0)
	assert_float(dendrite.max_length).is_equal(300.0)


func test_level_data_defaults() -> void:
	var level := LevelData.new()
	assert_float(level.neuron_radius).is_equal(28.0)
	assert_bool(level.show_crossing_feedback).is_true()
	assert_str(level.story_text).is_empty()
	assert_array(level.neurons).is_empty()
	assert_array(level.dendrites).is_empty()
	assert_array(level.obstacles).is_empty()


func test_level_data_holds_typed_collections() -> void:
	var level := LevelFactory.x_level()
	assert_int(level.neurons.size()).is_equal(4)
	assert_int(level.dendrites.size()).is_equal(2)
	assert_int(level.play_area.size()).is_equal(4)
	assert_object(level.neurons[1]).is_instanceof(NeuronData)
	assert_object(level.dendrites[0]).is_instanceof(DendriteData)


func test_level_data_find_neuron_by_id() -> void:
	var level := LevelFactory.x_level()
	assert_vector(level.find_neuron(2).position).is_equal(Vector2(500, 100))
	assert_object(level.find_neuron(99)).is_null()


func test_level_data_neuron_ids() -> void:
	var level := LevelFactory.x_level()
	assert_array(level.get_neuron_ids()).is_equal([0, 1, 2, 3])
