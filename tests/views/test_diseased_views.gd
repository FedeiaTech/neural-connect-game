extends GdUnitTestSuite
## T8.3: diseased dendrite look (dark orange ember line that thins, trembles and cracks near the
## limit), its snap effect and the ember sparks. Reduced motion keeps the colors and the snap flash
## but stops the sparks, the tremble and the burst.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const DendriteScene := preload("res://scenes/views/dendrite_view.tscn")

var _saved_motion := false


func before_test() -> void:
	_saved_motion = GameState.reduced_motion
	GameState.reduced_motion = false


func after_test() -> void:
	GameState.reduced_motion = _saved_motion


## Edge 0: DISEASED 0-1 (rest 100, max 300), start length 150. Edge 1: NORMAL 2-3.
func _model() -> PuzzleModel:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(200, 500)),
		LevelFactory.neuron(1, Vector2(350, 500)),
		LevelFactory.neuron(2, Vector2(200, 200)),
		LevelFactory.neuron(3, Vector2(500, 200)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(0, 1, 100.0, 300.0), LevelFactory.edge(2, 3)]
	return PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))


func _view(edge_id: int, model: PuzzleModel) -> DendriteView:
	var view: DendriteView = auto_free(DendriteScene.instantiate())
	view.setup(edge_id, model, true)
	return view


func _layer(model: PuzzleModel) -> DiseasedView:
	var layer: DiseasedView = auto_free(DiseasedView.new())
	add_child(layer)
	layer.setup(model)
	return layer


func test_diseased_dendrite_is_dark_orange() -> void:
	var model := _model()
	var view := _view(0, model)
	assert_bool(view.is_diseased()).is_true()
	assert_object(view.get_base_color()).is_equal(Palette.DISEASED.lerp(Palette.DISEASED_HOT, 0.25 * 0.25))
	assert_bool(_view(1, model).is_diseased()).is_false()


## Dark orange (about 25 degrees of hue) against the bright red of crossing dendrites (about 8).
func test_diseased_color_is_not_the_crossing_red() -> void:
	assert_float(absf(Palette.DISEASED.h - Palette.CROSSING_DENDRITE.h)).is_greater(0.04)
	assert_float(Palette.DISEASED.v).is_less(Palette.CROSSING_DENDRITE.v + 0.001)


func test_strain_thins_and_heats_the_line() -> void:
	var model := _model()
	var view := _view(0, model)
	var calm_width := view.get_line_width()
	var calm_color := view.get_base_color()
	model.grab(1)
	model.drag_to(Vector2(480, 500))
	assert_float(view.get_line_width()).is_less(calm_width)
	assert_float(view.get_base_color().g).is_greater(calm_color.g)


func test_tremble_flicker_and_cracks_grow_near_the_limit() -> void:
	var model := _model()
	var view := _view(0, model)
	assert_float(view.get_shader_param(&"crack")).is_equal(0.0)
	assert_float(view.get_shader_param(&"tremble_px")).is_equal(0.0)
	model.grab(1)
	model.drag_to(Vector2(490, 500))
	assert_float(view.get_shader_param(&"crack")).is_greater(0.5)
	assert_float(view.get_shader_param(&"tremble_px")).is_greater(0.0)
	assert_float(view.get_shader_param(&"flicker")).is_greater(0.0)


func test_a_crossing_diseased_dendrite_keeps_its_color() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(200, 500)),
		LevelFactory.neuron(1, Vector2(350, 500)),
		LevelFactory.neuron(2, Vector2(275, 400)),
		LevelFactory.neuron(3, Vector2(275, 600)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(0, 1, 100.0, 300.0), LevelFactory.edge(2, 3)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	var view := _view(0, model)
	assert_object(view.get_crossing_color()).is_equal(view.get_base_color())


func test_the_view_hides_when_the_dendrite_snaps() -> void:
	var model := _model()
	var view := _view(0, model)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_bool(view.is_broken()).is_true()
	assert_bool(view.visible).is_false()
	assert_bool(_view(1, model).is_broken()).is_false()


func test_ember_sparks_only_while_strained_and_with_motion() -> void:
	var model := _model()
	var layer := _layer(model)
	layer.tick(0.5)
	assert_int(layer.get_spark_count()).is_equal(0)
	model.grab(1)
	model.drag_to(Vector2(480, 500))
	for i in 10:
		layer.tick(0.1)
	assert_int(layer.get_spark_count()).is_greater(0)
	GameState.reduced_motion = true
	layer.clear_sparks()
	for i in 10:
		layer.tick(0.1)
	assert_int(layer.get_spark_count()).is_equal(0)


func test_snap_effect_plays_and_ends() -> void:
	var model := _model()
	var layer := _layer(model)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_int(layer.get_snap_count()).is_equal(1)
	assert_bool(layer.is_snapping()).is_true()
	layer.tick(DiseasedView.SNAP_TIME + 0.1)
	assert_bool(layer.is_snapping()).is_false()


func test_reduced_motion_snap_has_no_sparks() -> void:
	GameState.reduced_motion = true
	var model := _model()
	var layer := _layer(model)
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_int(layer.get_snap_count()).is_equal(1)
	assert_int(layer.get_spark_count()).is_equal(0)


func test_level_fx_bursts_and_shakes_on_a_snap() -> void:
	var model := _model()
	var fx: LevelFx = auto_free(LevelFx.new())
	var target: Node2D = auto_free(Node2D.new())
	add_child(target)
	add_child(fx)
	fx.shake_target = target
	fx.setup(model, {}, [], [])
	model.grab(1)
	model.drag_to(Vector2(600, 500))
	assert_int(fx.get_burst_count()).is_equal(1)
	assert_bool(fx.is_shaking()).is_true()


func test_completion_wave_skips_a_broken_dendrite() -> void:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(250, 500)),
		LevelFactory.neuron(1, Vector2(400, 500)),
		LevelFactory.neuron(2, Vector2(600, 500)),
		LevelFactory.neuron(3, Vector2(800, 500)),
		LevelFactory.neuron(4, Vector2(1000, 500)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(1, 0, 100.0, 300.0),
		LevelFactory.edge(1, 2), LevelFactory.edge(2, 3), LevelFactory.edge(3, 4)]
	var model := PuzzleModel.from_level(LevelFactory.level(neurons, dendrites))
	var intact := NetworkWave.schedule(model, 1)
	assert_float(intact["neurons"][0]).is_equal_approx(VisualTuning.WAVE_STEP, 0.0001)
	model.grab(0)
	model.drag_to(Vector2(50, 500))
	# Neuron 0 is no longer reachable through the snapped dendrite: it lights up after the rest.
	var broken := NetworkWave.schedule(model, 1)
	assert_float(broken["neurons"][0]).is_equal_approx(4.0 * VisualTuning.WAVE_STEP, 0.0001)
