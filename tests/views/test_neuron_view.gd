extends GdUnitTestSuite
## T2.1: NeuronView follows the model and reflects crossing / grabbed / fixed state.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const NeuronScene := preload("res://scenes/views/neuron_view.tscn")


func _view(id: int, model: PuzzleModel, show_feedback := true) -> NeuronView:
	var view: NeuronView = auto_free(NeuronScene.instantiate())
	view.setup(id, model, show_feedback)
	return view


func test_setup_places_view_at_model_position() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(1, model)
	assert_int(view.neuron_id).is_equal(1)
	assert_vector(view.position).is_equal(Vector2(500, 500))
	assert_float(view.get_radius()).is_equal(28.0)


func test_view_starts_highlighted_when_involved_in_a_crossing() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	assert_bool(_view(0, model).is_highlighted()).is_true()


func test_view_follows_only_its_own_neuron() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(1, model)
	model.grab(0)
	model.drag_to(Vector2(150, 150))
	assert_vector(view.position).is_equal(Vector2(500, 500))
	model.release()
	model.grab(1)
	model.drag_to(Vector2(450, 200))
	assert_vector(view.position).is_equal(Vector2(450, 200))


func test_highlight_clears_when_crossing_is_resolved() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	# Pull neuron 1 to the same side of edge 2-3 as neuron 0: one move untangles the X.
	model.grab(1)
	model.drag_to(Vector2(300, 180))
	assert_array(model.get_crossing_edges()).is_empty()
	assert_bool(view.is_highlighted()).is_false()


func test_highlight_disabled_when_feedback_is_off() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	assert_bool(_view(0, model, false).is_highlighted()).is_false()


func test_grabbed_state_enlarges_the_drawn_radius() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	view.set_grabbed(true)
	assert_bool(view.is_grabbed()).is_true()
	assert_float(view.get_draw_radius()).is_greater(view.get_radius())
	view.set_grabbed(false)
	assert_float(view.get_draw_radius()).is_equal(view.get_radius())


func test_fixed_neuron_uses_fixed_color() -> void:
	var level := LevelFactory.x_level()
	level.neurons[0].fixed = true
	var model := PuzzleModel.from_level(level)
	var view := _view(0, model, false)
	assert_bool(view.is_fixed()).is_true()
	assert_that(view.get_fill_color()).is_equal(Palette.NEURON_FIXED)


func test_glow_shader_material_is_assigned() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	assert_object(view.material).is_instanceof(ShaderMaterial)
	assert_float(view.get_shader_param(&"radius_px")).is_equal(view.get_radius())
	var other := _view(1, model)
	assert_float(view.get_shader_param(&"phase")).is_not_equal(other.get_shader_param(&"phase"))


func test_reduced_motion_stops_shader_motion() -> void:
	var saved := GameState.reduced_motion
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	GameState.reduced_motion = false
	view._process(0.016)
	assert_float(view.get_shader_param(&"motion")).is_equal(1.0)
	GameState.reduced_motion = true
	view._process(0.016)
	assert_float(view.get_shader_param(&"motion")).is_equal(0.0)
	GameState.reduced_motion = saved


func test_crossing_glow_fades_in_and_calms_smoothly() -> void:
	var saved := GameState.reduced_motion
	GameState.reduced_motion = false
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	# Starts at full warmth (already crossing when built).
	assert_float(view.get_highlight_amount()).is_equal(1.0)
	model.grab(1)
	model.drag_to(Vector2(300, 180))
	view._process(0.05)
	var mid := view.get_highlight_amount()
	assert_float(mid).is_between(0.01, 0.99)
	view._process(5.0)
	assert_float(view.get_highlight_amount()).is_equal(0.0)
	assert_float(view.get_shader_param(&"crossing")).is_equal(0.0)
	GameState.reduced_motion = saved


## T7.1 (revised): crossing shows as a soft, slow warm "latency" glow with light sparkle, not a
## dashed ring; the soma keeps its own color so it never reads as a red fixed neuron.
func test_crossing_uses_a_soft_latency_glow_not_a_ring() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	assert_bool(view.is_highlighted()).is_true()
	assert_that(view.get_shader_param(&"core_color")).is_equal(Palette.NEURON)
	assert_that(view.get_shader_param(&"latency_color")).is_equal(Palette.CROSSING_LATENCY)
	assert_object(view.get_shader_param(&"ring_color")).is_null()
	# Slower than the idle pulse: a gentle breathing.
	assert_float(view.get_shader_param(&"latency_speed")).is_less(VisualTuning.NEURON_PULSE_SPEED)
	var code := NeuronView.NeuronShader.code
	assert_bool(code.contains("dashes")).is_false()


func test_crossing_sparkle_honors_reduced_motion() -> void:
	var saved := GameState.reduced_motion
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	GameState.reduced_motion = false
	view._process(0.016)
	assert_float(view.get_shader_param(&"sparkle")).is_greater(0.0)
	GameState.reduced_motion = true
	view._process(0.016)
	assert_float(view.get_shader_param(&"sparkle")).is_equal(0.0)
	assert_float(view.get_shader_param(&"motion")).is_equal(0.0)
	GameState.reduced_motion = saved


func test_fixed_neuron_pulses_slower_and_deeper() -> void:
	var level := LevelFactory.x_level()
	level.neurons[0].fixed = true
	var model := PuzzleModel.from_level(level)
	var fixed := _view(0, model)
	var normal := _view(1, model)
	assert_float(fixed.get_shader_param(&"pulse_speed")).is_less(normal.get_shader_param(&"pulse_speed"))
	assert_float(fixed.get_shader_param(&"pulse_depth")).is_greater(normal.get_shader_param(&"pulse_depth"))


func test_blocked_signal_starts_a_contact_flash() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	model.grab(0)
	model.drag_to(Vector2(-100, 100))
	assert_bool(view.is_contact_flashing()).is_true()
