extends GdUnitTestSuite
## T8.2: toxic neuron look (yellow soma, warning glow), contamination link (flickering yellow
## line with a warning flash) and the receptor reacting to contamination. Reduced motion calms
## the flicker and the glow pulse.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const NeuronScene := preload("res://scenes/views/neuron_view.tscn")

var _saved_motion := false


func before_test() -> void:
	_saved_motion = GameState.reduced_motion
	GameState.reduced_motion = false


func after_test() -> void:
	GameState.reduced_motion = _saved_motion


## Receptor 0 (500, 500) reach 120, normal neuron 1 (800, 500), toxic neuron 2 (500, 750).
func _model() -> PuzzleModel:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), 120.0, 1),
		LevelFactory.neuron(1, Vector2(800, 500)),
		LevelFactory.toxic(2, Vector2(500, 750)),
	]
	return PuzzleModel.from_level(LevelFactory.level(neurons, []))


func _neuron(model: PuzzleModel, id: int) -> NeuronView:
	var view: NeuronView = auto_free(NeuronScene.instantiate())
	add_child(view)
	view.setup(id, model)
	return view


func _move_toxic_into_reach(model: PuzzleModel) -> void:
	model.grab(2)
	model.drag_to(Vector2(500, 620))


func test_palette_toxic_yellow_is_distinct_from_the_other_identities() -> void:
	for other in [Palette.NEURON, Palette.NEURON_FIXED, Palette.RECEPTOR, Palette.LETHAL, Palette.TENSION,
			Palette.CROSSING_DENDRITE, Palette.SPARK_GLOW]:
		var distance := Vector3(Palette.TOXIC.r - other.r, Palette.TOXIC.g - other.g, Palette.TOXIC.b - other.b).length()
		assert_float(distance).is_greater(0.25)


func test_toxic_neuron_is_yellow() -> void:
	var model := _model()
	var toxic := _neuron(model, 2)
	assert_bool(toxic.is_toxic()).is_true()
	assert_bool(_neuron(model, 1).is_toxic()).is_false()
	assert_object(toxic.get_fill_color()).is_equal(Palette.TOXIC)
	assert_object(toxic.get_shader_param(&"core_color")).is_equal(Palette.TOXIC)
	assert_object(toxic.get_shader_param(&"warn_color")).is_equal(Palette.TOXIC_GLOW)


func test_toxic_glow_is_faint_until_contaminated() -> void:
	var model := _model()
	var toxic := _neuron(model, 2)
	assert_float(toxic.get_warning_target()).is_equal(VisualTuning.TOXIC_WARN_IDLE)
	_move_toxic_into_reach(model)
	assert_bool(toxic.is_contaminated()).is_true()
	assert_float(toxic.get_warning_target()).is_equal(1.0)
	model.drag_to(Vector2(500, 800))
	assert_bool(toxic.is_contaminated()).is_false()
	assert_float(toxic.get_warning_target()).is_equal(VisualTuning.TOXIC_WARN_IDLE)


func test_normal_neurons_have_no_warning_glow() -> void:
	var model := _model()
	assert_float(_neuron(model, 1).get_warning_target()).is_equal(0.0)


func test_reduced_motion_snaps_the_warning_glow_and_stops_its_pulse() -> void:
	GameState.reduced_motion = true
	var model := _model()
	var toxic := _neuron(model, 2)
	_move_toxic_into_reach(model)
	toxic._process(0.0)
	assert_float(toxic.get_warning_amount()).is_equal(1.0)
	assert_float(toxic.get_shader_param(&"motion")).is_equal(0.0)


func test_contamination_link_follows_the_model() -> void:
	var model := _model()
	var links: LinksView = auto_free(LinksView.new())
	add_child(links)
	links.setup(model)
	assert_int(links.get_contamination_count()).is_equal(0)
	_move_toxic_into_reach(model)
	assert_int(links.get_contamination_count()).is_equal(1)
	assert_bool(links.has_contamination(Vector2i(0, 2))).is_true()
	# A warning flash appears where the link forms.
	assert_int(links.get_flash_count()).is_greater(0)
	model.drag_to(Vector2(500, 800))
	assert_int(links.get_contamination_count()).is_equal(0)
	# It is a warning, not a normal link.
	assert_int(links.get_link_count()).is_equal(0)


func test_contamination_present_at_build_is_drawn() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), 120.0, 1),
		LevelFactory.toxic(1, Vector2(600, 500)),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, []))
	var links: LinksView = auto_free(LinksView.new())
	add_child(links)
	links.setup(model)
	assert_int(links.get_contamination_count()).is_equal(1)


func test_flicker_is_steady_with_reduced_motion() -> void:
	for t in [0.0, 0.13, 0.5, 1.7]:
		assert_float(LinksView.contamination_flicker(t, 0.0)).is_equal(1.0)


func test_flicker_dips_with_motion_but_never_vanishes() -> void:
	var lowest := 1.0
	for i in 200:
		var value := LinksView.contamination_flicker(i * 0.037, 1.0)
		assert_float(value).is_between(LinksView.CONTAMINATION_FLICKER_MIN, 1.0)
		lowest = minf(lowest, value)
	assert_float(lowest).is_less(1.0)


func test_receptor_flags_contamination() -> void:
	var model := _model()
	var receptor: ReceptorView = auto_free(ReceptorView.new())
	add_child(receptor)
	receptor.setup(0, model)
	assert_bool(receptor.is_contaminated()).is_false()
	_move_toxic_into_reach(model)
	assert_bool(receptor.is_contaminated()).is_true()
	model.drag_to(Vector2(500, 800))
	assert_bool(receptor.is_contaminated()).is_false()


func test_receptor_stub_ignores_toxic_neurons() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), 120.0, 1),
		LevelFactory.toxic(1, Vector2(500, 700)),
		LevelFactory.neuron(2, Vector2(900, 500)),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, []))
	var receptor: ReceptorView = auto_free(ReceptorView.new())
	add_child(receptor)
	receptor.setup(0, model)
	# The nearest movable neuron is the toxic one (below), but the stub looks for a real partner.
	assert_float(receptor._nearest_candidate_angle()).is_equal_approx(0.0, 0.01)
