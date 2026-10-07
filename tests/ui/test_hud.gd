extends GdUnitTestSuite
## T2.4: minimal HUD — counters, story overlay, completion panel and its signals.

const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const HudScene := preload("res://scenes/ui/hud.tscn")

var _hud: Hud
var _recorder: SignalRecorder


func before_test() -> void:
	_hud = auto_free(HudScene.instantiate())
	add_child(_hud)
	_recorder = SignalRecorder.new()
	_recorder.watch(_hud, [&"restart_pressed", &"story_dismissed"])


func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func test_format_time_is_minutes_and_seconds() -> void:
	assert_str(Hud.format_time(0.0)).is_equal("00:00")
	assert_str(Hud.format_time(65.9)).is_equal("01:05")
	assert_str(Hud.format_time(3600.0)).is_equal("60:00")
	assert_str(Hud.format_time(-3.0)).is_equal("00:00")


func test_counters_update_labels() -> void:
	_hud.set_moves(3)
	_hud.set_time(65.0)
	_hud.set_mission_title("First Spark")
	assert_str(_hud.get_moves_text()).is_equal("Moves 3")
	assert_str(_hud.get_time_text()).is_equal("01:05")
	assert_str(_hud.get_mission_text()).is_equal("First Spark")


func test_overlays_start_hidden() -> void:
	assert_bool(_hud.is_story_visible()).is_false()
	assert_bool(_hud.is_completion_visible()).is_false()


func test_click_dismisses_story() -> void:
	_hud.show_story("A first spark crosses the dark.")
	assert_bool(_hud.is_story_visible()).is_true()
	assert_str(_hud.get_story_text()).is_equal("A first spark crosses the dark.")
	_hud._on_story_gui_input(_click())
	assert_bool(_hud.is_story_visible()).is_false()
	assert_int(_recorder.count(&"story_dismissed")).is_equal(1)


func test_tap_dismisses_story_once() -> void:
	_hud.show_story("Story.")
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	_hud._on_story_gui_input(tap)
	_hud._on_story_gui_input(_click())
	assert_int(_recorder.count(&"story_dismissed")).is_equal(1)


func test_completion_shows_stars_moves_and_time() -> void:
	_hud.show_completion(LevelResult.create(4, 32.0, 6, 60.0))
	assert_bool(_hud.is_completion_visible()).is_true()
	assert_int(_hud.get_star_count()).is_equal(3)
	assert_str(_hud.get_completion_stats_text()).contains("Moves 4")
	assert_str(_hud.get_completion_stats_text()).contains("00:32")
	_hud.hide_completion()
	assert_bool(_hud.is_completion_visible()).is_false()


func test_restart_and_replay_buttons_emit_restart_pressed() -> void:
	_hud.get_restart_button().pressed.emit()
	_hud.get_replay_button().pressed.emit()
	assert_int(_recorder.count(&"restart_pressed")).is_equal(2)


func _pause_action() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	return event


func test_pause_action_requests_pause_then_resume() -> void:
	_recorder.watch(_hud, [&"pause_requested", &"resume_pressed"])
	_hud._unhandled_input(_pause_action())
	assert_int(_recorder.count(&"pause_requested")).is_equal(1)
	_hud.show_pause()
	_hud._unhandled_input(_pause_action())
	assert_int(_recorder.count(&"resume_pressed")).is_equal(1)
	assert_int(_recorder.count(&"pause_requested")).is_equal(1)


func test_pause_overlay_buttons_emit_intents() -> void:
	_recorder.watch(_hud, [&"pause_requested", &"resume_pressed", &"mission_select_pressed"])
	_hud.get_pause_button().pressed.emit()
	_hud.show_pause()
	assert_bool(_hud.is_pause_visible()).is_true()
	_hud.get_resume_button().pressed.emit()
	_hud.get_pause_restart_button().pressed.emit()
	_hud.get_pause_mission_select_button().pressed.emit()
	assert_int(_recorder.count(&"pause_requested")).is_equal(1)
	assert_int(_recorder.count(&"resume_pressed")).is_equal(1)
	assert_int(_recorder.count(&"restart_pressed")).is_equal(1)
	assert_int(_recorder.count(&"mission_select_pressed")).is_equal(1)
	_hud.hide_pause()
	assert_bool(_hud.is_pause_visible()).is_false()


func test_completion_offers_next_replay_and_mission_select() -> void:
	_recorder.watch(_hud, [&"next_mission_pressed", &"mission_select_pressed"])
	_hud.show_completion(LevelResult.create(4, 32.0, 6, 60.0))
	assert_bool(_hud.get_next_button().visible).is_false()
	_hud.set_next_mission_available(true)
	assert_bool(_hud.get_next_button().visible).is_true()
	_hud.get_next_button().pressed.emit()
	_hud.get_mission_select_button().pressed.emit()
	assert_int(_recorder.count(&"next_mission_pressed")).is_equal(1)
	assert_int(_recorder.count(&"mission_select_pressed")).is_equal(1)


func test_hud_runs_while_paused() -> void:
	assert_int(_hud.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_star_shape_has_ten_points() -> void:
	assert_int(StarRow.star_points(Vector2.ZERO, 10.0).size()).is_equal(10)
