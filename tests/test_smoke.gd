extends GdUnitTestSuite
## Smoke test: proves the gdUnit4 runner and the GameState autoload work headless.


func test_game_state_autoload_is_available() -> void:
	assert_that(GameState).is_not_null()


func test_game_state_emits_on_mission_change() -> void:
	var monitor := monitor_signals(GameState, false)
	GameState.current_mission = &"m01"
	await assert_signal(monitor).is_emitted("current_mission_changed", [&"m01"])
	GameState.current_mission = &""
