extends GdUnitTestSuite
## T2.5: the Level scene wires LevelController and HUD; m01/m02 load.
## T3.1: pause overlay freezes the level; completion/pause intents go up as Level signals.
## (The main scene no longer runs m01 directly: see tests/flow/test_screen_host.gd.)

const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const LevelScene := preload("res://scenes/level/level.tscn")
const M01_PATH := "res://data/levels/m01.tres"
const M02_PATH := "res://data/levels/m02.tres"

var _level: Level
var _saved_reduced_motion := false
## Text assertions are in English whatever the OS language (T6.2).
var _saved_locale := ""


## Reduced motion: the completion summary shows at once (the delayed path is covered by
## tests/level/test_level_fx.gd).
func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_saved_reduced_motion = GameState.reduced_motion
	GameState.reduced_motion = true
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)
	GameState.reduced_motion = _saved_reduced_motion
	# Never leave the tree paused for the next test.
	get_tree().paused = false


func test_scene_tree_matches_sdd() -> void:
	for path in ["Background", "Playfield/Boundary", "Playfield/Obstacles", "Playfield/Dendrites",
			"Playfield/Neurons", "InputController", "LevelController", "HUD"]:
		assert_object(_level.get_node_or_null(path)).override_failure_message(path).is_not_null()


func test_m01_is_a_four_neuron_first_mission() -> void:
	var level: LevelData = load(M01_PATH)
	assert_str(String(level.mission_id)).is_equal("m01")
	assert_int(level.chapter_id).is_equal(1)
	assert_int(level.neurons.size()).is_equal(4)
	assert_str(level.story_text).is_not_empty()
	assert_array(PuzzleModel.validate_level(level)).is_empty()


func test_m02_has_a_multi_dendrite_neuron() -> void:
	var level: LevelData = load(M02_PATH)
	assert_array(PuzzleModel.validate_level(level)).is_empty()
	var degree: Dictionary[int, int] = {}
	for dendrite in level.dendrites:
		degree[dendrite.a] = degree.get(dendrite.a, 0) + 1
		degree[dendrite.b] = degree.get(dendrite.b, 0) + 1
	assert_int(degree.values().max()).is_greater_equal(3)


func test_loading_a_story_mission_shows_the_story() -> void:
	var data: LevelData = load(M01_PATH)
	_level.load_level(data)
	var hud := _level.get_hud()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.INTRO)
	assert_bool(hud.is_story_visible()).is_true()
	assert_str(hud.get_story_text()).is_equal(data.story_text)
	assert_str(hud.get_mission_text()).is_equal(data.mission_name)


func test_dismissing_the_story_starts_playing() -> void:
	_level.load_level(load(M01_PATH))
	_level.get_hud().story_dismissed.emit()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)


func test_mission_without_story_starts_playing_directly() -> void:
	_level.load_level(load(M02_PATH))
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)
	assert_bool(_level.get_hud().is_story_visible()).is_false()


func test_controller_counters_reach_the_hud() -> void:
	_level.load_level(load(M02_PATH))
	var controller := _level.get_controller()
	controller.move_count_changed.emit(5)
	controller.tick(61.0)
	assert_str(_level.get_hud().get_moves_text()).is_equal("Moves 5")
	assert_str(_level.get_hud().get_time_text()).is_equal("01:01")


func test_completion_and_replay_flow() -> void:
	_level.load_level(load(M02_PATH))
	var controller := _level.get_controller()
	controller.level_completed.emit(LevelResult.create(3, 20.0, 8, 90.0))
	assert_bool(_level.get_hud().is_completion_visible()).is_true()
	_level.get_hud().get_replay_button().pressed.emit()
	assert_bool(_level.get_hud().is_completion_visible()).is_false()
	assert_int(controller.get_state()).is_equal(LevelController.State.PLAYING)


func test_pause_freezes_the_level_clock_and_shows_the_overlay() -> void:
	_level.load_level(load(M02_PATH))
	var controller := _level.get_controller()
	var hud := _level.get_hud()
	_level.pause()
	assert_bool(_level.is_paused()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(hud.is_pause_visible()).is_true()
	# The controller (and its timer) stops; the HUD keeps working.
	assert_bool(controller.can_process()).is_false()
	assert_bool(hud.can_process()).is_true()
	_level.resume()
	assert_bool(get_tree().paused).is_false()
	assert_bool(hud.is_pause_visible()).is_false()
	assert_bool(controller.can_process()).is_true()


func test_pause_is_only_possible_while_playing() -> void:
	_level.load_level(load(M01_PATH))
	_level.pause()
	assert_bool(_level.is_paused()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_hud_pause_and_resume_requests_toggle_the_pause() -> void:
	_level.load_level(load(M02_PATH))
	_level.get_hud().pause_requested.emit()
	assert_bool(_level.is_paused()).is_true()
	_level.get_hud().get_resume_button().pressed.emit()
	assert_bool(_level.is_paused()).is_false()


func test_restart_from_pause_resumes_and_resets_counters() -> void:
	_level.load_level(load(M02_PATH))
	var controller := _level.get_controller()
	controller.tick(12.0)
	_level.pause()
	_level.get_hud().get_pause_restart_button().pressed.emit()
	assert_bool(get_tree().paused).is_false()
	assert_float(controller.get_elapsed_time()).is_equal(0.0)
	assert_int(controller.get_state()).is_equal(LevelController.State.PLAYING)


func test_mission_select_from_pause_resumes_and_requests_it() -> void:
	var recorder := SignalRecorder.new()
	recorder.watch(_level, [&"mission_select_requested"])
	_level.load_level(load(M02_PATH))
	_level.pause()
	_level.get_hud().get_pause_mission_select_button().pressed.emit()
	assert_bool(get_tree().paused).is_false()
	assert_int(recorder.count(&"mission_select_requested")).is_equal(1)


func test_leaving_the_tree_while_paused_unpauses() -> void:
	_level.load_level(load(M02_PATH))
	_level.pause()
	remove_child(_level)
	assert_bool(get_tree().paused).is_false()
	add_child(_level)


func test_next_mission_button_is_hidden_until_offered() -> void:
	var recorder := SignalRecorder.new()
	recorder.watch(_level, [&"next_mission_requested"])
	_level.load_level(load(M02_PATH))
	_level.get_controller().level_completed.emit(LevelResult.create(3, 20.0, 8, 90.0))
	assert_bool(_level.get_hud().get_next_button().visible).is_false()
	_level.set_next_mission_available(true)
	assert_bool(_level.get_hud().get_next_button().visible).is_true()
	_level.get_hud().get_next_button().pressed.emit()
	assert_int(recorder.count(&"next_mission_requested")).is_equal(1)
