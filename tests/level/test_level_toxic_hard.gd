extends GdUnitTestSuite
## T8.6: HARD toxic through the controller, audio and effects: the loss reason is TOXIC_OVERLOAD,
## the level restarts like a lethal-wall overload, the sound is toxic_overload (not explode) and
## the blast is yellow.

const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const LevelScene := preload("res://scenes/level/level.tscn")
const LevelFactory := preload("res://tests/model/level_factory.gd")

var _sandbox: Sandbox
var _level: Level


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)


func after_test() -> void:
	get_tree().paused = false
	_sandbox.exit()
	await await_idle_frame()


func _data(hard: bool) -> LevelData:
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
	var data := LevelFactory.level(neurons, dendrites)
	data.hard_toxic = hard
	return data


func _overload(model: PuzzleModel) -> void:
	model.grab(2)
	model.drag_to(Vector2(500, 620))


func test_the_loss_reason_is_toxic_overload_and_the_level_restarts() -> void:
	_level.load_level(_data(true))
	var controller := _level.get_controller()
	var recorder := SignalRecorder.new()
	recorder.watch(controller, [&"level_lost", &"level_restart_requested"])
	_overload(controller.get_model())
	assert_int(controller.get_loss_reason()).is_equal(LevelController.LossReason.TOXIC_OVERLOAD)
	assert_int(controller.get_state()).is_equal(LevelController.State.RESTARTING)
	assert_array(recorder.last_args(&"level_lost")).is_equal([LevelController.LossReason.TOXIC_OVERLOAD])
	controller.tick(LevelController.DESTROY_RESTART_DELAY + 0.01)
	assert_int(recorder.count(&"level_restart_requested")).is_equal(1)
	assert_int(controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_bool(controller.get_model().is_destroyed()).is_false()


func test_the_soft_rule_never_loses() -> void:
	_level.load_level(_data(false))
	var controller := _level.get_controller()
	_overload(controller.get_model())
	assert_int(controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_int(controller.get_loss_reason()).is_equal(LevelController.LossReason.NONE)


func test_a_lethal_wall_loss_stays_a_plain_overload() -> void:
	var data := _data(true)
	data.lethal_edges = PackedInt32Array([1])
	_level.load_level(data)
	var model := _level.get_controller().get_model()
	model.grab(1)
	model.drag_to(Vector2(1100, 500))
	assert_int(_level.get_controller().get_loss_reason()).is_equal(LevelController.LossReason.OVERLOAD)


func test_audio_plays_the_toxic_overload_instead_of_the_explosion() -> void:
	var director: AudioDirector = auto_free(AudioDirector.new())
	add_child(director)
	var recorder := SignalRecorder.new()
	recorder.watch(director, [&"sound_played"])
	_level.load_level(_data(true))
	director.bind_level(_level)
	_overload(_level.get_controller().get_model())
	var names: Array[StringName] = []
	for args in recorder.args_of(&"sound_played"):
		names.append(args[0])
	assert_bool(names.has(&"toxic_overload")).is_true()
	assert_bool(names.has(&"explode")).is_false()
	assert_bool(director.is_toxic_alarm_playing()).is_false()


func test_the_blast_is_yellow() -> void:
	GameState.reduced_motion = false
	_level.load_level(_data(true))
	var fx: LevelFx = _level.get_node("Playfield/Fx")
	_overload(_level.get_controller().get_model())
	await await_millis(int(VisualTuning.OVERLOAD_TIME * 1000.0) + 250)
	assert_int(fx.get_explosion_count()).is_equal(1)
	assert_bool(fx.is_flashing()).is_true()

