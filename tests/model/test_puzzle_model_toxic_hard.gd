extends GdUnitTestSuite
## T8.6: the HARD toxic rule (boss missions, LevelData.hard_toxic). A contamination link that
## forms during a drag overloads the toxic neuron: toxic_overloaded, then neuron_destroyed, the
## destroy cause is TOXIC and the model ignores input afterwards. The SOFT rule (default) is
## untouched.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const RADIUS := 28.0
const REACH := 120.0


## Receptor 0 (500, 500) reach 120, normal neuron 1 (linked at build), toxic neuron 2 (500, 750).
func _level(hard: bool) -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), REACH, 1),
		LevelFactory.neuron(1, Vector2(610, 500)),
		LevelFactory.toxic(2, Vector2(500, 750)),
	]
	var dendrites: Array[DendriteData] = []
	var level := LevelFactory.level(neurons, dendrites)
	level.hard_toxic = hard
	return level


func test_level_data_defaults_to_the_soft_rule_and_no_boss() -> void:
	var data := LevelData.new()
	assert_bool(data.hard_toxic).is_false()
	assert_bool(data.is_boss).is_false()


func test_hard_toxic_overloads_when_a_contamination_link_forms() -> void:
	var model := PuzzleModel.from_level(_level(true))
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"toxic_overloaded", &"neuron_destroyed", &"contamination_formed"])
	assert_bool(model.is_hard_toxic()).is_true()
	model.grab(2)
	model.drag_to(Vector2(500, 700))
	assert_bool(model.is_destroyed()).is_false()
	model.drag_to(Vector2(500, 500.0 + RADIUS + REACH - 1.0))
	assert_bool(model.is_destroyed()).is_true()
	assert_int(model.get_destroyed_id()).is_equal(2)
	assert_int(model.get_destroy_cause()).is_equal(PuzzleModel.DestroyCause.TOXIC)
	assert_bool(model.is_lost()).is_true()
	assert_int(recorder.count(&"toxic_overloaded")).is_equal(1)
	assert_array(recorder.last_args(&"toxic_overloaded")).is_equal([2, 0])
	assert_int(recorder.count(&"neuron_destroyed")).is_equal(1)
	assert_int(recorder.args_of(&"neuron_destroyed")[0][0]).is_equal(2)


func test_the_contact_point_is_on_the_rim_facing_the_receptor() -> void:
	var model := PuzzleModel.from_level(_level(true))
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"neuron_destroyed"])
	model.grab(2)
	model.drag_to(Vector2(500, 600))
	var contact: Vector2 = recorder.last_args(&"neuron_destroyed")[1]
	var center := model.get_neuron_position(2)
	assert_float(contact.distance_to(center)).is_equal_approx(RADIUS, 0.01)
	assert_float(contact.distance_to(Vector2(500, 500))).is_less(center.distance_to(Vector2(500, 500)))


func test_a_destroyed_model_ignores_further_input_and_never_solves() -> void:
	var model := PuzzleModel.from_level(_level(true))
	model.grab(2)
	model.drag_to(Vector2(500, 600))
	assert_bool(model.is_destroyed()).is_true()
	assert_int(model.get_grabbed_id()).is_equal(PuzzleModel.NO_NEURON)
	assert_bool(model.grab(1)).is_false()
	model.release()
	assert_bool(model.is_solved()).is_false()


func test_soft_rule_only_warns() -> void:
	var model := PuzzleModel.from_level(_level(false))
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"toxic_overloaded", &"neuron_destroyed"])
	assert_bool(model.is_hard_toxic()).is_false()
	model.grab(2)
	model.drag_to(Vector2(500, 600))
	assert_bool(model.is_contaminated()).is_true()
	assert_bool(model.is_destroyed()).is_false()
	assert_int(model.get_destroy_cause()).is_equal(PuzzleModel.DestroyCause.NONE)
	assert_int(recorder.count(&"toxic_overloaded")).is_equal(0)


func test_a_lethal_wall_keeps_its_own_cause() -> void:
	var neurons: Array[NeuronData] = [LevelFactory.neuron(0, Vector2(900, 500))]
	var level := LevelFactory.level(neurons, [])
	level.lethal_edges = PackedInt32Array([1])
	var model := PuzzleModel.from_level(level)
	model.grab(0)
	model.drag_to(Vector2(1100, 500))
	assert_bool(model.is_destroyed()).is_true()
	assert_int(model.get_destroy_cause()).is_equal(PuzzleModel.DestroyCause.LETHAL_WALL)


func test_hard_toxic_start_inside_a_reach_is_still_invalid() -> void:
	var level := _level(true)
	level.neurons[2].position = Vector2(500, 600)
	level.neurons[2].solution_position = Vector2(500, 750)
	assert_array(Array(PuzzleModel.validate_level(level))).is_not_empty()


func test_a_clean_route_outside_every_reach_never_overloads() -> void:
	var model := PuzzleModel.from_level(_level(true))
	model.grab(2)
	model.drag_to(Vector2(800, 750))
	model.release()
	assert_bool(model.is_destroyed()).is_false()
