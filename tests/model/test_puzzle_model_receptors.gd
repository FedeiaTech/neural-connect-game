extends GdUnitTestSuite
## T7.3: receptor neurons (immovable) form dynamic links to movable neurons that come within
## reach (center distance - radius <= reach), closest first, up to required_links; a link breaks
## when its neuron leaves reach. Links count as dendrites for crossings; the win also needs every
## receptor fully linked.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const RADIUS := 28.0
const REACH := 120.0


static func receptor(id: int, position: Vector2, reach := REACH, required := 1) -> NeuronData:
	var data := LevelFactory.neuron(id, position)
	data.kind = NeuronData.Kind.RECEPTOR
	data.reach = reach
	data.required_links = required
	return data


## Receptor 0 at (500, 500). Neuron 1 at (800, 500) (out of reach), neuron 2 at (200, 200).
## Static edge 1-2 only. No crossings at start.
func _level(required := 1) -> LevelData:
	var neurons: Array[NeuronData] = [
		receptor(0, Vector2(500, 500), REACH, required),
		LevelFactory.neuron(1, Vector2(800, 500)),
		LevelFactory.neuron(2, Vector2(200, 200)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(1, 2)]
	return LevelFactory.level(neurons, dendrites)


func test_neuron_data_defaults_to_a_normal_neuron() -> void:
	var data := NeuronData.new()
	assert_int(data.kind).is_equal(NeuronData.Kind.NORMAL)
	assert_bool(data.is_receptor()).is_false()
	assert_int(data.required_links).is_equal(1)


func test_receptor_is_immovable() -> void:
	var model := PuzzleModel.from_level(_level())
	assert_bool(model.is_receptor(0)).is_true()
	assert_bool(model.is_fixed(0)).is_true()
	assert_bool(model.grab(0)).is_false()
	assert_float(model.get_receptor_reach(0)).is_equal(REACH)
	assert_int(model.get_required_links(0)).is_equal(1)


func test_link_forms_when_a_neuron_enters_reach() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"link_formed"])
	assert_int(model.get_link_count(0)).is_equal(0)
	model.grab(1)
	# Center distance - radius = reach + 1: just outside; then reach - 1: inside.
	model.drag_to(Vector2(500.0 + RADIUS + REACH + 1.0, 500))
	assert_int(model.get_link_count(0)).is_equal(0)
	model.drag_to(Vector2(500.0 + RADIUS + REACH - 1.0, 500))
	assert_array(model.get_links(0)).is_equal([1])
	assert_int(recorder.count(&"link_formed")).is_equal(1)
	assert_array(recorder.last_args(&"link_formed")).is_equal([0, 1])
	assert_bool(model.is_receptor_satisfied(0)).is_true()


func test_link_breaks_when_the_neuron_leaves_reach() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"link_broken"])
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_int(model.get_link_count(0)).is_equal(1)
	model.drag_to(Vector2(800, 500))
	assert_int(model.get_link_count(0)).is_equal(0)
	assert_array(recorder.last_args(&"link_broken")).is_equal([0, 1])
	assert_bool(model.is_lost()).is_false()


func test_strain_ratio_approaches_one_at_the_reach_limit() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"link_strain_changed"])
	model.grab(1)
	model.drag_to(Vector2(500.0 + RADIUS + REACH * 0.5, 500))
	assert_float(model.get_link_strain(0, 1)).is_equal_approx(0.5, 0.001)
	model.drag_to(Vector2(500.0 + RADIUS + REACH * 0.95, 500))
	assert_float(model.get_link_strain(0, 1)).is_equal_approx(0.95, 0.001)
	assert_array(recorder.last_args(&"link_strain_changed")).is_equal([0, 1, model.get_link_strain(0, 1)])
	assert_float(PuzzleModel.link_strain(Vector2.ZERO, Vector2(RADIUS + REACH, 0), RADIUS, REACH)).is_equal(1.0)


func test_closest_candidate_wins() -> void:
	var level := _level()
	# Both candidates start within reach; 2 is closer.
	level.neurons[1].position = Vector2(620, 500)
	level.neurons[2].position = Vector2(500, 590)
	var model := PuzzleModel.from_level(level)
	assert_array(model.get_links(0)).is_equal([2])


func test_required_two_links_takes_the_two_closest() -> void:
	var level := _level(2)
	level.neurons.append(LevelFactory.neuron(3, Vector2(500, 400)))
	level.neurons[1].position = Vector2(620, 500)
	level.neurons[2].position = Vector2(500, 590)
	var model := PuzzleModel.from_level(level)
	assert_array(model.get_links(0)).is_equal([2, 3])
	assert_bool(model.is_receptor_satisfied(0)).is_true()


func test_full_receptor_ignores_further_candidates_until_a_link_breaks() -> void:
	var level := _level()
	level.neurons[2].position = Vector2(500, 590)
	var model := PuzzleModel.from_level(level)
	assert_array(model.get_links(0)).is_equal([2])
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_array(model.get_links(0)).is_equal([2])
	model.release()
	model.grab(2)
	model.drag_to(Vector2(500, 800))
	# 2 left, 1 is still within reach: it takes the free slot.
	assert_array(model.get_links(0)).is_equal([1])


func test_fixed_receptors_and_statically_connected_neurons_are_not_candidates() -> void:
	var neurons: Array[NeuronData] = [
		receptor(0, Vector2(500, 500)),
		receptor(1, Vector2(620, 500)),
		LevelFactory.neuron(2, Vector2(500, 600), null, true),
		LevelFactory.neuron(3, Vector2(380, 500)),
		LevelFactory.neuron(4, Vector2(900, 900)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(0, 3), LevelFactory.edge(3, 4)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_int(model.get_link_count(0)).is_equal(0)


func test_links_count_as_dendrites_for_crossings() -> void:
	# Link 0-1 (horizontal) crossed by static edge 2-3 (vertical).
	var neurons: Array[NeuronData] = [
		receptor(0, Vector2(500, 500)),
		LevelFactory.neuron(1, Vector2(640, 500)),
		LevelFactory.neuron(2, Vector2(570, 300)),
		LevelFactory.neuron(3, Vector2(570, 700)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(2, 3)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_array(model.get_links(0)).is_equal([1])
	assert_int(model.get_crossing_count()).is_equal(1)
	assert_array(model.get_crossing_edges()).is_equal([0])
	assert_array(model.get_crossing_links()).is_equal([Vector2i(0, 1)])
	assert_array(model.get_crossing_neurons()).is_equal([0, 1, 2, 3])
	assert_vector(model.get_crossing_points()[0]).is_equal_approx(Vector2(570, 500), Vector2(0.01, 0.01))


func test_breaking_a_crossing_link_resolves_the_crossing() -> void:
	var neurons: Array[NeuronData] = [
		receptor(0, Vector2(500, 500)),
		LevelFactory.neuron(1, Vector2(640, 500)),
		LevelFactory.neuron(2, Vector2(570, 300)),
		LevelFactory.neuron(3, Vector2(570, 700)),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, [LevelFactory.edge(2, 3)] as Array[DendriteData]))
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"crossings_changed"])
	model.grab(1)
	model.drag_to(Vector2(900, 500))
	assert_int(model.get_crossing_count()).is_equal(0)
	assert_array(model.get_crossing_links()).is_empty()
	assert_int(recorder.count(&"crossings_changed")).is_equal(1)


func test_win_needs_zero_crossings_and_every_receptor_linked() -> void:
	var model := PuzzleModel.from_level(_level())
	assert_int(model.get_crossing_count()).is_equal(0)
	assert_bool(model.are_receptors_satisfied()).is_false()
	model.grab(2)
	model.drag_to(Vector2(250, 250))
	model.release()
	assert_bool(model.is_solved()).is_false()
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	model.release()
	assert_bool(model.is_solved()).is_true()


func test_link_pairs_are_sorted_receptor_then_neuron() -> void:
	var level := _level()
	level.neurons[1].position = Vector2(620, 500)
	level.neurons.append(receptor(5, Vector2(740, 500)))
	var model := PuzzleModel.from_level(level)
	assert_array(model.get_link_pairs()).is_equal([Vector2i(0, 1), Vector2i(5, 1)])


# --- Validation -------------------------------------------------------------------

func _assert_has_error(errors: PackedStringArray, fragment: String) -> void:
	var found := false
	for error in errors:
		if error.contains(fragment):
			found = true
	assert_bool(found).override_failure_message(
		"Expected an error containing '%s', got %s" % [fragment, errors]).is_true()


## Receptor 0 needs neuron 1 (solution within reach). Tangle 10-13 keeps the start crossing.
func _valid_receptor_level() -> LevelData:
	var neurons: Array[NeuronData] = [
		receptor(0, Vector2(500, 300)),
		LevelFactory.neuron(1, Vector2(800, 300), Vector2(620, 300)),
	]
	var dendrites: Array[DendriteData] = []
	neurons.append(LevelFactory.neuron(10, Vector2(100, 700), Vector2(100, 700)))
	neurons.append(LevelFactory.neuron(11, Vector2(400, 900), Vector2(400, 700)))
	neurons.append(LevelFactory.neuron(12, Vector2(400, 700), Vector2(100, 900)))
	neurons.append(LevelFactory.neuron(13, Vector2(100, 900), Vector2(400, 900)))
	dendrites.append(LevelFactory.edge(10, 11))
	dendrites.append(LevelFactory.edge(12, 13))
	return LevelFactory.level(neurons, dendrites)


func test_valid_receptor_level_has_no_errors() -> void:
	assert_array(PuzzleModel.validate_level(_valid_receptor_level())).is_empty()


func test_solution_must_satisfy_every_receptor() -> void:
	var level := _valid_receptor_level()
	level.neurons[1].solution_position = Vector2(900, 300)
	_assert_has_error(PuzzleModel.validate_level(level), "Solution layout leaves receptor 0 with 0 of 1 link")


func test_receptor_settings_are_checked() -> void:
	var level := _valid_receptor_level()
	level.neurons[0].reach = 0.0
	level.neurons[0].required_links = 3
	level.neurons[0].solution_position = Vector2(510, 300)
	var errors := PuzzleModel.validate_level(level)
	_assert_has_error(errors, "Receptor 0: reach must be greater than 0")
	_assert_has_error(errors, "Receptor 0: required_links must be 1 or 2")
	_assert_has_error(errors, "Receptor 0: solution_position must equal position")


func test_start_already_solved_with_receptors_is_rejected() -> void:
	# No tangle, the receptor starts linked: nothing to do.
	var neurons: Array[NeuronData] = [
		receptor(0, Vector2(500, 300)),
		LevelFactory.neuron(1, Vector2(620, 300)),
		LevelFactory.neuron(2, Vector2(800, 800)),
	]
	var level := LevelFactory.level(neurons, [LevelFactory.edge(1, 2)] as Array[DendriteData])
	_assert_has_error(PuzzleModel.validate_level(level), "Start layout is already solved")


func test_start_without_crossings_but_unlinked_receptor_is_tangled_enough() -> void:
	var level := _valid_receptor_level()
	# Untangle the X: only the receptor is left to satisfy.
	for neuron in level.neurons:
		neuron.position = neuron.solution_position
	level.neurons[1].position = Vector2(800, 300)
	assert_array(PuzzleModel.validate_level(level)).is_empty()
