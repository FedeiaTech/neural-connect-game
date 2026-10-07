extends GdUnitTestSuite
## T4.2: MembraneOutline (living boundary/obstacle outline) and the views that use it.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const BoundaryScene := preload("res://scenes/views/boundary.tscn")
const ObstacleScene := preload("res://scenes/views/obstacle_view.tscn")

var _saved_reduced_motion := false


func before_test() -> void:
	_saved_reduced_motion = GameState.reduced_motion
	GameState.reduced_motion = false


func after_test() -> void:
	GameState.reduced_motion = _saved_reduced_motion


func _square() -> MembraneOutline:
	var membrane := MembraneOutline.new()
	membrane.build(LevelFactory.rect(Vector2.ZERO, Vector2(400, 400)), 10.0)
	return membrane


func test_build_resamples_the_closed_outline() -> void:
	var membrane := _square()
	assert_float(membrane.get_perimeter()).is_equal_approx(1600.0, 0.01)
	var points := membrane.get_base_points()
	assert_int(points.size()).is_greater_equal(160)
	for i in points.size():
		var next := points[(i + 1) % points.size()]
		assert_float(points[i].distance_to(next)).is_less_equal(10.0 + 0.001)


func test_normals_point_out_of_the_polygon() -> void:
	var membrane := _square()
	var polygon := LevelFactory.rect(Vector2.ZERO, Vector2(400, 400))
	var points := membrane.get_base_points()
	var normals := membrane.get_normals()
	for i in points.size():
		assert_bool(Geometry2D.is_point_in_polygon(points[i] + normals[i] * 3.0, polygon)).is_false()
		assert_float(normals[i].length()).is_equal_approx(1.0, 0.001)


func test_wave_offset_is_bounded_by_its_amplitude() -> void:
	for i in 200:
		var u := i / 200.0
		var t := i * 0.37
		var offset := MembraneOutline.wave_offset(u, t, 3.5, 4, 9)
		assert_float(absf(offset)).is_less_equal(3.5 + 0.0001)


func test_wave_offset_wraps_continuously_around_the_outline() -> void:
	for t in [0.0, 1.3, 7.9]:
		assert_float(MembraneOutline.wave_offset(0.0, t, 3.5, 4, 9)) \
			.is_equal_approx(MembraneOutline.wave_offset(1.0, t, 3.5, 4, 9), 0.0001)


func test_ripple_offset_is_bounded_and_dies_out() -> void:
	for i in 100:
		var offset := MembraneOutline.ripple_offset(i * 3.0, i * 0.015)
		assert_float(absf(offset)).is_less_equal(VisualTuning.RIPPLE_AMPLITUDE + 0.0001)
	assert_float(MembraneOutline.ripple_offset(0.0, 0.0)).is_equal(VisualTuning.RIPPLE_AMPLITUDE)
	assert_float(MembraneOutline.ripple_offset(0.0, VisualTuning.RIPPLE_LIFETIME)).is_equal(0.0)


func test_ripples_start_only_near_the_outline_and_respect_a_cooldown() -> void:
	var membrane := _square()
	assert_bool(membrane.add_ripple(Vector2(200, 200), 0.0, 40.0)).is_false()
	assert_bool(membrane.add_ripple(Vector2(30, 200), 0.0, 40.0)).is_true()
	assert_bool(membrane.has_ripples(0.1)).is_true()
	# Same spot again right away: ignored.
	assert_bool(membrane.add_ripple(Vector2(30, 205), 0.1, 40.0)).is_false()
	assert_bool(membrane.add_ripple(Vector2(30, 205), 1.0, 40.0)).is_true()
	assert_bool(membrane.has_ripples(5.0)).is_false()


func test_displaced_outline_stays_within_amplitude_and_is_static_without_motion() -> void:
	var membrane := _square()
	membrane.add_ripple(Vector2(30, 200), 0.0, 40.0)
	var base := membrane.get_base_points()
	var limit := 3.5 + VisualTuning.RIPPLE_AMPLITUDE
	var moving := membrane.displaced(0.2, 3.5, 1.0, 0.0)
	assert_int(moving.size()).is_equal(base.size() + 1)
	for i in base.size():
		assert_float(moving[i].distance_to(base[i])).is_less_equal(limit + 0.001)
	var still := membrane.displaced(0.2, 3.5, 0.0, 1.0)
	for i in base.size():
		assert_vector(still[i]).is_equal(base[i])


func test_boundary_ripples_when_a_neuron_touches_it() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view: BoundaryView = auto_free(BoundaryScene.instantiate())
	view.setup(model)
	assert_bool(view.has_ripples()).is_false()
	model.grab(0)
	model.drag_to(Vector2(-100, 100))
	assert_bool(view.has_ripples()).is_true()


func test_boundary_ignores_neuron_contacts_away_from_it() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view: BoundaryView = auto_free(BoundaryScene.instantiate())
	view.setup(model)
	# Neuron 0 runs into neuron 3 in the middle of the area, far from the boundary.
	model.grab(0)
	model.drag_to(Vector2(100, 470))
	assert_bool(view.has_ripples()).is_false()


func test_obstacle_ripples_when_a_neuron_touches_it() -> void:
	var obstacle := LevelFactory.rect(Vector2(250, 250), Vector2(100, 100))
	var level := LevelFactory.x_level()
	var obstacles: Array[PackedVector2Array] = [obstacle]
	level.obstacles = obstacles
	var model := PuzzleModel.from_level(level)
	var view: ObstacleView = auto_free(ObstacleScene.instantiate())
	view.setup(obstacle, model)
	model.grab(0)
	model.drag_to(Vector2(300, 300))
	assert_bool(view.has_ripples()).is_true()
