extends GdUnitTestSuite
## T3.1: MainMenu, MissionSelect and SettingsScreen emit intent upward and reflect GameState.

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")
const SettingsScene := preload("res://scenes/screens/settings_screen.tscn")

var _sandbox: Sandbox
var _recorder: SignalRecorder


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	_recorder = SignalRecorder.new()


func after_test() -> void:
	_sandbox.exit()


func _add(scene: PackedScene) -> Node:
	var node: Node = auto_free(scene.instantiate())
	add_child(node)
	return node


func _result(stars: int) -> LevelResult:
	var result := LevelResult.new()
	result.moves = 4
	result.time = 20.0
	result.stars = stars
	return result


# --- MainMenu -------------------------------------------------------------------

func test_main_menu_shows_the_title_and_emits_button_intents() -> void:
	var menu: MainMenu = _add(MainMenuScene)
	assert_str(menu.get_title_text()).is_equal("Neural Connect")
	_recorder.watch(menu, [&"play_pressed", &"settings_pressed", &"quit_pressed"])
	menu.get_play_button().pressed.emit()
	menu.get_settings_button().pressed.emit()
	menu.get_quit_button().pressed.emit()
	assert_int(_recorder.count(&"play_pressed")).is_equal(1)
	assert_int(_recorder.count(&"settings_pressed")).is_equal(1)
	assert_int(_recorder.count(&"quit_pressed")).is_equal(1)


# --- MissionSelect -------------------------------------------------------------

func test_mission_select_shows_chapters_and_lock_states() -> void:
	var select: MissionSelect = _add(MissionSelectScene)
	assert_array(select.get_chapter_titles()).contains(["Chapter 1: First Signals"])
	var m01 := select.get_mission_node(&"m01")
	var m02 := select.get_mission_node(&"m02")
	assert_int(m01.state).is_equal(MissionNode.State.UNLOCKED)
	assert_int(m01.number).is_equal(1)
	assert_int(m02.state).is_equal(MissionNode.State.LOCKED)
	assert_bool(m02.disabled).is_true()


func test_mission_select_shows_completed_missions_with_stars() -> void:
	GameState.record_result(&"m01", _result(2))
	var select: MissionSelect = _add(MissionSelectScene)
	var m01 := select.get_mission_node(&"m01")
	assert_int(m01.state).is_equal(MissionNode.State.COMPLETED)
	assert_int(m01.stars).is_equal(2)
	assert_int(select.get_mission_node(&"m02").state).is_equal(MissionNode.State.UNLOCKED)


func test_pressing_an_unlocked_mission_emits_mission_selected() -> void:
	var select: MissionSelect = _add(MissionSelectScene)
	_recorder.watch(select, [&"mission_selected", &"back_pressed"])
	select.get_mission_node(&"m01").pressed.emit()
	select.get_mission_node(&"m02").pressed.emit()
	assert_int(_recorder.count(&"mission_selected")).is_equal(1)
	assert_array(_recorder.last_args(&"mission_selected")).is_equal([&"m01"])
	select.get_back_button().pressed.emit()
	assert_int(_recorder.count(&"back_pressed")).is_equal(1)


func test_mission_node_state_from_progress() -> void:
	assert_int(MissionNode.state_for(false, false)).is_equal(MissionNode.State.LOCKED)
	assert_int(MissionNode.state_for(true, false)).is_equal(MissionNode.State.UNLOCKED)
	assert_int(MissionNode.state_for(true, true)).is_equal(MissionNode.State.COMPLETED)


# --- SettingsScreen ------------------------------------------------------------

func test_settings_reflect_saved_values() -> void:
	GameState.set_master_volume(0.25)
	GameState.set_reduced_motion(true)
	var settings: SettingsScreen = _add(SettingsScene)
	assert_float(settings.get_volume_slider().value).is_equal_approx(0.25, 0.0001)
	assert_bool(settings.get_reduced_motion_toggle().button_pressed).is_true()


func test_settings_apply_and_save_immediately() -> void:
	GameState.set_reduced_motion(false)
	var settings: SettingsScreen = _add(SettingsScene)
	settings.get_volume_slider().value = 0.5
	assert_float(GameState.master_volume).is_equal_approx(0.5, 0.0001)
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal_approx(linear_to_db(0.5), 0.01)
	settings.get_reduced_motion_toggle().button_pressed = true
	assert_bool(GameState.reduced_motion).is_true()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Sandbox.TEMP_PATH))
	assert_float(float(saved["settings"]["master_volume"])).is_equal_approx(0.5, 0.0001)
	assert_bool(saved["settings"]["reduced_motion"]).is_true()


func test_settings_back_button_emits_back_pressed() -> void:
	var settings: SettingsScreen = _add(SettingsScene)
	_recorder.watch(settings, [&"back_pressed"])
	settings.get_back_button().pressed.emit()
	assert_int(_recorder.count(&"back_pressed")).is_equal(1)
