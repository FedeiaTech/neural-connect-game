extends GdUnitTestSuite
## T2.5: the Level scene wires LevelController and HUD; m01/m02 load and the main scene runs m01.

const LevelScene := preload("res://scenes/level/level.tscn")
const MainScene := preload("res://scenes/main.tscn")
const M01_PATH := "res://data/levels/m01.tres"
const M02_PATH := "res://data/levels/m02.tres"

var _level: Level
var _previous_mission: StringName


func before_test() -> void:
	# The main scene writes the GameState autoload; restore it so other suites stay isolated.
	_previous_mission = GameState.current_mission
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)


func after_test() -> void:
	GameState.current_mission = _previous_mission


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


func test_main_scene_runs_the_first_mission() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	add_child(main)
	var level: Level = main.get_level()
	assert_object(level).is_not_null()
	assert_str(String(GameState.current_mission)).is_equal("m01")
	assert_str(String(level.get_controller().get_level().mission_id)).is_equal("m01")
	assert_int(level.get_controller().neurons_root.get_child_count()).is_equal(4)
