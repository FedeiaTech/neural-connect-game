extends GdUnitTestSuite
## T4.6: AudioDirector — buses, tension-to-pitch mapping and sounds triggered by the signals the
## level, HUD and menus already emit (recorded through sound_played).

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const LevelScene := preload("res://scenes/level/level.tscn")
const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")
const MainScene := preload("res://scenes/main.tscn")
const LevelFactory := preload("res://tests/model/level_factory.gd")

var _sandbox: Sandbox
var _recorder: SignalRecorder
var _director: AudioDirector


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	_recorder = SignalRecorder.new()
	_director = auto_free(AudioDirector.new())
	add_child(_director)
	_recorder.watch(_director, [&"sound_played"])


func after_test() -> void:
	get_tree().paused = false
	_sandbox.exit()
	await await_idle_frame()


func _played() -> Array[StringName]:
	var names: Array[StringName] = []
	for args in _recorder.args_of(&"sound_played"):
		names.append(args[0])
	return names


func _level() -> Level:
	var level: Level = auto_free(LevelScene.instantiate())
	add_child(level)
	level.load_level(GameState.get_level(&"m01"))
	_director.bind_level(level)
	return level


# --- Pure mapping --------------------------------------------------------------

func test_tension_pitch_rises_with_the_ratio() -> void:
	assert_float(AudioDirector.tension_pitch(0.0)).is_equal_approx(AudioDirector.TENSION_PITCH_MIN, 0.0001)
	assert_float(AudioDirector.tension_pitch(1.0)).is_equal_approx(AudioDirector.TENSION_PITCH_MAX, 0.0001)
	assert_float(AudioDirector.tension_pitch(2.0)).is_equal_approx(AudioDirector.TENSION_PITCH_MAX, 0.0001)
	var previous := 0.0
	for i in 11:
		var pitch := AudioDirector.tension_pitch(i / 10.0)
		assert_float(pitch).is_greater_equal(previous)
		previous = pitch


func test_tension_volume_is_silent_when_slack() -> void:
	assert_bool(AudioDirector.is_tension_audible(AudioDirector.TENSION_AUDIBLE_START - 0.01)).is_false()
	assert_bool(AudioDirector.is_tension_audible(0.8)).is_true()
	assert_float(AudioDirector.tension_volume_db(1.0)).is_equal_approx(AudioDirector.TENSION_MAX_DB, 0.0001)
	assert_float(AudioDirector.tension_volume_db(0.5)).is_less(AudioDirector.tension_volume_db(0.9))


# --- Setup -----------------------------------------------------------------------

func test_buses_exist_and_players_use_them() -> void:
	if not _director.are_sounds_ready():
		await _director.sounds_ready
	assert_int(AudioServer.get_bus_index(&"Music")).is_greater(0)
	assert_int(AudioServer.get_bus_index(&"SFX")).is_greater(0)
	assert_str(String(_director.get_player(&"ambient").bus)).is_equal("Music")
	assert_str(String(_director.get_player(&"grab").bus)).is_equal("SFX")
	assert_bool(_director.is_ambient_playing()).is_true()


func test_sounds_are_rendered_off_the_main_thread_and_handed_over() -> void:
	if not _director.are_sounds_ready():
		await _director.sounds_ready
	for sound: StringName in SoundBank.NAMES:
		assert_object(_director.get_player(sound).stream).override_failure_message(String(sound)).is_not_null()
		assert_bool(SoundBank.is_built(sound)).is_true()


func test_director_keeps_playing_while_paused() -> void:
	assert_int(_director.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_play_reports_the_sound() -> void:
	_director.play(&"star", 1.2)
	assert_array(_played()).is_equal([&"star"])
	assert_float(_director.get_player(&"star").pitch_scale).is_equal_approx(1.2, 0.0001)


# --- Level signals -------------------------------------------------------------

func test_grab_and_release_blips() -> void:
	var level := _level()
	level.get_input_controller().grab_started.emit(0)
	level.get_input_controller().grab_ended.emit(0)
	assert_array(_played()).is_equal([&"grab", &"release"])


func test_blocked_contact_ticks_but_is_throttled() -> void:
	var level := _level()
	var model := level.get_controller().get_model()
	model.neuron_blocked.emit(0, Vector2.ZERO)
	model.neuron_blocked.emit(0, Vector2.ZERO)
	assert_int(_played().count(&"blocked")).is_equal(1)
	var ready_at := Time.get_ticks_msec() + int(AudioDirector.BLOCKED_COOLDOWN * 1000.0) + 20
	while Time.get_ticks_msec() < ready_at:
		await await_idle_frame()
	model.neuron_blocked.emit(0, Vector2.ZERO)
	assert_int(_played().count(&"blocked")).is_equal(2)


func test_tension_tone_follows_the_max_ratio_and_stops_on_release() -> void:
	var level := _level()
	var model := level.get_controller().get_model()
	model.tension_changed.emit(0, 0.1)
	assert_bool(_director.is_tension_playing()).is_false()
	model.tension_changed.emit(0, 0.7)
	model.tension_changed.emit(1, 0.9)
	assert_bool(_director.is_tension_playing()).is_true()
	assert_float(_director.get_player(&"tension").pitch_scale) \
		.is_equal_approx(AudioDirector.tension_pitch(0.9), 0.0001)
	model.tension_changed.emit(1, 0.2)
	assert_float(_director.get_player(&"tension").pitch_scale) \
		.is_equal_approx(AudioDirector.tension_pitch(0.7), 0.0001)
	level.get_input_controller().grab_ended.emit(0)
	assert_bool(_director.is_tension_playing()).is_false()


func test_break_snaps_and_silences_the_tension_tone() -> void:
	var level := _level()
	var model := level.get_controller().get_model()
	model.tension_changed.emit(0, 0.95)
	model.edge_broke.emit(0)
	assert_bool(_played().has(&"snap")).is_true()
	assert_bool(_director.is_tension_playing()).is_false()


func test_resolved_crossing_chimes() -> void:
	var level := _level()
	var model := level.get_controller().get_model()
	var none: Array[int] = []
	# More crossings than m01 can ever have, so this is never a decrease.
	var many: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	model.crossings_changed.emit(many, none)
	assert_bool(_played().has(&"chime")).is_false()
	model.crossings_changed.emit(none, none)
	assert_bool(_played().has(&"chime")).is_true()


## T7.1: soft electric buzz while crossings exist, louder with more crossings (capped).
func test_buzz_volume_rises_gently_with_the_crossing_count() -> void:
	assert_float(AudioDirector.buzz_volume_db(0)).is_equal(AudioDirector.SILENT_DB)
	assert_float(AudioDirector.buzz_volume_db(1)).is_equal_approx(AudioDirector.BUZZ_MIN_DB, 0.0001)
	assert_float(AudioDirector.buzz_volume_db(3)).is_greater(AudioDirector.buzz_volume_db(1))
	assert_float(AudioDirector.buzz_volume_db(50)).is_equal_approx(AudioDirector.BUZZ_MAX_DB, 0.0001)


func test_buzz_loops_while_crossings_exist_and_fades_when_resolved() -> void:
	var level := _level()
	var model := level.get_controller().get_model()
	# m01 starts tangled.
	assert_bool(_director.is_buzz_playing()).is_true()
	model.crossing_points_changed.emit(PackedVector2Array([Vector2.ONE, Vector2.ZERO, Vector2.ONE]))
	assert_float(_director.get_buzz_target_db()).is_equal_approx(AudioDirector.buzz_volume_db(3), 0.0001)
	model.crossing_points_changed.emit(PackedVector2Array())
	assert_bool(_director.is_buzz_playing()).is_false()
	assert_float(_director.get_buzz_target_db()).is_equal(AudioDirector.SILENT_DB)


## T7.2: rising alarm with lethal-wall proximity; overload explosion.
func test_alarm_rises_with_proximity() -> void:
	assert_bool(AudioDirector.is_alarm_audible(0.0)).is_false()
	assert_bool(AudioDirector.is_alarm_audible(0.5)).is_true()
	assert_float(AudioDirector.alarm_pitch(1.0)).is_greater(AudioDirector.alarm_pitch(0.3))
	assert_float(AudioDirector.alarm_volume_db(1.0)).is_equal_approx(AudioDirector.ALARM_MAX_DB, 0.0001)
	assert_float(AudioDirector.alarm_volume_db(0.4)).is_less(AudioDirector.alarm_volume_db(0.9))


func test_alarm_follows_the_proximity_and_stops_on_release() -> void:
	var level := _level()
	var model := level.get_controller().get_model()
	model.hazard_proximity_changed.emit(0, 0.8)
	assert_bool(_director.is_alarm_playing()).is_true()
	assert_float(_director.get_player(&"alarm").pitch_scale) \
		.is_equal_approx(AudioDirector.alarm_pitch(0.8), 0.0001)
	model.hazard_proximity_changed.emit(0, 0.0)
	assert_bool(_director.is_alarm_playing()).is_false()
	model.hazard_proximity_changed.emit(0, 0.9)
	level.get_input_controller().grab_ended.emit(0)
	assert_bool(_director.is_alarm_playing()).is_false()


func test_destroyed_neuron_explodes_and_silences_the_alarm() -> void:
	var level := _level()
	var model := level.get_controller().get_model()
	model.hazard_proximity_changed.emit(0, 0.95)
	model.neuron_destroyed.emit(0, Vector2.ZERO)
	assert_bool(_played().has(&"explode")).is_true()
	assert_bool(_director.is_alarm_playing()).is_false()


## T7.3: synaptic click when a receptor link forms, a small snap when it breaks.
func test_link_formation_clicks_and_breaking_snaps() -> void:
	var level := _level()
	var model := level.get_controller().get_model()
	model.link_formed.emit(0, 1)
	assert_bool(_played().has(&"link")).is_true()
	model.link_broken.emit(0, 1)
	assert_bool(_played().has(&"unlink")).is_true()


func test_completion_chord_and_star_pings() -> void:
	var level := _level()
	level.get_controller().level_completed.emit(LevelResult.create(4, 20.0, 6, 60.0))
	assert_bool(_played().has(&"complete")).is_true()
	level.get_hud().star_revealed.emit(2)
	assert_bool(_played().has(&"star")).is_true()
	assert_float(_director.get_player(&"star").pitch_scale).is_equal_approx(AudioDirector.star_pitch(2), 0.0001)


func test_restart_rebinds_the_new_model() -> void:
	var level := _level()
	level.get_controller().restart()
	level.get_controller().get_model().edge_broke.emit(0)
	assert_bool(_played().has(&"snap")).is_true()


# --- UI ---------------------------------------------------------------------------

func test_ui_buttons_click_and_hover() -> void:
	var menu: MainMenu = auto_free(MainMenuScene.instantiate())
	add_child(menu)
	_director.bind_ui(menu)
	# The focus grabbed when a screen opens is not a hover.
	assert_bool(_played().has(&"ui_hover")).is_false()
	menu.get_play_button().pressed.emit()
	assert_bool(_played().has(&"ui_click")).is_true()
	menu.get_settings_button().mouse_entered.emit()
	assert_bool(_played().has(&"ui_hover")).is_false()
	while _director.is_ui_quiet():
		await await_idle_frame()
	menu.get_settings_button().mouse_entered.emit()
	assert_bool(_played().has(&"ui_hover")).is_true()


func test_binding_twice_does_not_double_sounds() -> void:
	var menu: MainMenu = auto_free(MainMenuScene.instantiate())
	add_child(menu)
	_director.bind_ui(menu)
	_director.bind_ui(menu)
	menu.get_play_button().pressed.emit()
	assert_int(_played().count(&"ui_click")).is_equal(1)


func test_main_wires_the_director_into_every_screen() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	add_child(main)
	var director: AudioDirector = main.get_node(^"AudioDirector")
	var host: ScreenHost = main.get_screen_host()
	assert_object(host.audio).is_same(director)
	var recorder := SignalRecorder.new()
	recorder.watch(director, [&"sound_played"])
	(host.get_current_node() as MainMenu).get_play_button().pressed.emit()
	assert_int(recorder.count(&"sound_played")).is_equal(1)
	host.play_mission(&"m01")
	var level := host.get_current_node() as Level
	level.get_input_controller().grab_started.emit(0)
	assert_array(recorder.last_args(&"sound_played")).is_equal([&"grab"])
