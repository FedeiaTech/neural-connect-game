extends GdUnitTestSuite
## T7.1: CrossingSparksView draws a crackling spark marker at every exact crossing point.

const LevelFactory := preload("res://tests/model/level_factory.gd")

var _saved_motion := false


func before_test() -> void:
	_saved_motion = GameState.reduced_motion
	GameState.reduced_motion = false


func after_test() -> void:
	GameState.reduced_motion = _saved_motion


func _view(model: PuzzleModel, show_feedback := true) -> CrossingSparksView:
	var view: CrossingSparksView = auto_free(CrossingSparksView.new())
	add_child(view)
	view.setup(model, show_feedback)
	return view


func test_one_marker_per_crossing_point() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(model)
	assert_int(view.get_marker_count()).is_equal(1)
	assert_vector(view.get_points()[0]).is_equal_approx(Vector2(300, 300), Vector2(0.01, 0.01))


func test_markers_follow_the_model() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(model)
	model.grab(1)
	model.drag_to(Vector2(250, 250))
	assert_int(view.get_marker_count()).is_equal(0)


func test_no_markers_when_feedback_is_off() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	assert_int(_view(model, false).get_marker_count()).is_equal(0)


func test_sparks_crackle_with_motion() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(model)
	for i in 10:
		view._process(0.03)
	assert_bool(view.is_static()).is_false()
	assert_int(view.get_particle_count()).is_greater(0)
	assert_int(view.get_arc_count()).is_greater(0)


func test_reduced_motion_shows_a_static_marker() -> void:
	GameState.reduced_motion = true
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view := _view(model)
	for i in 10:
		view._process(0.03)
	assert_bool(view.is_static()).is_true()
	assert_int(view.get_particle_count()).is_equal(0)
	assert_int(view.get_marker_count()).is_equal(1)


func test_particles_are_capped() -> void:
	var neurons: Array[NeuronData] = []
	var dendrites: Array[DendriteData] = []
	# A 6 x 6 grid of crossings (12 long dendrites).
	for i in 6:
		neurons.append(LevelFactory.neuron(i * 4, Vector2(50, 100 + i * 150)))
		neurons.append(LevelFactory.neuron(i * 4 + 1, Vector2(950, 100 + i * 150)))
		neurons.append(LevelFactory.neuron(i * 4 + 2, Vector2(100 + i * 150, 30)))
		neurons.append(LevelFactory.neuron(i * 4 + 3, Vector2(100 + i * 150, 970)))
		dendrites.append(LevelFactory.edge(i * 4, i * 4 + 1))
		dendrites.append(LevelFactory.edge(i * 4 + 2, i * 4 + 3))
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	var view := _view(model)
	assert_int(view.get_marker_count()).is_equal(36)
	for i in 60:
		view._process(0.03)
	assert_int(view.get_particle_count()).is_less_equal(CrossingSparksView.MAX_PARTICLES)


func test_arc_is_a_short_jagged_line_from_the_center() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var arc := CrossingSparksView.make_arc(Vector2(10, 20), rng, 18.0, 4, 4.0)
	assert_int(arc.size()).is_equal(5)
	assert_vector(arc[0]).is_equal(Vector2(10, 20))
	for point in arc:
		assert_float(point.distance_to(Vector2(10, 20))).is_less_equal(18.0 + 4.0 + 0.01)
