extends GdUnitTestSuite
## T4.3: reusable background (black base, drifting spores, vignette) behind everything.

const BackgroundScene := preload("res://scenes/views/background.tscn")

var _saved_reduced_motion := false
var _saved_low_memory := false


func before_test() -> void:
	_saved_reduced_motion = GameState.reduced_motion
	_saved_low_memory = GameState.low_memory_mode
	GameState.low_memory_mode = false


func after_test() -> void:
	GameState.reduced_motion = _saved_reduced_motion
	GameState.low_memory_mode = _saved_low_memory
	VisualTuning.set_low_quality_override(-1)


func test_low_memory_mode_hides_and_restores_the_spores_live() -> void:
	VisualTuning.set_low_quality_override(0)
	var background := _background()
	assert_bool(background.get_spores().visible).is_true()
	GameState.low_memory_mode = true
	VisualTuning.set_low_quality_override(-1)
	GameState.settings_changed.emit()
	assert_bool(background.get_spores().visible).is_false()
	assert_bool(background.get_spores().emitting).is_false()
	GameState.low_memory_mode = false
	VisualTuning.set_low_quality_override(0)
	GameState.settings_changed.emit()
	assert_bool(background.get_spores().visible).is_true()
	assert_bool(background.get_spores().emitting).is_true()


func test_low_memory_mode_draws_a_plain_black_background_and_restores_the_shaders_live() -> void:
	VisualTuning.set_low_quality_override(0)
	var background := _background()
	var base: ColorRect = background.get_node(^"Base")
	assert_object(base.material).is_instanceof(ShaderMaterial)
	assert_bool(background.get_vignette().visible).is_true()
	GameState.low_memory_mode = true
	GameState.settings_changed.emit()
	assert_object(base.material).is_null()
	assert_bool(background.get_vignette().visible).is_false()
	assert_object(background.get_vignette().material).is_instanceof(ShaderMaterial)
	GameState.low_memory_mode = false
	GameState.settings_changed.emit()
	assert_object(base.material).is_instanceof(ShaderMaterial)
	assert_bool(background.get_vignette().visible).is_true()


func _background() -> BackgroundView:
	var background: BackgroundView = auto_free(BackgroundScene.instantiate())
	add_child(background)
	return background


func test_draws_behind_the_default_canvas() -> void:
	var background := _background()
	assert_int(background.layer).is_less(0)
	assert_object(background.get_spores()).is_instanceof(CPUParticles2D)
	assert_object(background.get_vignette().material).is_instanceof(ShaderMaterial)


func test_spores_are_few_faint_and_cover_the_viewport() -> void:
	var background := _background()
	var spores := background.get_spores()
	assert_int(spores.amount).is_less_equal(60)
	assert_float(spores.color.a).is_less_equal(0.25)
	var size := background.get_viewport().get_visible_rect().size
	assert_vector(spores.position).is_equal(size * 0.5)
	assert_vector(spores.emission_rect_extents).is_equal(size * 0.5)


func test_reduced_motion_freezes_the_spores() -> void:
	GameState.reduced_motion = false
	var background := _background()
	assert_float(background.get_spores().speed_scale).is_greater(0.0)
	GameState.reduced_motion = true
	GameState.settings_changed.emit()
	assert_float(background.get_spores().speed_scale).is_equal(0.0)
	GameState.reduced_motion = false
	GameState.settings_changed.emit()
	assert_float(background.get_spores().speed_scale).is_greater(0.0)


func test_level_uses_the_background_scene() -> void:
	var level: Node = auto_free(preload("res://scenes/level/level.tscn").instantiate())
	assert_object(level.get_node(^"Background")).is_instanceof(BackgroundView)
