extends GdUnitTestSuite
## T8.3: diseased dendrites. A DISEASED dendrite breaks when stretched beyond max_length: it is
## removed from the active edge set (no more crossings), diseased_broken(edge_id) fires, it stays
## broken until a rebuild, breaking is never a loss and the win needs every diseased dendrite broken.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")


## Edge 0: DISEASED 0-1 (rest 100, max 300), start length 150. Edge 1: NORMAL 2-3 vertical at
## x = 275 crossing it. Neuron 1 can be pulled right to break edge 0.
func _level() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(200, 500)),
		LevelFactory.neuron(1, Vector2(350, 500)),
		LevelFactory.neuron(2, Vector2(275, 400)),
		LevelFactory.neuron(3, Vector2(275, 600)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(0, 1, 100.0, 300.0), LevelFactory.edge(2, 3)]
	return LevelFactory.level(neurons, dendrites)


## The same diseased edge alone, no crossing anywhere.
func _alone() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(200, 500)),
		LevelFactory.neuron(1, Vector2(350, 500)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(0, 1, 100.0, 300.0)]
	return LevelFactory.level(neurons, dendrites)


func test_dendrite_data_diseased_kind() -> void:
	var data := DendriteData.new()
	assert_bool(data.is_diseased()).is_false()
	data.kind = DendriteData.Kind.DISEASED
	assert_bool(data.is_diseased()).is_true()
	assert_bool(data.is_tension()).is_false()


func test_diseased_edge_queries() -> void:
	var model := PuzzleModel.from_level(_level())
	assert_bool(model.is_diseased_edge(0)).is_true()
	assert_bool(model.is_diseased_edge(1)).is_false()
	# It is a different kind from a tension dendrite (different views and sounds).
	assert_bool(model.is_tension_edge(0)).is_false()
	assert_int(model.get_diseased_count()).is_equal(1)
	assert_int(model.get_diseased_broken_count()).is_equal(0)
	assert_bool(model.is_edge_broken(0)).is_false()
	assert_bool(model.are_diseased_broken()).is_false()
	assert_float(model.get_diseased_ratio(0)).is_equal_approx(0.25, 0.0001)
	assert_float(model.get_diseased_ratio(1)).is_equal(0.0)


func test_strain_follows_the_stretch() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"diseased_strain_changed", &"tension_changed"])
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	assert_array(recorder.last_args(&"diseased_strain_changed")).is_equal([0, 0.75])
	assert_float(model.get_diseased_ratio(0)).is_equal_approx(0.75, 0.0001)
	# Tension listeners (e.g. the tension tone) never hear about diseased edges.
	assert_int(recorder.count(&"tension_changed")).is_equal(0)


func test_stretching_past_max_length_breaks_it_without_losing() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"diseased_broken", &"edge_broke", &"neuron_destroyed"])
	model.grab(1)
	model.drag_to(Vector2(500, 500))
	assert_int(recorder.count(&"diseased_broken")).is_equal(0)
	model.drag_to(Vector2(501, 500))
	assert_int(recorder.count(&"diseased_broken")).is_equal(1)
	assert_array(recorder.last_args(&"diseased_broken")).is_equal([0])
	assert_bool(model.is_edge_broken(0)).is_true()
	assert_int(model.get_diseased_broken_count()).is_equal(1)
	assert_bool(model.are_diseased_broken()).is_true()
	# Required, never a loss: the grab continues, no tension break, no restart.
	assert_bool(model.is_lost()).is_false()
	assert_bool(model.is_broken()).is_false()
	assert_int(model.get_grabbed_id()).is_equal(1)
	assert_int(recorder.count(&"edge_broke")).is_equal(0)
	assert_int(recorder.count(&"neuron_destroyed")).is_equal(0)


func test_breaking_resolves_its_crossings() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"crossings_changed"])
	assert_int(model.get_crossing_count()).is_equal(1)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_int(model.get_crossing_count()).is_equal(0)
	assert_array(model.get_crossing_edges()).is_empty()
	assert_array(recorder.last_args(&"crossings_changed")[0]).is_empty()


func test_a_broken_dendrite_stays_broken_and_never_crosses_again() -> void:
	var model := PuzzleModel.from_level(_level())
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	# Back inside the limit and across the other dendrite: still broken, still no crossing.
	model.drag_to(Vector2(350, 500))
	assert_bool(model.is_edge_broken(0)).is_true()
	assert_int(model.get_crossing_count()).is_equal(0)


func test_breaking_works_from_either_endpoint() -> void:
	var model := PuzzleModel.from_level(_level())
	model.grab(0)
	model.drag_to(Vector2(30, 500))
	assert_bool(model.is_edge_broken(0)).is_true()


func test_win_needs_every_diseased_dendrite_broken() -> void:
	var model := PuzzleModel.from_level(_alone())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"solved"])
	# No crossings at all, but the diseased dendrite is intact.
	model.grab(1)
	model.drag_to(Vector2(400, 500))
	model.release()
	assert_bool(model.is_solved()).is_false()
	assert_int(recorder.count(&"solved")).is_equal(0)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	model.release()
	assert_bool(model.is_solved()).is_true()
	assert_int(recorder.count(&"solved")).is_equal(1)


func test_win_also_needs_zero_crossings() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(200, 500)),
		LevelFactory.neuron(1, Vector2(350, 500)),
		LevelFactory.neuron(2, Vector2(100, 100)),
		LevelFactory.neuron(3, Vector2(500, 300)),
		LevelFactory.neuron(4, Vector2(500, 100)),
		LevelFactory.neuron(5, Vector2(100, 300)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(0, 1, 100.0, 300.0),
		LevelFactory.edge(2, 3), LevelFactory.edge(4, 5)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	model.release()
	assert_int(model.get_crossing_count()).is_equal(1)
	assert_bool(model.is_solved()).is_false()


func test_several_diseased_dendrites_are_counted() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(200, 500)),
		LevelFactory.neuron(1, Vector2(350, 500)),
		LevelFactory.neuron(2, Vector2(200, 800)),
		LevelFactory.neuron(3, Vector2(350, 800)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(0, 1, 100.0, 300.0),
		LevelFactory.diseased_edge(2, 3, 100.0, 300.0)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_int(model.get_diseased_count()).is_equal(2)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	model.release()
	assert_int(model.get_diseased_broken_count()).is_equal(1)
	assert_bool(model.are_diseased_broken()).is_false()
	model.grab(3)
	model.drag_to(Vector2(600, 800))
	model.release()
	assert_bool(model.are_diseased_broken()).is_true()
	assert_bool(model.is_solved()).is_true()


func test_a_tension_dendrite_still_loses_the_level() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(200, 500)),
		LevelFactory.neuron(1, Vector2(350, 500)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.tension_edge(0, 1, 100.0, 300.0)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_bool(model.is_broken()).is_true()
	assert_int(model.get_diseased_count()).is_equal(0)
	assert_bool(model.are_diseased_broken()).is_true()


func test_a_levels_without_diseased_dendrites_win_as_before() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	assert_bool(model.are_diseased_broken()).is_true()


## Solution layouts stretch the dendrite past its limit: the model built for validation treats it
## as broken (and therefore without crossings).
func test_solution_model_marks_stretched_diseased_dendrites_broken() -> void:
	var level := _level()
	level.neurons[1].solution_position = Vector2(600, 500)
	var model := PuzzleModel.from_level(level, true)
	assert_bool(model.is_edge_broken(0)).is_true()
	assert_int(model.get_crossing_count()).is_equal(0)
	# Not stretched in the solution: stays intact (and crosses).
	var unstretched := PuzzleModel.from_level(_level(), true)
	assert_bool(unstretched.is_edge_broken(0)).is_false()
	assert_int(unstretched.get_crossing_count()).is_equal(1)
