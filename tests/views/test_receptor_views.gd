extends GdUnitTestSuite
## T7.3: receptor look (cyan soma, reach halo, searching stub, required-link dots) and the
## dynamic link views (grow, strain thinning, crossing, snap on break, completion wave).

const LevelFactory := preload("res://tests/model/level_factory.gd")
const NeuronScene := preload("res://scenes/views/neuron_view.tscn")
const LevelScene := preload("res://scenes/level/level.tscn")
const REACH := 120.0

var _saved_motion := false


func before_test() -> void:
	_saved_motion = GameState.reduced_motion
	GameState.reduced_motion = false


func after_test() -> void:
	GameState.reduced_motion = _saved_motion


## Receptor 0 (needs 2) at (500, 500); neuron 1 at (800, 500); neuron 2 at (500, 200);
## static edge 1-2 plus an X (3-4, 5-6) crossing far away.
func _model() -> PuzzleModel:
	var receptor := LevelFactory.neuron(0, Vector2(500, 500))
	receptor.kind = NeuronData.Kind.RECEPTOR
	receptor.reach = REACH
	receptor.required_links = 2
	var neurons: Array[NeuronData] = [
		receptor,
		LevelFactory.neuron(1, Vector2(800, 500)),
		LevelFactory.neuron(2, Vector2(500, 200)),
		LevelFactory.neuron(3, Vector2(100, 700)),
		LevelFactory.neuron(4, Vector2(300, 900)),
		LevelFactory.neuron(5, Vector2(300, 700)),
		LevelFactory.neuron(6, Vector2(100, 900)),
	]
	var dendrites: Array[DendriteData] = [
		LevelFactory.edge(1, 2), LevelFactory.edge(3, 4), LevelFactory.edge(5, 6)]
	return PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))


func _links(model: PuzzleModel) -> LinksView:
	var view: LinksView = auto_free(LinksView.new())
	add_child(view)
	view.setup(model)
	return view


func _receptor(model: PuzzleModel) -> ReceptorView:
	var view: ReceptorView = auto_free(ReceptorView.new())
	add_child(view)
	view.setup(0, model)
	return view


func test_receptor_soma_is_cyan_and_immovable() -> void:
	var model := _model()
	var view: NeuronView = auto_free(NeuronScene.instantiate())
	view.setup(0, model)
	assert_bool(view.is_receptor()).is_true()
	assert_bool(view.is_fixed()).is_true()
	assert_that(view.get_fill_color()).is_equal(Palette.RECEPTOR)
	assert_that(view.get_shader_param(&"core_color")).is_equal(Palette.RECEPTOR)


func test_receptor_view_shows_halo_dots_and_searching_stub() -> void:
	var model := _model()
	var view := _receptor(model)
	assert_float(view.get_halo_radius()).is_equal(28.0 + REACH)
	assert_array(view.get_dot_states()).is_equal([false, false])
	assert_bool(view.is_searching()).is_true()
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_array(view.get_dot_states()).is_equal([true, false])
	model.release()
	model.grab(2)
	model.drag_to(Vector2(500, 400))
	assert_array(view.get_dot_states()).is_equal([true, true])
	assert_bool(view.is_searching()).is_false()


func test_link_grows_from_the_receptor() -> void:
	var model := _model()
	var view := _links(model)
	assert_int(view.get_link_count()).is_equal(0)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	var pair := Vector2i(0, 1)
	assert_int(view.get_link_count()).is_equal(1)
	assert_float(view.get_grow(pair)).is_less(1.0)
	assert_int(view.get_flash_count()).is_equal(1)
	for i in 30:
		view._process(0.03)
	assert_float(view.get_grow(pair)).is_equal(1.0)


func test_reduced_motion_link_appears_at_once() -> void:
	GameState.reduced_motion = true
	var model := _model()
	var view := _links(model)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_float(view.get_grow(Vector2i(0, 1))).is_equal(1.0)


func test_link_thins_near_the_reach_limit() -> void:
	var model := _model()
	var view := _links(model)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	var relaxed := view.get_width(Vector2i(0, 1))
	model.drag_to(Vector2(500.0 + 28.0 + REACH * 0.97, 500))
	assert_float(view.get_width(Vector2i(0, 1))).is_less(relaxed)
	assert_float(view.get_strain(Vector2i(0, 1))).is_greater(0.9)


func test_break_snaps_with_sparks_and_clears_the_link() -> void:
	var model := _model()
	var view := _links(model)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	model.drag_to(Vector2(900, 500))
	assert_int(view.get_link_count()).is_equal(0)
	assert_int(view.get_breaking_count()).is_equal(1)
	for i in 40:
		view._process(0.03)
	assert_int(view.get_breaking_count()).is_equal(0)


func test_crossing_link_is_flagged() -> void:
	var model := _model()
	var view := _links(model)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	# Neuron 4 takes the second slot; then dendrite 3-4 is pulled across link 0-1.
	model.release()
	model.grab(4)
	model.drag_to(Vector2(560, 600))
	model.release()
	model.grab(3)
	model.drag_to(Vector2(560, 380))
	assert_array(model.get_crossing_links()).is_equal([Vector2i(0, 1)])
	assert_bool(view.is_link_crossing(Vector2i(0, 1))).is_true()
	# A crossing link stays a solid cyan line: no travelling dashes.
	assert_bool(view.has_method(&"_draw_dashed")).is_false()


func test_completion_wave_runs_through_links_in_the_level() -> void:
	var level: Level = auto_free(LevelScene.instantiate())
	add_child(level)
	var data := LevelFactory.x_level()
	var receptor := LevelFactory.neuron(9, Vector2(800, 300))
	receptor.kind = NeuronData.Kind.RECEPTOR
	receptor.reach = REACH
	data.neurons.append(receptor)
	data.neurons[1].position = Vector2(700, 380)
	level.load_level(data)
	var links: LinksView = level.get_node(^"Playfield/Links")
	assert_int(links.get_link_count()).is_equal(1)
	var fx: LevelFx = level.get_node(^"Playfield/Fx")
	fx.play_completion_wave()
	assert_int(links.get_wave_count()).is_equal(1)
	var receptors := level.get_node(^"Playfield/Receptors").get_children()
	assert_int(receptors.size()).is_equal(1)
