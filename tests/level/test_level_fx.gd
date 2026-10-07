extends GdUnitTestSuite
## T4.4: completion wave before the summary, tension break flash/burst/shake, reduced motion.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const LevelScene := preload("res://scenes/level/level.tscn")
const M02_PATH := "res://data/levels/m02.tres"

var _level: Level
var _saved_reduced_motion := false


func before_test() -> void:
	_saved_reduced_motion = GameState.reduced_motion
	GameState.reduced_motion = false
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)


func after_test() -> void:
	GameState.reduced_motion = _saved_reduced_motion
	get_tree().paused = false


## Edge 0: TENSION 0-1 (rest 100, max 300). Edge 1: NORMAL 2-3.
func _tension_level() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(200, 500)),
		LevelFactory.neuron(2, Vector2(100, 100)),
		LevelFactory.neuron(3, Vector2(300, 100)),
	]
	var dendrites: Array[DendriteData] = [
		LevelFactory.tension_edge(0, 1, 100.0, 300.0),
		LevelFactory.edge(2, 3),
	]
	return LevelFactory.level(neurons, dendrites)


func _fx() -> LevelFx:
	return _level.get_node(^"Playfield/Fx")


func _result() -> LevelResult:
	return LevelResult.create(3, 20.0, 8, 90.0)


func test_fx_layer_sits_above_the_neurons() -> void:
	var fx := _fx()
	assert_object(fx).is_not_null()
	assert_int(fx.get_index()).is_greater(_level.get_node(^"Playfield/Neurons").get_index())


func test_summary_waits_for_the_completion_wave() -> void:
	_level.load_level(load(M02_PATH))
	_level.get_controller().level_completed.emit(_result())
	assert_bool(_level.get_hud().is_completion_visible()).is_false()
	assert_bool(_fx().is_wave_running()).is_true()
	await await_millis(int(_fx().get_last_wave_duration() * 1000.0) + 250)
	assert_bool(_level.get_hud().is_completion_visible()).is_true()


func test_restart_during_the_wave_cancels_the_summary() -> void:
	_level.load_level(load(M02_PATH))
	_level.get_controller().level_completed.emit(_result())
	_level.get_hud().get_restart_button().pressed.emit()
	await await_millis(int(_fx().get_last_wave_duration() * 1000.0) + 250)
	assert_bool(_level.get_hud().is_completion_visible()).is_false()


func test_reduced_motion_shows_the_summary_at_once() -> void:
	GameState.reduced_motion = true
	_level.load_level(load(M02_PATH))
	_level.get_controller().level_completed.emit(_result())
	assert_bool(_level.get_hud().is_completion_visible()).is_true()


func test_next_mission_offer_survives_the_delayed_summary() -> void:
	_level.load_level(load(M02_PATH))
	_level.get_controller().level_completed.emit(_result())
	_level.set_next_mission_available(true)
	await await_millis(int(_fx().get_last_wave_duration() * 1000.0) + 250)
	assert_bool(_level.get_hud().get_next_button().visible).is_true()


func test_tension_break_flashes_bursts_and_shakes() -> void:
	_level.load_level(_tension_level())
	var model := _level.get_controller().get_model()
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	assert_bool(model.is_broken()).is_true()
	var fx := _fx()
	assert_bool(fx.is_flashing()).is_true()
	assert_int(fx.get_burst_count()).is_equal(1)
	assert_bool(fx.is_shaking()).is_true()
	await await_millis(int(VisualTuning.SHAKE_TIME * 1000.0) + 150)
	assert_bool(fx.is_shaking()).is_false()
	assert_vector(_level.position).is_equal(Vector2.ZERO)


func test_reduced_motion_break_only_flashes() -> void:
	GameState.reduced_motion = true
	_level.load_level(_tension_level())
	var model := _level.get_controller().get_model()
	model.grab(1)
	model.drag_to(Vector2(450, 500))
	var fx := _fx()
	assert_bool(fx.is_flashing()).is_true()
	assert_int(fx.get_burst_count()).is_equal(0)
	assert_bool(fx.is_shaking()).is_false()


func test_completion_wave_starts_at_the_last_moved_neuron() -> void:
	_level.load_level(load(M02_PATH))
	var model := _level.get_controller().get_model()
	var id: int = model.get_neuron_ids()[2]
	model.grab(id)
	model.drag_to(model.get_neuron_position(id) + Vector2(5, 0))
	model.release()
	assert_int(_fx().get_last_moved_id()).is_equal(id)
