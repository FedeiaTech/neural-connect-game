extends GdUnitTestSuite
## Studio splash and credits screen: intent signals and the flow through ScreenHost.

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const MainScene := preload("res://scenes/main.tscn")
const BrandIntroScene := preload("res://scenes/screens/brand_intro.tscn")
const CreditsScene := preload("res://scenes/screens/credits_screen.tscn")
const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")

var _sandbox: Sandbox
var _recorder: SignalRecorder


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	GameState.reduced_motion = true
	_recorder = SignalRecorder.new()


func after_test() -> void:
	get_tree().paused = false
	_sandbox.exit()
	await get_tree().process_frame


func _press_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	return key


func test_brand_intro_finishes_once_when_skipped() -> void:
	var intro: BrandIntro = auto_free(BrandIntroScene.instantiate())
	add_child(intro)
	_recorder.watch(intro, [&"finished"])
	intro._unhandled_input(_press_key())
	intro._unhandled_input(_press_key())
	assert_int(_recorder.count(&"finished")).is_equal(1)


func test_main_menu_shows_the_project_version() -> void:
	var menu: MainMenu = auto_free(MainMenuScene.instantiate())
	add_child(menu)
	var expected := "v%s" % ProjectSettings.get_setting("application/config/version")
	assert_str(MainMenu.version_text()).is_equal(expected)
	assert_str((menu.get_node("VersionLabel") as Label).text).is_equal(expected)
	assert_str(expected).is_equal("v1.03")


func test_credits_back_button_emits_back_pressed() -> void:
	var credits: CreditsScreen = auto_free(CreditsScene.instantiate())
	add_child(credits)
	_recorder.watch(credits, [&"back_pressed"])
	credits.get_back_button().pressed.emit()
	assert_int(_recorder.count(&"back_pressed")).is_equal(1)


func test_game_starts_on_the_brand_intro_and_reaches_the_menu() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	add_child(main)
	var host: ScreenHost = main.get_screen_host()
	await get_tree().create_timer(0.3).timeout
	assert_int(host.get_current_screen()).is_equal(ScreenHost.Screen.BRAND_INTRO)
	(host.get_current_node() as BrandIntro).finished.emit()
	await get_tree().create_timer(0.3).timeout
	assert_int(host.get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)


func test_menu_credits_button_opens_credits_and_back_returns() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	main.show_brand_intro = false
	add_child(main)
	var host: ScreenHost = main.get_screen_host()
	await get_tree().create_timer(0.3).timeout
	(host.get_current_node() as MainMenu).get_credits_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	assert_int(host.get_current_screen()).is_equal(ScreenHost.Screen.CREDITS)
	(host.get_current_node() as CreditsScreen).get_back_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	assert_int(host.get_current_screen()).is_equal(ScreenHost.Screen.MAIN_MENU)
