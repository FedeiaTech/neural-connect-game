extends GdUnitTestSuite
## T4.1-T4.4: pure visual parameters (tension look, motion switch, membrane offsets).

var _saved_reduced_motion := false
var _saved_low_memory := false


func before_test() -> void:
	_saved_reduced_motion = GameState.reduced_motion
	_saved_low_memory = GameState.low_memory_mode


func after_test() -> void:
	GameState.reduced_motion = _saved_reduced_motion
	GameState.low_memory_mode = _saved_low_memory
	VisualTuning.set_low_quality_override(-1)


func test_low_memory_mode_forces_low_quality_unless_overridden() -> void:
	GameState.low_memory_mode = true
	assert_bool(VisualTuning.is_low_memory()).is_true()
	assert_bool(VisualTuning.is_low_quality()).is_true()
	VisualTuning.set_low_quality_override(0)
	assert_bool(VisualTuning.is_low_quality()).is_false()
	GameState.low_memory_mode = false
	VisualTuning.set_low_quality_override(-1)
	assert_bool(VisualTuning.is_low_memory()).is_false()


func test_burst_amount_shrinks_with_quality_and_memory_modes() -> void:
	VisualTuning.set_low_quality_override(0)
	GameState.low_memory_mode = false
	assert_int(VisualTuning.burst_amount(64)).is_equal(64)
	VisualTuning.set_low_quality_override(1)
	assert_int(VisualTuning.burst_amount(64)).is_equal(32)
	assert_int(VisualTuning.burst_amount(8)).is_equal(8)
	GameState.low_memory_mode = true
	assert_int(VisualTuning.burst_amount(64)).is_equal(16)
	assert_int(VisualTuning.burst_amount(8)).is_equal(6)


func test_low_quality_is_automatic_off_android_and_can_be_forced() -> void:
	assert_bool(VisualTuning.is_low_quality()).is_equal(OS.has_feature("android"))
	VisualTuning.set_low_quality_override(1)
	assert_bool(VisualTuning.is_low_quality()).is_true()
	VisualTuning.set_low_quality_override(0)
	assert_bool(VisualTuning.is_low_quality()).is_false()


func test_low_quality_neuron_turns_sparkle_off_and_flags_the_shader() -> void:
	VisualTuning.set_low_quality_override(1)
	var model := PuzzleModel.from_level(preload("res://tests/model/level_factory.gd").x_level())
	var view: NeuronView = auto_free(preload("res://scenes/views/neuron_view.tscn").instantiate())
	view.setup(0, model)
	var material := view.material as ShaderMaterial
	assert_float(material.get_shader_parameter(&"low_quality")).is_equal(1.0)
	assert_float(material.get_shader_parameter(&"sparkle")).is_equal(0.0)


func test_motion_scale_follows_reduced_motion() -> void:
	GameState.reduced_motion = false
	assert_bool(VisualTuning.is_motion_enabled()).is_true()
	assert_float(VisualTuning.motion_scale()).is_equal(1.0)
	GameState.reduced_motion = true
	assert_bool(VisualTuning.is_motion_enabled()).is_false()
	assert_float(VisualTuning.motion_scale()).is_equal(0.0)


func test_tension_width_thins_from_normal_to_minimum() -> void:
	assert_float(VisualTuning.tension_width(0.0)).is_equal(DendriteView.WIDTH)
	assert_float(VisualTuning.tension_width(1.0)).is_equal(DendriteView.MIN_TENSION_WIDTH)
	assert_float(VisualTuning.tension_width(0.5)) \
		.is_equal_approx(lerpf(DendriteView.WIDTH, DendriteView.MIN_TENSION_WIDTH, 0.5), 0.0001)
	assert_float(VisualTuning.tension_width(7.0)).is_equal(DendriteView.MIN_TENSION_WIDTH)


func test_tension_tremble_and_flicker_only_rise_near_the_limit() -> void:
	for ratio in [0.0, 0.3, VisualTuning.TENSION_WARNING_START]:
		assert_float(VisualTuning.tension_tremble(ratio)).is_equal(0.0)
		assert_float(VisualTuning.tension_flicker(ratio)).is_equal(0.0)
	var previous_tremble := 0.0
	var previous_flicker := 0.0
	for step in range(1, 11):
		var ratio := lerpf(VisualTuning.TENSION_WARNING_START, 1.0, step / 10.0)
		var tremble := VisualTuning.tension_tremble(ratio)
		var flicker := VisualTuning.tension_flicker(ratio)
		assert_float(tremble).is_greater(previous_tremble)
		assert_float(flicker).is_greater(previous_flicker)
		previous_tremble = tremble
		previous_flicker = flicker
	assert_float(VisualTuning.tension_tremble(1.0)).is_equal_approx(VisualTuning.MAX_TREMBLE, 0.0001)
	assert_float(VisualTuning.tension_flicker(1.0)).is_equal_approx(VisualTuning.MAX_FLICKER, 0.0001)


func test_neuron_phases_differ_and_stay_in_range() -> void:
	var phases := {}
	for id in 12:
		var phase := VisualTuning.phase_for(id)
		assert_float(phase).is_between(0.0, TAU)
		phases[snappedf(phase, 0.001)] = true
	assert_int(phases.size()).is_equal(12)


func test_approach_moves_towards_target_without_overshoot() -> void:
	assert_float(VisualTuning.approach(0.0, 1.0, 4.0, 0.1)).is_equal_approx(0.4, 0.0001)
	assert_float(VisualTuning.approach(0.9, 1.0, 4.0, 0.1)).is_equal(1.0)
	assert_float(VisualTuning.approach(1.0, 0.0, 4.0, 1.0)).is_equal(0.0)
