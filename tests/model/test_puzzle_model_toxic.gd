extends GdUnitTestSuite
## T8.2: toxic neurons (SOFT rule). A TOXIC neuron is movable like a normal one; inside a
## receptor's reach it forms a contamination link (separate from normal links: no slot, not
## counted towards required_links, never a crossing, never a loss). The win additionally needs
## zero contamination links.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const RADIUS := 28.0
const REACH := 120.0


## Receptor 0 at (500, 500) with reach 120. Normal neuron 1 at (610, 500) (linked at build),
## toxic neuron 2 at (500, 750) (out of reach). No dendrites: zero crossings.
func _level(required := 1) -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), REACH, required),
		LevelFactory.neuron(1, Vector2(610, 500)),
		LevelFactory.toxic(2, Vector2(500, 750)),
	]
	var dendrites: Array[DendriteData] = []
	return LevelFactory.level(neurons, dendrites)


func test_neuron_data_toxic_kind() -> void:
	var data := NeuronData.new()
	assert_bool(data.is_toxic()).is_false()
	data.kind = NeuronData.Kind.TOXIC
	assert_bool(data.is_toxic()).is_true()
	assert_bool(data.is_receptor()).is_false()


func test_toxic_neuron_is_movable() -> void:
	var model := PuzzleModel.from_level(_level())
	assert_bool(model.is_toxic(2)).is_true()
	assert_bool(model.is_toxic(1)).is_false()
	assert_bool(model.is_fixed(2)).is_false()
	assert_bool(model.grab(2)).is_true()


func test_toxic_inside_reach_forms_a_contamination_link() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"contamination_formed", &"link_formed"])
	assert_bool(model.is_contaminated()).is_false()
	model.grab(2)
	model.drag_to(Vector2(500, 700))
	assert_bool(model.is_contaminated()).is_false()
	model.drag_to(Vector2(500, 500.0 + RADIUS + REACH - 1.0))
	assert_bool(model.is_contaminated()).is_true()
	assert_array(model.get_contamination_links()).is_equal([Vector2i(0, 2)])
	assert_bool(model.has_contamination(0, 2)).is_true()
	assert_int(recorder.count(&"contamination_formed")).is_equal(1)
	assert_array(recorder.last_args(&"contamination_formed")).is_equal([0, 2])
	# It is not a normal link: no slot used, no link_formed.
	assert_int(recorder.count(&"link_formed")).is_equal(0)
	assert_array(model.get_links(0)).is_equal([1])


func test_contamination_clears_when_the_toxic_neuron_leaves_reach() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"contamination_cleared"])
	model.grab(2)
	model.drag_to(Vector2(500, 600))
	assert_bool(model.is_contaminated()).is_true()
	model.drag_to(Vector2(500, 800))
	assert_bool(model.is_contaminated()).is_false()
	assert_int(recorder.count(&"contamination_cleared")).is_equal(1)
	assert_array(recorder.last_args(&"contamination_cleared")).is_equal([0, 2])


func test_contamination_does_not_count_towards_required_links() -> void:
	# Only a toxic neuron is in reach: the receptor stays unsatisfied.
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), REACH, 1),
		LevelFactory.toxic(1, Vector2(610, 500)),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, []))
	assert_bool(model.is_contaminated()).is_true()
	assert_int(model.get_link_count(0)).is_equal(0)
	assert_bool(model.is_receptor_satisfied(0)).is_false()
	assert_bool(model.are_receptors_satisfied()).is_false()


func test_a_closer_toxic_neuron_never_takes_the_link_slot() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), REACH, 1),
		LevelFactory.toxic(1, Vector2(570, 500)),
		LevelFactory.neuron(2, Vector2(800, 500)),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, []))
	model.grab(2)
	model.drag_to(Vector2(500, 640))
	assert_array(model.get_links(0)).is_equal([2])
	assert_array(model.get_contamination_links()).is_equal([Vector2i(0, 1)])


func test_win_is_blocked_while_contaminated_and_never_a_loss() -> void:
	var model := PuzzleModel.from_level(_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"solved"])
	model.grab(2)
	model.drag_to(Vector2(500, 600))
	model.release()
	assert_bool(model.is_contaminated()).is_true()
	assert_bool(model.is_solved()).is_false()
	assert_bool(model.is_lost()).is_false()
	assert_int(recorder.count(&"solved")).is_equal(0)
	model.grab(2)
	model.drag_to(Vector2(500, 800))
	model.release()
	assert_bool(model.is_solved()).is_true()
	assert_int(recorder.count(&"solved")).is_equal(1)


func test_contamination_links_are_warnings_not_crossings() -> void:
	# Dendrite 3-4 passes between the receptor and the toxic neuron.
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), REACH, 1),
		LevelFactory.toxic(1, Vector2(640, 500)),
		LevelFactory.neuron(3, Vector2(570, 380)),
		LevelFactory.neuron(4, Vector2(570, 620)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(3, 4)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_bool(model.is_contaminated()).is_true()
	assert_int(model.get_crossing_count()).is_equal(0)


func test_each_receptor_tracks_its_own_contamination() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(300, 500), REACH, 1),
		LevelFactory.receptor(1, Vector2(700, 500), REACH, 1),
		LevelFactory.toxic(2, Vector2(500, 500)),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, []))
	assert_array(model.get_contamination_links()).is_empty()
	model.grab(2)
	model.drag_to(Vector2(400, 500))
	assert_array(model.get_contamination_links()).is_equal([Vector2i(0, 2)])
	model.drag_to(Vector2(600, 500))
	assert_array(model.get_contamination_links()).is_equal([Vector2i(1, 2)])


func test_a_static_dendrite_to_the_receptor_still_contaminates() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), REACH, 1),
		LevelFactory.toxic(1, Vector2(610, 500)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(0, 1)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	assert_bool(model.is_contaminated()).is_true()


func test_a_toxic_neuron_without_receptors_is_harmless() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(300, 300)),
		LevelFactory.toxic(1, Vector2(600, 300)),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, []))
	assert_bool(model.is_contaminated()).is_false()
	assert_bool(model.get_contamination_links().is_empty()).is_true()
