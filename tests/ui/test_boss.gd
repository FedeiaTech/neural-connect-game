extends GdUnitTestSuite
## T8.6: boss missions. The intro card sequencing (also with reduced motion), the BOSS tag, the
## boss look of the membrane and vignette, the fanfare, the mission-map node and its sounds.

const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const LevelScene := preload("res://scenes/level/level.tscn")
const LevelFactory := preload("res://tests/model/level_factory.gd")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")

var _sandbox: Sandbox
var _level: Level


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)


func after_test() -> void:
	get_tree().paused = false
	_sandbox.exit()
	await await_idle_frame()


func _data(boss: bool, story := "") -> LevelData:
	var data := LevelFactory.x_level()
	data.mission_name = "MISSION_M31_NAME"
	data.story_text = story
	data.is_boss = boss
	return data


# --- Pure helpers ------------------------------------------------------------

func test_card_alpha_fades_in_holds_and_fades_out() -> void:
	var duration := BossIntro.DURATION
	assert_float(BossIntro.card_alpha(0.0, duration)).is_equal(0.0)
	assert_float(BossIntro.card_alpha(BossIntro.FADE_IN, duration)).is_equal(1.0)
	assert_float(BossIntro.card_alpha(duration * 0.5, duration)).is_equal(1.0)
	assert_float(BossIntro.card_alpha(duration - BossIntro.FADE_OUT * 0.5, duration)).is_equal_approx(0.5, 0.001)
	assert_float(BossIntro.card_alpha(duration, duration)).is_equal(0.0)


func test_sweep_eases_from_zero_to_one() -> void:
	assert_float(BossIntro.sweep(0.0)).is_equal(0.0)
	assert_float(BossIntro.sweep(10.0)).is_equal(1.0)
	assert_float(BossIntro.sweep(BossIntro.FADE_IN)).is_between(0.5, 1.0)


# --- Intro sequencing ---------------------------------------------------------

func test_a_boss_waits_in_intro_even_without_a_story() -> void:
	_level.load_level(_data(true))
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.INTRO)
	assert_bool(_level.get_hud().is_boss_tag_visible()).is_true()
	assert_bool(_level.get_hud().is_story_visible()).is_false()


func test_a_regular_mission_has_no_boss_ui() -> void:
	_level.load_level(_data(false))
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)
	assert_bool(_level.get_hud().is_boss_tag_visible()).is_false()
	await await_idle_frame()
	assert_bool(_level.get_hud().is_boss_intro_visible()).is_false()
	assert_str(_level.get_hud().get_completion_title_text()).is_equal("Network restored")


func test_the_intro_card_opens_one_frame_later_and_announces_itself() -> void:
	var recorder := SignalRecorder.new()
	recorder.watch(_level, [&"boss_intro_started"])
	_level.load_level(_data(true))
	assert_bool(_level.get_hud().is_boss_intro_visible()).is_false()
	await await_idle_frame()
	assert_bool(_level.get_hud().is_boss_intro_visible()).is_true()
	assert_int(recorder.count(&"boss_intro_started")).is_equal(1)
	assert_str(_level.get_hud().get_boss_intro().get_title_key()).is_equal("MISSION_M31_NAME")


func test_reduced_motion_plays_a_short_still_card_then_starts() -> void:
	GameState.reduced_motion = true
	_level.load_level(_data(true))
	await await_idle_frame()
	var intro := _level.get_hud().get_boss_intro()
	assert_float(intro.get_duration()).is_equal(BossIntro.REDUCED_DURATION)
	intro.advance(BossIntro.REDUCED_DURATION + 0.01)
	assert_bool(intro.is_playing()).is_false()
	assert_bool(_level.get_hud().is_boss_intro_visible()).is_false()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)


func test_full_motion_uses_the_full_duration() -> void:
	GameState.reduced_motion = false
	_level.load_level(_data(true))
	await await_idle_frame()
	var intro := _level.get_hud().get_boss_intro()
	assert_float(intro.get_duration()).is_equal(BossIntro.DURATION)
	intro.advance(BossIntro.DURATION * 0.5)
	assert_bool(intro.is_playing()).is_true()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.INTRO)
	intro.advance(BossIntro.DURATION)
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)


func test_the_story_follows_the_card_and_is_dismissed_into_play() -> void:
	_level.load_level(_data(true, "MISSION_M31_STORY"))
	await await_idle_frame()
	assert_bool(_level.get_hud().is_story_visible()).is_false()
	_level.get_hud().get_boss_intro().advance(10.0)
	assert_bool(_level.get_hud().is_story_visible()).is_true()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.INTRO)
	_level.get_hud().story_dismissed.emit()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)


func test_skipping_needs_a_moment_of_viewing() -> void:
	GameState.reduced_motion = false
	_level.load_level(_data(true))
	await await_idle_frame()
	var intro := _level.get_hud().get_boss_intro()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	intro._gui_input(click)
	assert_bool(intro.is_playing()).is_true()
	intro.advance(BossIntro.SKIP_AFTER + 0.05)
	intro._gui_input(click)
	assert_bool(intro.is_playing()).is_false()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)


func test_a_newer_load_cancels_a_pending_intro() -> void:
	_level.load_level(_data(true))
	_level.load_level(_data(false))
	await await_idle_frame()
	assert_bool(_level.get_hud().is_boss_intro_visible()).is_false()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)


func test_restart_does_not_replay_the_intro() -> void:
	_level.load_level(_data(true))
	await await_idle_frame()
	_level.get_hud().get_boss_intro().advance(10.0)
	_level.get_controller().restart()
	await await_idle_frame()
	assert_bool(_level.get_hud().is_boss_intro_visible()).is_false()
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.PLAYING)


# --- Boss look and completion -----------------------------------------------------

func test_the_membrane_and_vignette_take_the_boss_look() -> void:
	_level.load_level(_data(true))
	var boundary: BoundaryView = _level.get_node("Playfield/Boundary")
	var background: BackgroundView = _level.get_node("Background")
	assert_bool(boundary.is_boss_look()).is_true()
	assert_object(boundary.get_color()).is_equal(Palette.BOSS_MEMBRANE)
	assert_bool(background.is_boss_look()).is_true()
	_level.load_level(_data(false))
	assert_bool(boundary.is_boss_look()).is_false()
	assert_object(boundary.get_color()).is_equal(Palette.BOUNDARY)
	assert_bool(background.is_boss_look()).is_false()


func test_a_boss_completion_is_titled_and_has_a_longer_wave() -> void:
	GameState.reduced_motion = false
	_level.load_level(_data(true))
	await await_idle_frame()
	_level.get_hud().get_boss_intro().advance(10.0)
	var fx: LevelFx = _level.get_node("Playfield/Fx")
	var boss_wave := fx.play_completion_wave(true)
	var plain_wave := fx.play_completion_wave(false)
	assert_float(boss_wave).is_greater(plain_wave)
	assert_str(_level.get_hud().get_completion_title_text()).is_equal("Boss defeated")


func test_stinger_and_fanfare_sound() -> void:
	GameState.reduced_motion = true
	var director: AudioDirector = auto_free(AudioDirector.new())
	add_child(director)
	var recorder := SignalRecorder.new()
	recorder.watch(director, [&"sound_played"])
	_level.load_level(_data(true))
	director.bind_level(_level)
	await await_idle_frame()
	var names: Array[StringName] = []
	for args in recorder.args_of(&"sound_played"):
		names.append(args[0])
	assert_bool(names.has(&"boss_stinger")).is_true()
	_level.get_hud().get_boss_intro().advance(10.0)
	var model := _level.get_controller().get_model()
	model.grab(1)
	model.drag_to(Vector2(100, 300))
	model.release()
	names.clear()
	for args in recorder.args_of(&"sound_played"):
		names.append(args[0])
	assert_bool(model.is_solved()).is_true()
	assert_bool(names.has(&"complete")).is_true()
	assert_bool(names.has(&"boss_fanfare")).is_true()


func test_a_regular_completion_has_no_fanfare() -> void:
	var director: AudioDirector = auto_free(AudioDirector.new())
	add_child(director)
	var recorder := SignalRecorder.new()
	recorder.watch(director, [&"sound_played"])
	_level.load_level(_data(false))
	director.bind_level(_level)
	var model := _level.get_controller().get_model()
	model.grab(1)
	model.drag_to(Vector2(100, 300))
	model.release()
	for args in recorder.args_of(&"sound_played"):
		assert_bool(args[0] == &"boss_fanfare").is_false()


# --- Mission map node ---------------------------------------------------------------

func test_boss_nodes_are_bigger_with_a_crown() -> void:
	var regular := MissionNode.new()
	var boss := MissionNode.new()
	auto_free(regular)
	auto_free(boss)
	regular.setup(&"a", 1, MissionNode.State.UNLOCKED, 0, "A")
	boss.setup(&"b", 2, MissionNode.State.UNLOCKED, 0, "B", true)
	assert_bool(boss.is_boss).is_true()
	assert_float(boss.get_radius()).is_greater(regular.get_radius())
	assert_float(boss.custom_minimum_size.x).is_greater(regular.custom_minimum_size.x)
	assert_float(boss.get_name_offset()).is_greater(regular.get_name_offset())


func test_boss_nodes_use_their_own_hover_and_press_sounds() -> void:
	var director: AudioDirector = auto_free(AudioDirector.new())
	add_child(director)
	var recorder := SignalRecorder.new()
	recorder.watch(director, [&"sound_played"])
	var holder := Control.new()
	auto_free(holder)
	add_child(holder)
	var boss := MissionNode.new()
	boss.setup(&"b", 2, MissionNode.State.UNLOCKED, 0, "B", true)
	var plain := MissionNode.new()
	plain.setup(&"a", 1, MissionNode.State.UNLOCKED, 0, "A")
	holder.add_child(boss)
	holder.add_child(plain)
	director.bind_ui(holder)
	await await_millis(int(AudioDirector.UI_QUIET_TIME * 1000.0) + 100)
	boss.mouse_entered.emit()
	boss.pressed.emit()
	plain.mouse_entered.emit()
	plain.pressed.emit()
	var names: Array[StringName] = []
	for args in recorder.args_of(&"sound_played"):
		names.append(args[0])
	assert_array(names).contains([&"boss_hover", &"boss_press", &"ui_hover", &"ui_click"])


func test_a_boss_press_kicks_the_node_and_reduced_motion_does_not() -> void:
	GameState.reduced_motion = false
	var holder := Control.new()
	auto_free(holder)
	add_child(holder)
	var boss := MissionNode.new()
	boss.setup(&"b", 2, MissionNode.State.UNLOCKED, 0, "B", true)
	holder.add_child(boss)
	boss.button_down.emit()
	assert_float(boss._kick).is_greater(0.0)
	GameState.reduced_motion = true
	boss.button_down.emit()
	assert_float(boss._kick).is_equal(0.0)


func test_chapter_headers_have_distinct_accents_and_seeds() -> void:
	var accents := {}
	var seeds := {}
	for id in range(1, 10):
		accents[ChapterHeader.accent_for(id)] = true
		seeds[ChapterHeader.seed_for(id)] = true
	assert_int(accents.size()).is_equal(9)
	assert_int(seeds.size()).is_equal(9)
