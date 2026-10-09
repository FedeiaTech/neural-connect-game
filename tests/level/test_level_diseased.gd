extends GdUnitTestSuite
## T8.3: the HUD counter ("Diseased: 1/3", only in levels that have them), the controller
## signal, the crack / snap sounds and the planner breaking a diseased dendrite.

const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const LevelScene := preload("res://scenes/level/level.tscn")
const LevelFactory := preload("res://tests/model/level_factory.gd")

var _sandbox: Sandbox
var _level: Level
var _saved_locale := ""
var _saved_motion := false


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_saved_motion = GameState.reduced_motion
	GameState.reduced_motion = true
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)
	GameState.reduced_motion = _saved_motion
	get_tree().paused = false
	_sandbox.exit()
	await await_idle_frame()


## Tangled X (10-13) plus two diseased dendrites 0-1 and 2-3 (rest 100, max 300).
func _data() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(200, 500), Vector2(200, 500)),
		LevelFactory.neuron(1, Vector2(350, 500), Vector2(600, 500)),
		LevelFactory.neuron(2, Vector2(200, 800), Vector2(200, 800)),
		LevelFactory.neuron(3, Vector2(350, 800), Vector2(600, 800)),
		LevelFactory.neuron(10, Vector2(700, 100)),
		LevelFactory.neuron(11, Vector2(1000, 300), Vector2(1000, 100)),
		LevelFactory.neuron(12, Vector2(1000, 100), Vector2(700, 300)),
		LevelFactory.neuron(13, Vector2(700, 300), Vector2(1000, 300)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.diseased_edge(0, 1, 100.0, 300.0),
		LevelFactory.diseased_edge(2, 3, 100.0, 300.0), LevelFactory.edge(10, 11), LevelFactory.edge(12, 13)]
	return LevelFactory.level(neurons, dendrites)


func _break(model: PuzzleModel, id: int, target: Vector2) -> void:
	model.grab(id)
	model.drag_to(target)
	model.release()


func test_counter_is_hidden_without_diseased_dendrites() -> void:
	_level.load_level(LevelFactory.x_level())
	assert_bool(_level.get_hud().is_diseased_counter_visible()).is_false()


func test_counter_shows_progress() -> void:
	_level.load_level(_data())
	var hud := _level.get_hud()
	assert_bool(hud.is_diseased_counter_visible()).is_true()
	assert_str(hud.get_diseased_counter_text()).is_equal("Diseased: 0/2")
	_break(_level.get_controller().get_model(), 1, Vector2(600, 500))
	assert_str(hud.get_diseased_counter_text()).is_equal("Diseased: 1/2")
	_break(_level.get_controller().get_model(), 3, Vector2(600, 800))
	assert_str(hud.get_diseased_counter_text()).is_equal("Diseased: 2/2")


func test_counter_is_translated() -> void:
	TranslationServer.set_locale("es")
	_level.load_level(_data())
	assert_str(_level.get_hud().get_diseased_counter_text()).is_equal("Dendritas enfermas: 0/2")


func test_restart_resets_the_counter() -> void:
	_level.load_level(_data())
	_break(_level.get_controller().get_model(), 1, Vector2(600, 500))
	_level.get_controller().restart()
	assert_str(_level.get_hud().get_diseased_counter_text()).is_equal("Diseased: 0/2")


func test_controller_reports_diseased_progress() -> void:
	var recorder := SignalRecorder.new()
	recorder.watch(_level.get_controller(), [&"diseased_progress_changed"])
	_level.load_level(_data())
	assert_array(recorder.last_args(&"diseased_progress_changed")).is_equal([0, 2])
	_break(_level.get_controller().get_model(), 1, Vector2(600, 500))
	assert_array(recorder.last_args(&"diseased_progress_changed")).is_equal([1, 2])


func test_breaking_never_restarts_the_level() -> void:
	_level.load_level(_data())
	var controller := _level.get_controller()
	var recorder := SignalRecorder.new()
	recorder.watch(controller, [&"level_lost", &"level_restart_requested"])
	_break(controller.get_model(), 1, Vector2(600, 500))
	assert_int(controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_int(recorder.count(&"level_lost")).is_equal(0)
	assert_int(recorder.count(&"level_restart_requested")).is_equal(0)


# --- Audio ---------------------------------------------------------------------------

func _director() -> AudioDirector:
	var director: AudioDirector = auto_free(AudioDirector.new())
	add_child(director)
	_level.load_level(_data())
	director.bind_level(_level)
	return director


func test_crack_mapping_rises_with_strain() -> void:
	assert_bool(AudioDirector.is_diseased_audible(0.1)).is_false()
	assert_bool(AudioDirector.is_diseased_audible(0.8)).is_true()
	assert_float(AudioDirector.diseased_pitch(1.0)).is_greater(AudioDirector.diseased_pitch(0.4))
	assert_float(AudioDirector.diseased_volume_db(1.0)).is_greater(AudioDirector.diseased_volume_db(0.5))


func test_crack_loop_follows_the_strain_and_stops_on_release() -> void:
	var director := _director()
	var model := _level.get_controller().get_model()
	model.grab(1)
	model.drag_to(Vector2(470, 500))
	assert_bool(director.is_diseased_crack_playing()).is_true()
	# It is not the tension tone.
	assert_bool(director.is_tension_playing()).is_false()
	_level.get_input_controller().grab_ended.emit(1)
	assert_bool(director.is_diseased_crack_playing()).is_false()


func test_snap_sound_and_crack_stops_when_it_breaks() -> void:
	var director := _director()
	var recorder := SignalRecorder.new()
	recorder.watch(director, [&"sound_played"])
	var model := _level.get_controller().get_model()
	model.grab(1)
	model.drag_to(Vector2(470, 500))
	model.drag_to(Vector2(600, 500))
	var names: Array[StringName] = []
	for args in recorder.args_of(&"sound_played"):
		names.append(args[0])
	assert_bool(names.has(&"diseased_snap")).is_true()
	assert_bool(director.is_diseased_crack_playing()).is_false()
