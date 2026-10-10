extends GdUnitTestSuite
## Multipolar neuron body (NeuronMorphology): deterministic per seed, bounded around the collision
## circle, tapered processes, one axon, per-kind looks, link-oriented dendrites, static without
## motion, and in sync with the shaders.

const SEEDS := 120
const Kind := NeuronMorphology.Kind
const NeuronScene := preload("res://scenes/views/neuron_view.tscn")
const LevelFactory := preload("res://tests/model/level_factory.gd")


func _kinds() -> Array:
	return [Kind.NORMAL, Kind.FIXED, Kind.RECEPTOR, Kind.TOXIC]


func _angle_gap(a: float, b: float) -> float:
	return absf(atan2(sin(a - b), cos(a - b)))


func test_same_seed_gives_the_same_neuron_and_other_seeds_differ() -> void:
	var a := NeuronMorphology.generate(7, Kind.NORMAL)
	var b := NeuronMorphology.generate(7, Kind.NORMAL)
	assert_int(a.processes.size()).is_equal(b.processes.size())
	assert_array(a.corners).is_equal(b.corners)
	assert_that(a.nucleus).is_equal(b.nucleus)
	for i in a.processes.size():
		assert_array(a.processes[i].points).is_equal(b.processes[i].points)
		assert_array(a.processes[i].widths).is_equal(b.processes[i].widths)
	var c := NeuronMorphology.generate(8, Kind.NORMAL)
	assert_array(a.corners).is_not_equal(c.corners)
	assert_int(a.build_mesh().get_surface_count()).is_equal(1)


func test_primary_dendrite_count_matches_the_kind() -> void:
	var ranges := {Kind.NORMAL: [4, 6], Kind.FIXED: [4, 5], Kind.RECEPTOR: [3, 4], Kind.TOXIC: [5, 6]}
	for kind in _kinds():
		for s in SEEDS:
			var m := NeuronMorphology.generate(s, kind)
			assert_int(m.dendrite_angles().size()).is_equal(m.arm_count)
			assert_int(m.arm_count).is_between(ranges[kind][0], ranges[kind][1])
			assert_bool(m.has_axon).is_true()
			assert_object(m.get_axon()).is_not_null()


func test_process_reach_is_bounded() -> void:
	var farthest := 0.0
	for kind in _kinds():
		for s in SEEDS:
			var m := NeuronMorphology.generate(s, kind)
			farthest = maxf(farthest, m.max_reach())
	assert_float(farthest).is_less_equal(NeuronMorphology.MAX_REACH + 0.0001)
	assert_float(farthest).is_greater(1.0)


func test_soma_stays_compact_for_every_time_and_angle() -> void:
	for kind in _kinds():
		var lo := INF
		var hi := -INF
		for s in SEEDS:
			var m := NeuronMorphology.generate(s, kind)
			for t in [0.0, 2.7, 40.0]:
				for i in 90:
					var r := m.soma_radius_at(TAU * float(i) / 90.0, t)
					lo = minf(lo, r)
					hi = maxf(hi, r)
		assert_float(lo).is_greater(0.4)
		assert_float(hi).is_less(0.95)


func test_processes_taper_towards_the_tips() -> void:
	for s in SEEDS:
		var m := NeuronMorphology.generate(s, Kind.NORMAL)
		for p in m.processes:
			for k in range(1, p.widths.size()):
				assert_float(p.widths[k]).is_less_equal(p.widths[k - 1] + 0.00001)
			assert_float(p.widths[p.widths.size() - 1]).is_less(p.widths[0])
			if p.role == NeuronMorphology.Role.DENDRITE and p.is_root:
				assert_float(p.widths[0]).is_greater(0.2)
	# The axon is much thinner than a dendrite root.
	var m := NeuronMorphology.generate(3, Kind.NORMAL)
	assert_float(m.get_axon().widths[0]).is_less(0.15)


func test_kinds_keep_their_identity() -> void:
	var sums := {}
	for kind in _kinds():
		var width := 0.0
		var length := 0.0
		var soma := 0.0
		for s in SEEDS:
			var m := NeuronMorphology.generate(s, kind)
			soma += m.soma_radius
			for p in m.processes:
				if p.is_root:
					width += p.widths[0]
					length += p.points[p.points.size() - 1].length()
		sums[kind] = {"w": width, "l": length, "s": soma}
	# Fixed: stockier soma, thicker and shorter arms than normal.
	assert_float(sums[Kind.FIXED].s).is_greater(sums[Kind.NORMAL].s)
	assert_float(sums[Kind.FIXED].w / sums[Kind.FIXED].l).is_greater(sums[Kind.NORMAL].w / sums[Kind.NORMAL].l)
	# Toxic: sharper soma points.
	assert_float(NeuronMorphology.generate(1, Kind.TOXIC).corner_width) \
		.is_less(NeuronMorphology.generate(1, Kind.NORMAL).corner_width)


func test_dendrites_and_axon_grow_towards_linked_neighbours() -> void:
	var links := PackedFloat32Array([0.5, 2.0, 4.0, 5.5])
	for s in 20:
		var m := NeuronMorphology.generate(s, Kind.NORMAL, links)
		assert_float(_angle_gap(m.get_axon().points[0].angle(), 0.5)).is_less(0.01)
		var angles := m.dendrite_angles()
		for target in [2.0, 4.0, 5.5]:
			var best := INF
			for a in angles:
				best = minf(best, _angle_gap(a, target))
			assert_float(best).is_less(0.01)


func test_free_processes_spread_around_the_soma() -> void:
	for s in SEEDS:
		var m := NeuronMorphology.generate(s, Kind.NORMAL)
		var sorted: Array[float] = []
		for a in m.corners:
			sorted.append(a)
		sorted.sort()
		var largest := 0.0
		for i in sorted.size():
			var next: float = sorted[(i + 1) % sorted.size()] + (TAU if i == sorted.size() - 1 else 0.0)
			largest = maxf(largest, next - sorted[i])
		assert_float(largest).is_less(TAU * 0.6)


func test_soma_is_static_without_motion_and_breathes_with_it() -> void:
	var m := NeuronMorphology.generate(5, Kind.NORMAL)
	assert_float(m.soma_radius_at(1.0, 0.0)).is_equal(m.soma_radius_at(1.0, 0.0 * 50.0))
	assert_float(m.soma_radius_at(1.0, 0.0)).is_not_equal(m.soma_radius_at(1.0, 1.4))


func test_soma_formula_matches_hand_computed_reference() -> void:
	var m := NeuronMorphology.new()
	m.soma_radius = 0.6
	m.corner_amp = 0.3
	m.corner_width = 0.5
	m.corners = PackedFloat32Array([0.0])
	m.breath_phase = 0.0
	# At the corner: 0.6 * (0.86 + 0.3 * 1.0); opposite: exp(-PI^2 / 0.5) is about 0.
	assert_float(m.soma_radius_at(0.0, 0.0)).is_equal_approx(0.6 * 1.16, 1e-5)
	assert_float(m.soma_radius_at(PI, 0.0)).is_equal_approx(0.6 * 0.86, 1e-4)


func test_shaders_declare_the_same_constants() -> void:
	var soma: String = NeuronView.NeuronShader.code
	assert_bool(soma.contains("SOMA_BASE = %s" % _glsl(NeuronMorphology.SOMA_BASE))).is_true()
	assert_bool(soma.contains("CORNER_CAP = %s" % _glsl(NeuronMorphology.CORNER_CAP))).is_true()
	assert_bool(soma.contains("SOMA_BREATH = %s" % _glsl(NeuronMorphology.SOMA_BREATH))).is_true()
	assert_bool(soma.contains("SOMA_BREATH_SPEED = %s" % _glsl(NeuronMorphology.SOMA_BREATH_SPEED))).is_true()
	assert_bool(soma.contains("must stay in sync with NeuronMorphology")).is_true()
	assert_bool(soma.contains("SWAY = %s" % _glsl(NeuronMorphology.SWAY))).is_true()


func test_view_builds_the_arms_mesh_and_orients_dendrites_to_links() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view: NeuronView = auto_free(NeuronScene.instantiate())
	view.setup(0, model)
	assert_object(view.get_arms_mesh()).is_not_null()
	assert_int(view.get_arms_mesh().get_surface_count()).is_equal(1)
	assert_int(view.get_shader_param(&"corner_count")).is_equal(view.get_morphology().corners.size())
	var here := model.get_neuron_position(0)
	var targets: Array[float] = []
	for edge in model.get_edge_count():
		var ends := model.get_edge_endpoints(edge)
		if ends.x == 0 or ends.y == 0:
			var other := ends.y if ends.x == 0 else ends.x
			targets.append((model.get_neuron_position(other) - here).angle())
	assert_bool(targets.is_empty()).is_false()
	for target in targets:
		var best := INF
		for a in view.get_morphology().corners:
			best = minf(best, _angle_gap(a, target))
		assert_float(best).is_less(0.01)


func test_grabbing_scales_the_mesh_with_the_soma() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view: NeuronView = auto_free(NeuronScene.instantiate())
	view.setup(0, model)
	assert_float(view.get_shader_param(&"mesh_scale")).is_equal(view.get_radius())
	view.set_grabbed(true)
	view._process(0.016)
	assert_float(view.get_shader_param(&"mesh_scale")).is_greater_equal(view.get_radius())


func _glsl(v: float) -> String:
	var s := String.num(v, 4)
	return s if s.contains(".") else s + ".0"
