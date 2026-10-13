extends GdUnitTestSuite
## DiagnosticsScreen and how the app reaches it: the Settings button, ScreenHost, and the automatic
## resume at launch. The battery runs headless here, where every step that needs a window is skipped.

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const MainScene := preload("res://scenes/main.tscn")
const ScreenScene := preload("res://scenes/screens/diagnostics_screen.tscn")
const SettingsScene := preload("res://scenes/screens/settings_screen.tscn")
const STATE_PATH := "user://test_diag_screen_state.json"
const REPORT_PATH := "user://test_diag_screen_report.txt"

var _sandbox: Sandbox


class SlowStep extends DiagnosticStep:
	func _init() -> void:
		id = &"slow"
		title = "slow fake"
		duration = 30.0
		requires_window = false


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()


func after_test() -> void:
	get_tree().paused = false
	_sandbox.exit()
	DiagnosticState.clear(STATE_PATH)
	if FileAccess.file_exists(REPORT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REPORT_PATH))
	await await_idle_frame()


func _screen() -> DiagnosticsScreen:
	var screen: DiagnosticsScreen = ScreenScene.instantiate()
	screen.state_path = STATE_PATH
	screen.report_path = REPORT_PATH
	auto_free(screen)
	add_child(screen)
	screen.get_runner().set_process(false)
	screen.get_runner().gap_seconds = 0.0
	return screen


func test_it_opens_on_the_intro_with_a_start_button() -> void:
	var screen := _screen()
	assert_bool(screen.is_result_visible()).is_true()
	assert_bool(screen.get_start_button().visible).is_true()
	assert_bool(screen.get_copy_button().visible).is_false()
	assert_bool(screen.get_reset_button().visible).is_false()
	assert_str(screen.get_report_text()).is_not_empty()


func test_start_runs_the_battery_and_shows_the_report() -> void:
	var screen := _screen()
	screen.get_runner().headless = true
	screen.get_start_button().pressed.emit()
	assert_bool(screen.is_result_visible()).is_false()
	screen.get_runner().tick(0.0)
	assert_bool(screen.is_result_visible()).is_true()
	assert_str(screen.get_report_text()).contains("baseline_empty")
	assert_str(screen.get_report_text()).contains("SKIPPED")
	assert_bool(screen.get_copy_button().visible).is_true()
	assert_bool(FileAccess.file_exists(REPORT_PATH)).is_true()


func test_cancel_stops_the_run_and_forgets_it() -> void:
	var screen := _screen()
	var runner := screen.get_runner()
	runner.steps = [SlowStep.new()]
	screen.get_start_button().pressed.emit()
	runner.tick(0.0)
	assert_bool(runner.is_running()).is_true()
	assert_bool(FileAccess.file_exists(STATE_PATH)).is_true()
	screen.get_cancel_button().pressed.emit()
	assert_bool(runner.is_running()).is_false()
	assert_bool(FileAccess.file_exists(STATE_PATH)).is_false()
	assert_bool(screen.is_result_visible()).is_true()


func test_a_run_in_progress_resumes_by_itself_and_blames_the_unfinished_step() -> void:
	var state := DiagnosticState.create(PackedStringArray(["gone_a", "gone_b"]))
	state.begin_step("gone_a", 5.0, "", false)
	state.save(STATE_PATH)
	var screen: DiagnosticsScreen = ScreenScene.instantiate()
	screen.state_path = STATE_PATH
	screen.report_path = REPORT_PATH
	auto_free(screen)
	add_child(screen)
	var resumed := screen.get_runner().get_state()
	assert_object(resumed).is_not_null()
	assert_str(resumed.status_of("gone_a")).is_equal(DiagnosticState.CRASHED)
	assert_int(resumed.launches).is_equal(2)


func test_reset_forgets_the_previous_results() -> void:
	var state := DiagnosticState.create(PackedStringArray(["a"]))
	state.begin_step("a", 1.0, "", false)
	state.finish_step("a", {})
	state.save(STATE_PATH)
	var screen := _screen()
	assert_bool(screen.get_reset_button().visible).is_true()
	assert_str(screen.get_report_text()).contains("Neural Connect diagnostics report")
	screen.get_reset_button().pressed.emit()
	assert_bool(FileAccess.file_exists(STATE_PATH)).is_false()
	assert_bool(screen.get_reset_button().visible).is_false()


func test_back_emits_back_pressed() -> void:
	var screen := _screen()
	var pressed := [0]
	screen.back_pressed.connect(func() -> void: pressed[0] += 1)
	screen.get_back_button().pressed.emit()
	assert_int(pressed[0]).is_equal(1)


func test_settings_has_a_diagnostics_button_that_emits_its_signal() -> void:
	var settings: SettingsScreen = auto_free(SettingsScene.instantiate())
	add_child(settings)
	var pressed := [0]
	settings.diagnostics_pressed.connect(func() -> void: pressed[0] += 1)
	settings.get_diagnostics_button().pressed.emit()
	assert_int(pressed[0]).is_equal(1)
	settings.set_diagnostics_available(false)
	assert_bool(settings.get_diagnostics_button().visible).is_false()


func test_screen_host_opens_the_diagnostics_from_settings_and_back_returns_to_settings() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	main.show_brand_intro = false
	add_child(main)
	var host: ScreenHost = main.get_screen_host()
	host.go_to(ScreenHost.Screen.SETTINGS)
	(host.get_current_node() as SettingsScreen).diagnostics_pressed.emit()
	assert_int(host.get_current_screen()).is_equal(ScreenHost.Screen.DIAGNOSTICS)
	assert_object(host.get_current_node()).is_instanceof(DiagnosticsScreen)
	(host.get_current_node() as DiagnosticsScreen).back_pressed.emit()
	assert_int(host.get_current_screen()).is_equal(ScreenHost.Screen.SETTINGS)
	await await_idle_frame()


func test_a_host_nested_in_the_battery_hides_the_diagnostics_button() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	main.show_brand_intro = false
	add_child(main)
	var host: ScreenHost = main.get_screen_host()
	host.diagnostics_enabled = false
	host.go_to(ScreenHost.Screen.SETTINGS)
	assert_bool((host.get_current_node() as SettingsScreen).get_diagnostics_button().visible).is_false()
	await await_idle_frame()


func test_the_app_starts_on_the_diagnostics_when_a_run_is_in_progress() -> void:
	var state := DiagnosticState.create(PackedStringArray(["a", "b"]))
	state.begin_step("a", 1.0, "", false)
	state.save(STATE_PATH)
	var main: Node = auto_free(MainScene.instantiate())
	main.show_brand_intro = false
	main.diagnostics_state_path = STATE_PATH
	add_child(main)
	assert_int(main.get_screen_host().get_current_screen()).is_equal(ScreenHost.Screen.DIAGNOSTICS)
	await await_idle_frame()


func test_the_app_starts_normally_once_the_run_is_finished() -> void:
	var state := DiagnosticState.create(PackedStringArray(["a"]))
	state.begin_step("a", 1.0, "", false)
	state.finish_step("a", {})
	state.save(STATE_PATH)
	var main: Node = auto_free(MainScene.instantiate())
	main.show_brand_intro = false
	main.diagnostics_state_path = STATE_PATH
	add_child(main)
	assert_int(main.get_screen_host().get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)
	await await_idle_frame()
