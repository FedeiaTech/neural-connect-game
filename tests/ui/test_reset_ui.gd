extends GdUnitTestSuite
## T6.1: progress reset from Settings (with an inline confirmation) and a single mission's record
## reset from Mission select (confirmation, then the map refreshes).

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")
const SettingsScene := preload("res://scenes/screens/settings_screen.tscn")

var _sandbox: Sandbox


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()


func after_test() -> void:
	_sandbox.exit()


func _add(scene: PackedScene) -> Node:
	var node: Node = auto_free(scene.instantiate())
	add_child(node)
	return node


func _complete(ids: Array[StringName]) -> void:
	for id in ids:
		var result := LevelResult.new()
		result.moves = 4
		result.time = 20.0
		result.stars = 3
		GameState.record_result(id, result)


func _cancel_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event


# --- Settings -------------------------------------------------------------------

func test_settings_reset_asks_for_confirmation_first() -> void:
	_complete([&"m01", &"m02"])
	var settings: SettingsScreen = _add(SettingsScene)
	assert_bool(settings.is_reset_confirm_visible()).is_false()
	settings.get_reset_button().pressed.emit()
	assert_bool(settings.is_reset_confirm_visible()).is_true()
	# Nothing is erased until confirmed; the safe choice has focus.
	assert_int(GameState.progress.get_completed_count()).is_equal(2)
	assert_bool(settings.get_reset_cancel_button().has_focus()).is_true()


func test_settings_reset_confirm_erases_progress_and_gives_feedback() -> void:
	_complete([&"m01", &"m02"])
	GameState.set_master_volume(0.4)
	var settings: SettingsScreen = _add(SettingsScene)
	settings.get_reset_button().pressed.emit()
	settings.get_reset_confirm_button().pressed.emit()
	assert_int(GameState.progress.get_completed_count()).is_equal(0)
	assert_float(GameState.master_volume).is_equal_approx(0.4, 0.0001)
	assert_bool(settings.is_reset_confirm_visible()).is_false()
	assert_bool(settings.is_reset_feedback_visible()).is_true()
	assert_bool(settings.get_reset_button().has_focus()).is_true()


func test_settings_reset_cancel_keeps_progress() -> void:
	_complete([&"m01"])
	var settings: SettingsScreen = _add(SettingsScene)
	settings.get_reset_button().pressed.emit()
	settings.get_reset_cancel_button().pressed.emit()
	assert_bool(settings.is_reset_confirm_visible()).is_false()
	assert_bool(settings.is_reset_feedback_visible()).is_false()
	assert_int(GameState.progress.get_completed_count()).is_equal(1)
	assert_bool(settings.get_reset_button().has_focus()).is_true()


func test_settings_ui_cancel_closes_the_confirmation_before_leaving() -> void:
	var settings: SettingsScreen = _add(SettingsScene)
	var backs := [0]
	settings.back_pressed.connect(func() -> void: backs[0] += 1)
	settings.get_reset_button().pressed.emit()
	settings._unhandled_input(_cancel_event())
	assert_bool(settings.is_reset_confirm_visible()).is_false()
	assert_int(backs[0]).is_equal(0)
	settings._unhandled_input(_cancel_event())
	assert_int(backs[0]).is_equal(1)


# --- Mission select -------------------------------------------------------------

func test_mission_reset_needs_a_completed_mission() -> void:
	_complete([&"m01"])
	var select: MissionSelect = _add(MissionSelectScene)
	select.request_mission_reset(&"m02")
	assert_bool(select.is_mission_reset_pending()).is_false()
	select.request_mission_reset(&"m01")
	assert_bool(select.is_mission_reset_pending()).is_true()
	assert_bool(select.get_mission_reset_cancel_button().has_focus()).is_true()


func test_mission_reset_confirm_clears_the_record_and_refreshes_the_map() -> void:
	_complete([&"m01", &"m02"])
	var select: MissionSelect = _add(MissionSelectScene)
	assert_int(select.get_mission_node(&"m02").state).is_equal(MissionNode.State.COMPLETED)
	select.request_mission_reset(&"m02")
	select.get_mission_reset_confirm_button().pressed.emit()
	assert_bool(GameState.progress.is_completed(&"m02")).is_false()
	assert_bool(GameState.progress.is_completed(&"m01")).is_true()
	assert_bool(select.is_mission_reset_pending()).is_false()
	var m02 := select.get_mission_node(&"m02")
	assert_int(m02.state).is_equal(MissionNode.State.UNLOCKED)
	assert_int(m02.stars).is_equal(0)
	assert_int(select.get_mission_node(&"m03").state).is_equal(MissionNode.State.LOCKED)
	assert_bool(m02.has_focus()).is_true()


func test_mission_reset_cancel_keeps_the_record() -> void:
	_complete([&"m01"])
	var select: MissionSelect = _add(MissionSelectScene)
	select.request_mission_reset(&"m01")
	select.get_mission_reset_cancel_button().pressed.emit()
	assert_bool(select.is_mission_reset_pending()).is_false()
	assert_bool(GameState.progress.is_completed(&"m01")).is_true()


func test_focusing_a_completed_mission_offers_its_reset() -> void:
	_complete([&"m01"])
	var select: MissionSelect = _add(MissionSelectScene)
	var button := select.get_mission_reset_button()
	select.get_mission_node(&"m02").grab_focus()
	assert_bool(button.visible).is_false()
	select.get_mission_node(&"m01").grab_focus()
	assert_bool(button.visible).is_true()
	button.pressed.emit()
	assert_bool(select.is_mission_reset_pending()).is_true()


func test_right_click_on_a_completed_mission_asks_to_reset_it() -> void:
	_complete([&"m01"])
	var select: MissionSelect = _add(MissionSelectScene)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	select.get_mission_node(&"m01").gui_input.emit(click)
	assert_bool(select.is_mission_reset_pending()).is_true()


func test_mission_select_ui_cancel_closes_the_confirmation_first() -> void:
	_complete([&"m01"])
	var select: MissionSelect = _add(MissionSelectScene)
	var backs := [0]
	select.back_pressed.connect(func() -> void: backs[0] += 1)
	select.request_mission_reset(&"m01")
	select._unhandled_input(_cancel_event())
	assert_bool(select.is_mission_reset_pending()).is_false()
	assert_int(backs[0]).is_equal(0)
