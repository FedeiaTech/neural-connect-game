extends GdUnitTestSuite
## T8.2: contamination reaches the HUD through the LevelController (hint text, en/es), and the
## audio director raises / clears the toxic alarm.

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


## Receptor 0 (500, 500), normal neuron 1, toxic neuron 2 (500, 750) and a tangled X (10-13).
func _data() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(500, 500), 120.0, 1),
		LevelFactory.neuron(1, Vector2(610, 500)),
		LevelFactory.toxic(2, Vector2(500, 750)),
		LevelFactory.neuron(10, Vector2(100, 100)),
		LevelFactory.neuron(11, Vector2(400, 300), Vector2(400, 100)),
		LevelFactory.neuron(12, Vector2(400, 100), Vector2(100, 300)),
		LevelFactory.neuron(13, Vector2(100, 300), Vector2(400, 300)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(10, 11), LevelFactory.edge(12, 13)]
	return LevelFactory.level(neurons, dendrites)


func _toxic_in(model: PuzzleModel) -> void:
	model.grab(2)
	model.drag_to(Vector2(500, 620))


func test_controller_reports_contamination_changes() -> void:
	_level.load_level(_data())
	var recorder := SignalRecorder.new()
	recorder.watch(_level.get_controller(), [&"contamination_changed"])
	var model := _level.get_controller().get_model()
	_toxic_in(model)
	assert_array(recorder.last_args(&"contamination_changed")).is_equal([true])
	model.drag_to(Vector2(500, 800))
	assert_array(recorder.last_args(&"contamination_changed")).is_equal([false])


func test_hud_shows_the_hint_only_while_contaminated() -> void:
	_level.load_level(_data())
	var hud := _level.get_hud()
	assert_bool(hud.is_contamination_hint_visible()).is_false()
	_toxic_in(_level.get_controller().get_model())
	assert_bool(hud.is_contamination_hint_visible()).is_true()
	assert_str(hud.get_contamination_hint_text()).is_equal("Contaminated link: move the yellow neuron away")
	_level.get_controller().get_model().drag_to(Vector2(500, 800))
	assert_bool(hud.is_contamination_hint_visible()).is_false()


func test_hud_hint_is_translated() -> void:
	TranslationServer.set_locale("es")
	_level.load_level(_data())
	_toxic_in(_level.get_controller().get_model())
	assert_str(_level.get_hud().get_contamination_hint_text()).is_equal("Enlace contaminado: aleja la neurona amarilla")


func test_restart_clears_the_hint() -> void:
	_level.load_level(_data())
	_toxic_in(_level.get_controller().get_model())
	_level.get_controller().restart()
	assert_bool(_level.get_hud().is_contamination_hint_visible()).is_false()


func test_toxic_alarm_plays_while_contaminated_and_a_chime_clears_it() -> void:
	var director: AudioDirector = auto_free(AudioDirector.new())
	add_child(director)
	var recorder := SignalRecorder.new()
	recorder.watch(director, [&"sound_played"])
	_level.load_level(_data())
	director.bind_level(_level)
	var model := _level.get_controller().get_model()
	assert_bool(director.is_toxic_alarm_playing()).is_false()
	_toxic_in(model)
	assert_bool(director.is_toxic_alarm_playing()).is_true()
	# The lethal alarm is a different voice.
	assert_bool(director.is_alarm_playing()).is_false()
	model.drag_to(Vector2(500, 800))
	assert_bool(director.is_toxic_alarm_playing()).is_false()
	var names: Array[StringName] = []
	for args in recorder.args_of(&"sound_played"):
		names.append(args[0])
	assert_bool(names.has(&"toxic_clear")).is_true()


func test_toxic_alarm_survives_release_and_stops_on_restart() -> void:
	var director: AudioDirector = auto_free(AudioDirector.new())
	add_child(director)
	_level.load_level(_data())
	director.bind_level(_level)
	_toxic_in(_level.get_controller().get_model())
	_level.get_input_controller().grab_ended.emit(2)
	assert_bool(director.is_toxic_alarm_playing()).is_true()
	_level.get_controller().restart()
	assert_bool(director.is_toxic_alarm_playing()).is_false()
