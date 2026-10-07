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


func test_blocked_signal_starts_a_contact_flash() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(0, model)
	model.grab(0)
	model.drag_to(Vector2(-100, 100))
	assert_bool(view.is_contact_flashing()).is_true()
