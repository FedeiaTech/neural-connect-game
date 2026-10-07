extends GdUnitTestSuite
## T4.5: level summary — stars light up one by one (each announced for its sound), moves and
## time count up, a light wave sweeps across; all instant with reduced motion.

const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const HudScene := preload("res://scenes/ui/hud.tscn")

var _hud: Hud
var _recorder: SignalRecorder
var _saved_reduced_motion := false


func before_test() -> void:
	_saved_reduced_motion = GameState.reduced_motion
	GameState.reduced_motion = false
	_hud = auto_free(HudScene.instantiate())
	add_child(_hud)
	_recorder = SignalRecorder.new()
	_recorder.watch(_hud, [&"star_revealed"])


func after_test() -> void:
	GameState.reduced_motion = _saved_reduced_motion


func _three_stars() -> LevelResult:
	return LevelResult.create(4, 32.0, 6, 60.0)


func test_star_reveal_schedule_is_one_after_another() -> void:
	var times := Hud.star_reveal_times(3)
	assert_int(times.size()).is_equal(3)
	assert_float(times[0]).is_equal_approx(Hud.STAR_START, 0.0001)
	assert_float(times[1] - times[0]).is_equal_approx(Hud.STAR_INTERVAL, 0.0001)
	assert_float(times[2] - times[1]).is_equal_approx(Hud.STAR_INTERVAL, 0.0001)
	assert_int(Hud.star_reveal_times(0).size()).is_equal(0)


func test_count_up_text_interpolates_moves_and_time() -> void:
	assert_str(Hud.stats_text(8, 61.0, 0.0)).is_equal("Moves 0    Time 00:00")
	assert_str(Hud.stats_text(8, 61.0, 0.5)).is_equal("Moves 4    Time 00:30")
	assert_str(Hud.stats_text(8, 61.0, 1.0)).is_equal("Moves 8    Time 01:01")


func test_stars_light_one_by_one_with_motion() -> void:
	_hud.show_completion(_three_stars())
	assert_int(_hud.get_star_count()).is_equal(3)
	assert_int(_hud.get_lit_star_count()).is_equal(0)
	assert_str(_hud.get_completion_stats_text()).contains("Moves 0")
	assert_bool(_hud.is_sweeping()).is_true()
	var times := Hud.star_reveal_times(3)
	await await_millis(int((times[0] + Hud.STAR_INTERVAL * 0.5) * 1000.0))
	assert_int(_hud.get_lit_star_count()).is_equal(1)
	await await_millis(int((Hud.STAR_INTERVAL * 2.0 + Hud.COUNT_TIME) * 1000.0) + 200)
	assert_int(_hud.get_lit_star_count()).is_equal(3)
	assert_int(_recorder.count(&"star_revealed")).is_equal(3)
	assert_array(_recorder.args_of(&"star_revealed")).is_equal([[0], [1], [2]])
	assert_str(_hud.get_completion_stats_text()).is_equal("Moves 4    Time 00:32")


func test_reduced_motion_shows_the_summary_at_once() -> void:
	GameState.reduced_motion = true
	_hud.show_completion(_three_stars())
	assert_int(_hud.get_lit_star_count()).is_equal(3)
	assert_int(_recorder.count(&"star_revealed")).is_equal(3)
	assert_str(_hud.get_completion_stats_text()).is_equal("Moves 4    Time 00:32")
	assert_bool(_hud.is_sweeping()).is_false()


func test_hiding_the_summary_stops_the_reveal() -> void:
	_hud.show_completion(_three_stars())
	_hud.hide_completion()
	await await_millis(int((Hud.star_reveal_times(3)[2] + 0.2) * 1000.0))
	assert_int(_recorder.count(&"star_revealed")).is_equal(0)


func test_one_star_result_reveals_a_single_star() -> void:
	GameState.reduced_motion = true
	_hud.show_completion(LevelResult.create(30, 500.0, 6, 60.0))
	assert_int(_hud.get_lit_star_count()).is_equal(1)
	assert_int(_recorder.count(&"star_revealed")).is_equal(1)


func test_hud_buttons_are_glow_buttons() -> void:
	assert_object(_hud.get_restart_button()).is_instanceof(GlowButton)
	assert_object(_hud.get_replay_button()).is_instanceof(GlowButton)
	assert_object(_hud.get_resume_button()).is_instanceof(GlowButton)
