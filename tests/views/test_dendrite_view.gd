extends GdUnitTestSuite
## T2.1: DendriteView follows its endpoints and reflects crossing / tension / broken state.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const DendriteScene := preload("res://scenes/views/dendrite_view.tscn")


func _view(edge_id: int, model: PuzzleModel, show_feedback := true) -> DendriteView:
	var view: DendriteView = auto_free(DendriteScene.instantiate())
	view.setup(edge_id, model, show_feedback)
	return view


## Edge 0: TENSION 0-1 (rest 100, max 300). Edge 1: NORMAL 2-3. No crossings.
func _tension_model() -> PuzzleModel:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(200, 500)),
		LevelFactory.neuron(2, Vector2(100, 100)),
		LevelFactory.neuron(3, Vector2(300, 100)),
	]
	var dendrites: Array[DendriteData] = [
		LevelFactory.tension_edge(0, 1, 100.0, 300.0),
		LevelFactory.edge(2, 3),
	]
	return PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))


func test_setup_reads_endpoints() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(1, model)
	assert_that(view.get_endpoints()).is_equal(PackedVector2Array([Vector2(500, 100), Vector2(100, 500)]))


func test_endpoint_follows_moved_neuron() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	model.grab(1)
	model.drag_to(Vector2(450, 200))
	assert_that(view.get_endpoints()).is_equal(PackedVector2Array([Vector2(100, 100), Vector2(450, 200)]))


func test_crossing_dendrite_is_highlighted() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	assert_bool(view.is_highlighted()).is_true()
	assert_that(view.get_line_color()).is_equal(Palette.CROSSING)
	# Pull neuron 1 to the same side of edge 2-3 as neuron 0: one move untangles the X.
	model.grab(1)
	model.drag_to(Vector2(300, 180))
	assert_bool(view.is_highlighted()).is_false()
	assert_that(view.get_line_color()).is_equal(Palette.DENDRITE)


func test_no_highlight_when_feedback_is_off() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	assert_bool(_view(0, model, false).is_highlighted()).is_false()


func test_normal_dendrite_has_full_width() -> void:
	var model := _tension_model()
	assert_float(_view(1, model).get_line_width()).is_equal(DendriteView.WIDTH)


func test_tension_dendrite_is_green_and_thins_with_ratio() -> void:
	var model := _tension_model()
	var view := _view(0, model)
	assert_that(view.get_line_color()).is_equal(Palette.TENSION)
	assert_float(view.get_line_width()).is_equal(DendriteView.WIDTH)
	model.grab(1)
	model.drag_to(Vector2(300, 500))
	var expected := lerpf(DendriteView.WIDTH, DendriteView.MIN_TENSION_WIDTH, 0.5)
	assert_float(view.get_line_width()).is_equal_approx(expected, 0.0001)


func test_glow_shader_material_is_assigned() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	assert_object(view.material).is_instanceof(ShaderMaterial)
	assert_that(view.get_shader_param(&"line_color")).is_equal(Palette.DENDRITE)


func test_tension_look_follows_the_ratio() -> void:
	var model := _tension_model()
	var view := _view(0, model)
	assert_float(view.get_shader_param(&"tremble_px")).is_equal(0.0)
	assert_float(view.get_shader_param(&"flicker")).is_equal(0.0)
	model.grab(1)
	# 280 of max 300 from rest 100 -> ratio 0.9, inside the warning zone.
	model.drag_to(Vector2(380, 500))
	assert_float(view.get_shader_param(&"core_width_px")).is_equal_approx(view.get_line_width(), 0.0001)
	assert_float(view.get_shader_param(&"tremble_px")).is_equal_approx(VisualTuning.tension_tremble(0.9), 0.001)
	assert_float(view.get_shader_param(&"flicker")).is_equal_approx(VisualTuning.tension_flicker(0.9), 0.001)
	assert_that(view.get_shader_param(&"line_color")).is_equal(Palette.TENSION)


func test_crossing_warmth_calms_smoothly_after_resolution() -> void:
	var saved := GameState.reduced_motion
	GameState.reduced_motion = false
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	assert_float(view.get_highlight_amount()).is_equal(1.0)
	model.grab(1)
	model.drag_to(Vector2(300, 180))
	view._process(0.05)
	assert_float(view.get_highlight_amount()).is_between(0.01, 0.99)
	view._process(5.0)
	assert_float(view.get_highlight_amount()).is_equal(0.0)
	GameState.reduced_motion = true
	model.drag_to(Vector2(500, 500))
	view._process(0.01)
	# Reduced motion: no fade, the warmth snaps.
	assert_float(view.get_highlight_amount()).is_equal(1.0)
	assert_float(view.get_shader_param(&"motion")).is_equal(0.0)
	GameState.reduced_motion = saved


func test_broken_tension_dendrite_is_hidden() -> void:
	var model := _tension_model()
	var view := _view(0, model)
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	assert_bool(view.is_broken()).is_true()
	assert_bool(view.visible).is_false()
