extends GdUnitTestSuite
## T3.1: Main = ScreenHost + Transition; ScreenHost swaps MainMenu, MissionSelect, Level and
## Settings, records results in GameState and offers the next mission (SDD 8.4-8.6).

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const MainScene := preload("res://scenes/main.tscn")

var _sandbox: Sandbox
var _main: Node
var _host: ScreenHost


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	_main = auto_free(MainScene.instantiate())
	_main.show_brand_intro = false
	add_child(_main)
	_host = _main.get_screen_host()


func after_test() -> void:
	get_tree().paused = false
	_sandbox.exit()
	# Swapped-out screens are queue_free()d (they may be inside their own signal emission);
	# let that frame pass so they are not reported as orphans.
	await await_idle_frame()


func _result(stars: int) -> LevelResult:
	var result := LevelResult.new()
	result.moves = 4
	result.time = 20.0
	result.stars = stars
	return result


func test_main_scene_tree_matches_sdd() -> void:
	assert_object(_main.get_node_or_null("ScreenHost")).is_instanceof(ScreenHost)
	assert_object(_main.get_node_or_null("Transition")).is_instanceof(Transition)
	assert_int((_main.get_node("Transition") as CanvasLayer).layer).is_greater_equal(100)


func test_starts_on_the_main_menu() -> void:
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)
	assert_object(_host.get_current_node()).is_instanceof(MainMenu)
	assert_int(_host.get_child_count()).is_equal(1)


func test_play_opens_mission_select_and_back_returns() -> void:
	(_host.get_current_node() as MainMenu).play_pressed.emit()
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MISSION_SELECT)
	(_host.get_current_node() as MissionSelect).back_pressed.emit()
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)


func test_settings_opens_and_back_returns() -> void:
	(_host.get_current_node() as MainMenu).settings_pressed.emit()
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.SETTINGS)
	assert_object(_host.get_current_node()).is_instanceof(SettingsScreen)
	(_host.get_current_node() as SettingsScreen).back_pressed.emit()
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)


func test_selecting_a_mission_loads_its_level() -> void:
	_host.go_to(ScreenHost.Screen.MISSION_SELECT)
	(_host.get_current_node() as MissionSelect).mission_selected.emit(&"m01")
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.LEVEL)
	var level := _host.get_current_node() as Level
	assert_str(String(GameState.current_mission)).is_equal("m01")
	assert_str(String(level.get_controller().get_level().mission_id)).is_equal("m01")
	assert_int(level.get_controller().neurons_root.get_child_count()).is_equal(4)
	assert_int(_host.get_child_count()).is_equal(1)


func test_locked_missions_cannot_be_played() -> void:
	_host.play_mission(&"m02")
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)
	_host.play_mission(&"missing")
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)


func test_completion_records_result_and_offers_the_next_mission() -> void:
	_host.play_mission(&"m01")
	var level := _host.get_current_node() as Level
	level.get_controller().level_completed.emit(_result(3))
	assert_bool(GameState.progress.is_completed(&"m01")).is_true()
	assert_int(GameState.progress.get_best_stars(&"m01")).is_equal(3)
	assert_bool(GameState.is_unlocked(&"m02")).is_true()
	assert_bool(FileAccess.file_exists(Sandbox.TEMP_PATH)).is_true()
	var hud := level.get_hud()
	assert_bool(hud.is_completion_visible()).is_true()
	assert_bool(hud.get_next_button().visible).is_true()
	hud.get_next_button().pressed.emit()
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.LEVEL)
	assert_str(String(GameState.current_mission)).is_equal("m02")
	var next_level := _host.get_current_node() as Level
	assert_str(String(next_level.get_controller().get_level().mission_id)).is_equal("m02")
	assert_bool(next_level.get_hud().is_completion_visible()).is_false()


func test_last_mission_offers_no_next_mission() -> void:
	var ids := GameState.campaign.get_mission_ids()
	for id in ids.slice(0, ids.size() - 1):
		GameState.record_result(id, _result(2))
	_host.play_mission(ids[-1])
	var level := _host.get_current_node() as Level
	assert_str(String(level.get_controller().get_level().mission_id)).is_equal(String(ids[-1]))
	level.get_controller().level_completed.emit(_result(1))
	assert_bool(level.get_hud().get_next_button().visible).is_false()


func test_completion_mission_select_button_returns_to_mission_select() -> void:
	_host.play_mission(&"m01")
	var level := _host.get_current_node() as Level
	level.get_controller().level_completed.emit(_result(2))
	level.get_hud().get_mission_select_button().pressed.emit()
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MISSION_SELECT)


func test_pause_mission_select_unpauses_and_leaves_the_level() -> void:
	GameState.record_result(&"m01", _result(2))
	_host.play_mission(&"m02")
	var level := _host.get_current_node() as Level
	level.pause()
	assert_bool(get_tree().paused).is_true()
	level.get_hud().get_pause_mission_select_button().pressed.emit()
	assert_bool(get_tree().paused).is_false()
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MISSION_SELECT)


func test_requests_report_whether_they_were_accepted() -> void:
	GameState.reduced_motion = false
	assert_bool(_host.go_to(ScreenHost.Screen.SETTINGS)).is_true()
	assert_bool(_host.go_to(ScreenHost.Screen.MISSION_SELECT)).is_false()
	assert_bool(_host.play_mission(&"m01")).is_false()
	await await_millis(int(Transition.FADE_DURATION * 1000.0) + 150)
	assert_bool(_host.is_busy()).is_false()
	assert_bool(_host.play_mission(&"m01")).is_true()
	await await_millis(int(Transition.FADE_DURATION * 1000.0) + 150)
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.LEVEL)


func test_transition_fades_instead_of_cutting() -> void:
	GameState.reduced_motion = false
	_host.go_to(ScreenHost.Screen.SETTINGS)
	# While the fade covers the screen the old screen is still shown.
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)
	assert_bool(_host.is_busy()).is_true()
	# Requests during a transition are ignored.
	_host.go_to(ScreenHost.Screen.MISSION_SELECT)
	await _host.screen_changed
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.SETTINGS)
	await await_millis(int(Transition.FADE_DURATION * 1000.0) + 100)
	assert_bool(_host.is_busy()).is_false()
	assert_int(_host.get_current_screen()).is_equal(ScreenHost.Screen.SETTINGS)
