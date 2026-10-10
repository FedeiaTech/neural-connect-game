extends GdUnitTestSuite
## Organic neuron body (NeuronShape): strictly convex at every time, bounded around the collision
## circle, deterministic per seed, static with reduced motion, and in sync with the shader.

const SEEDS := 200
const SAMPLES := 180


func _times() -> Array[float]:
	return [0.0, 0.7, 3.3, 11.9, 47.0, 123.4, 600.0]


func test_polar_convexity_holds_for_many_seeds_and_times() -> void:
	var worst := INF
	for s in SEEDS:
		var shape := NeuronShape.for_seed(s)
		for t in _times():
			for i in SAMPLES:
				var theta := TAU * float(i) / SAMPLES
				worst = minf(worst, shape.convexity_at(theta, t))
	assert_float(worst).is_greater(0.05)


func test_sampled_polygon_is_convex_for_many_seeds_and_times() -> void:
	for s in SEEDS:
		var shape := NeuronShape.for_seed(s)
		for t in _times():
			var poly := shape.outline(t, 96)
			assert_bool(NeuronShape.is_convex_polygon(poly)).is_true()


func test_radius_stays_within_the_collision_circle_band() -> void:
	var lo := INF
	var hi := -INF
	for s in SEEDS:
		var shape := NeuronShape.for_seed(s)
		for t in _times():
			for i in SAMPLES:
				var r := shape.radius_at(TAU * float(i) / SAMPLES, t)
				lo = minf(lo, r)
				hi = maxf(hi, r)
	assert_float(lo).is_greater_equal(0.82)
	assert_float(hi).is_less_equal(1.05)


func test_shape_is_deterministic_per_seed_and_differs_between_seeds() -> void:
	var a := NeuronShape.for_seed(7)
	var b := NeuronShape.for_seed(7)
	assert_that(a.phase).is_equal(b.phase)
	assert_that(a.amp).is_equal(b.amp)
	assert_that(a.nucleus).is_equal(b.nucleus)
	var c := NeuronShape.for_seed(8)
	assert_that(a.phase).is_not_equal(c.phase)
	var diff := 0.0
	for i in 32:
		var theta := TAU * float(i) / 32.0
		diff += absf(a.radius_at(theta, 0.0) - c.radius_at(theta, 0.0))
	assert_float(diff).is_greater(0.1)


func test_shape_is_not_a_circle_and_is_asymmetric() -> void:
	var shape := NeuronShape.for_seed(3)
	var lo := INF
	var hi := -INF
	for i in 90:
		var r := shape.radius_at(TAU * float(i) / 90.0, 0.0)
		lo = minf(lo, r)
		hi = maxf(hi, r)
	assert_float(hi - lo).is_greater(0.04)
	assert_float(shape.radius_at(0.0, 0.0)).is_not_equal(shape.radius_at(PI, 0.0))


func test_shape_drifts_with_motion_and_stands_still_without() -> void:
	var shape := NeuronShape.for_seed(5)
	assert_float(shape.radius_at(1.0, 0.0)).is_not_equal(shape.radius_at(1.0, 9.0))
	# Reduced motion feeds t = 0 (the view/shader multiply TIME by motion): always the same shape.
	assert_float(shape.radius_at(1.0, 0.0 * 9.0)).is_equal(shape.radius_at(1.0, 0.0 * 33.0))


func test_gdscript_matches_reference_values_of_the_shader_formula() -> void:
	# Hand-checked: mean 0.93, breathing 0.015, four cosine modes (1..4) with phase + drift * t.
	var shape := NeuronShape.new()
	shape.phase = Vector4(0.0, 0.0, 0.0, 0.0)
	shape.amp = Vector4(0.02, 0.0, 0.0, 0.0)
	shape.breath_phase = 0.0
	# t = 0, theta = 0: 0.93 * (1 + 0) * (1 + 0.02)
	assert_float(shape.radius_at(0.0, 0.0)).is_equal_approx(0.93 * 1.02, 1e-6)
	# theta = PI: cos(PI) = -1
	assert_float(shape.radius_at(PI, 0.0)).is_equal_approx(0.93 * 0.98, 1e-6)
	shape.amp = Vector4(0.0, 0.03, 0.0, 0.0)
	# theta = PI / 2, k = 2: cos(PI) = -1
	assert_float(shape.radius_at(PI * 0.5, 0.0)).is_equal_approx(0.93 * 0.97, 1e-6)


func test_shader_declares_the_same_constants() -> void:
	var code: String = NeuronView.NeuronShader.code
	assert_bool(code.contains("SHAPE_MEAN = %s" % _glsl(NeuronShape.MEAN_RADIUS))).is_true()
	assert_bool(code.contains("SHAPE_BREATH = %s" % _glsl(NeuronShape.BREATH))).is_true()
	var d := NeuronShape.DRIFT
	assert_bool(code.contains("SHAPE_DRIFT = vec4(%s, %s, %s, %s)" % [_glsl(d.x), _glsl(d.y), _glsl(d.z), _glsl(d.w)])).is_true()
	assert_bool(code.contains("SHAPE_LOBE_DRIFT = %s" % _glsl(NeuronShape.LOBE_DRIFT))).is_true()
	assert_bool(code.contains("WISP_SWAY = %s" % _glsl(NeuronShape.WISP_SWAY))).is_true()
	assert_bool(code.contains("must stay in sync with NeuronShape")).is_true()


func test_view_pushes_the_shape_uniforms() -> void:
	var level := preload("res://tests/model/level_factory.gd").x_level()
	var model := PuzzleModel.from_level(level)
	var view: NeuronView = auto_free(preload("res://scenes/views/neuron_view.tscn").instantiate())
	view.setup(1, model)
	var shape := NeuronShape.for_seed(1)
	assert_that(view.get_shader_param(&"shape_phase")).is_equal(shape.phase)
	assert_that(view.get_shader_param(&"shape_amp")).is_equal(shape.amp)


func test_lobes_are_three_to_five_and_vary_between_seeds() -> void:
	var counts := {}
	for s in SEEDS:
		var n := NeuronShape.for_seed(s).lobe.x
		assert_float(n).is_between(3.0, 5.0)
		counts[n] = true
	assert_int(counts.size()).is_equal(3)


func test_wisps_are_two_to_four_short_and_seeded() -> void:
	for s in SEEDS:
		var shape := NeuronShape.for_seed(s)
		assert_int(shape.wisp_count()).is_between(2, 4)
		for i in 4:
			assert_float(shape.wisp_len[i]).is_less_equal(0.35)
		var again := NeuronShape.for_seed(s)
		assert_that(shape.wisp_angle).is_equal(again.wisp_angle)
		assert_that(shape.wisp_len).is_equal(again.wisp_len)


func _glsl(v: float) -> String:
	var s := String.num(v, 4)
	return s if s.contains(".") else s + ".0"
