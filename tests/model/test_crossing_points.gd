extends GdUnitTestSuite
## T7.1: exact crossing points (one per crossing pair) for the spark markers.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")


func test_proper_intersection_point() -> void:
	var point: Variant = GeometryUtils.crossing_point(
		Vector2(0, 0), Vector2(100, 100), Vector2(100, 0), Vector2(0, 100))
	assert_vector(point).is_equal_approx(Vector2(50, 50), Vector2(0.01, 0.01))


func test_touching_endpoint_is_the_crossing_point() -> void:
	var point: Variant = GeometryUtils.crossing_point(
		Vector2(0, 0), Vector2(100, 0), Vector2(50, 0), Vector2(50, 80))
	assert_vector(point).is_equal_approx(Vector2(50, 0), Vector2(0.01, 0.01))


func test_collinear_overlap_uses_the_overlap_midpoint() -> void:
	# a: 100..500, b: 300..700 on y = 100 -> overlap 300..500, midpoint 400.
	var point: Variant = GeometryUtils.crossing_point(
		Vector2(100, 100), Vector2(500, 100), Vector2(700, 100), Vector2(300, 100))
	assert_vector(point).is_equal_approx(Vector2(400, 100), Vector2(0.01, 0.01))


func test_disjoint_segments_have_no_crossing_point() -> void:
	assert_object(GeometryUtils.crossing_point(
		Vector2(0, 0), Vector2(100, 0), Vector2(0, 50), Vector2(100, 50))).is_null()
	assert_object(GeometryUtils.crossing_point(
		Vector2(0, 0), Vector2(100, 0), Vector2(200, 0), Vector2(300, 0))).is_null()


func test_x_level_has_one_crossing_point_at_the_center() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var points := model.get_crossing_points()
	assert_int(points.size()).is_equal(1)
	assert_vector(points[0]).is_equal_approx(Vector2(300, 300), Vector2(0.01, 0.01))


func test_solved_layout_has_no_crossing_points() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level(), true)
	assert_int(model.get_crossing_points().size()).is_equal(0)


func test_one_point_per_crossing_pair() -> void:
	# Edge 0 is crossed by edges 1 and 2: two points on y = 500.
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(900, 500)),
		LevelFactory.neuron(2, Vector2(300, 100)),
		LevelFactory.neuron(3, Vector2(300, 900)),
		LevelFactory.neuron(4, Vector2(600, 100)),
		LevelFactory.neuron(5, Vector2(600, 900)),
	]
	var dendrites: Array[DendriteData] = [
		LevelFactory.edge(0, 1), LevelFactory.edge(2, 3), LevelFactory.edge(4, 5),
	]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	var points := model.get_crossing_points()
	assert_int(points.size()).is_equal(model.get_crossing_count())
	assert_vector(points[0]).is_equal_approx(Vector2(300, 500), Vector2(0.01, 0.01))
	assert_vector(points[1]).is_equal_approx(Vector2(600, 500), Vector2(0.01, 0.01))


func test_crossing_points_changed_follows_the_drag() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"crossing_points_changed"])
	model.grab(1)
	# Still crossing, but the intersection moves: the points change, the edge set does not.
	model.drag_to(Vector2(500, 300))
	assert_int(recorder.count(&"crossing_points_changed")).is_equal(1)
	var points: PackedVector2Array = recorder.last_args(&"crossing_points_changed")[0]
	assert_int(points.size()).is_equal(1)
	assert_vector(points[0]).is_equal_approx(model.get_crossing_points()[0], Vector2(0.01, 0.01))
	# Untangled: an empty notification.
	model.drag_to(Vector2(250, 250))
	assert_int(model.get_crossing_count()).is_equal(0)
	assert_int(recorder.count(&"crossing_points_changed")).is_equal(2)
	assert_int((recorder.last_args(&"crossing_points_changed")[0] as PackedVector2Array).size()).is_equal(0)


func test_moving_an_unrelated_neuron_does_not_notify_points() -> void:
	var level := LevelFactory.x_level()
	level.neurons.append(LevelFactory.neuron(4, Vector2(800, 800)))
	var model := PuzzleModel.from_level(level)
	var recorder := SignalRecorder.new()
	recorder.watch(model, [&"crossing_points_changed"])
	model.grab(4)
	model.drag_to(Vector2(850, 800))
	assert_int(recorder.count(&"crossing_points_changed")).is_equal(0)
