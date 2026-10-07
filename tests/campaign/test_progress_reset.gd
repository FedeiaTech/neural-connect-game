extends GdUnitTestSuite
## T6.1: resetting the whole campaign progress or one mission's record. Settings survive, the
## save is rewritten at once and progress_changed is emitted. Uses a fresh GameState instance
## with a temp save path (same pattern as test_game_state_save.gd).

const GameStateScript := preload("res://scripts/autoloads/game_state.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const TEMP_PATH := "user://test_reset_progress.json"

var _state: Node
var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	_delete_temp()
	_state = _new_state()


func after_test() -> void:
	_delete_temp()
	GameState.apply_settings()
	TranslationServer.set_locale(_locale)


func _new_state() -> Node:
	var state: Node = auto_free(GameStateScript.new())
	state.save_path = TEMP_PATH
	state.load_game()
	return state


func _delete_temp() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with(TEMP_PATH.get_file()):
			dir.remove(file)


func _write_temp(data: Dictionary) -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _read_saved() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH))


func _result(moves: int, time: float, stars: int) -> LevelResult:
	var result := LevelResult.new()
	result.moves = moves
	result.time = time
	result.stars = stars
	return result


func _complete(ids: Array[StringName]) -> void:
	for id in ids:
		_state.record_result(id, _result(5, 30.0, 3))


# --- Progress -------------------------------------------------------------------

func test_progress_erase_forgets_one_mission() -> void:
	var progress := Progress.new()
	progress.record(&"m01", 3, 5, 30.0)
	progress.record(&"m02", 2, 7, 40.0)
	progress.erase(&"m01")
	assert_bool(progress.is_completed(&"m01")).is_false()
	assert_int(progress.get_best_stars(&"m01")).is_equal(0)
	assert_int(progress.get_best_moves(&"m01")).is_equal(Progress.NO_MOVES)
	assert_float(progress.get_best_time(&"m01")).is_equal(Progress.NO_TIME)
	assert_bool(progress.is_completed(&"m02")).is_true()
	assert_bool(progress.to_dict()["missions"].has("m01")).is_false()


func test_progress_clear_forgets_everything() -> void:
	var progress := Progress.new()
	progress.record(&"m01", 3, 5, 30.0)
	progress.record(&"m02", 2, 7, 40.0)
	progress.clear()
	assert_int(progress.get_completed_count()).is_equal(0)
	assert_dict(progress.to_dict()).is_equal({"missions": {}})


# --- reset_progress -------------------------------------------------------------

func test_reset_progress_locks_everything_but_the_first_mission() -> void:
	_complete([&"m01", &"m02", &"m03"])
	_state.reset_progress()
	assert_int(_state.progress.get_completed_count()).is_equal(0)
	assert_bool(_state.is_unlocked(&"m01")).is_true()
	assert_bool(_state.is_unlocked(&"m02")).is_false()
	assert_bool(_state.is_unlocked(&"m04")).is_false()


func test_reset_progress_saves_and_keeps_settings() -> void:
	_state.set_master_volume(0.3)
	_state.set_reduced_motion(true)
	_complete([&"m01", &"m02"])
	_state.reset_progress()
	var reloaded := _new_state()
	assert_int(reloaded.progress.get_completed_count()).is_equal(0)
	assert_float(reloaded.master_volume).is_equal_approx(0.3, 0.0001)
	assert_bool(reloaded.reduced_motion).is_true()
	assert_dict(_read_saved()["progress"]["missions"]).is_empty()


func test_reset_progress_emits_progress_changed() -> void:
	_complete([&"m01"])
	var recorder := SignalRecorder.new()
	recorder.watch(_state, [&"progress_changed"])
	_state.reset_progress()
	assert_int(recorder.count(&"progress_changed")).is_equal(1)


## Mission entries are removed completely, unknown per-mission keys and unknown (newer)
## missions included; unknown fields outside the mission records survive.
func test_reset_progress_drops_unknown_mission_data_but_keeps_other_fields() -> void:
	_write_temp({
		"version": 1,
		"cloud": {"id": 3},
		"progress": {
			"streak": 4,
			"missions": {
				"m01": {"completed": true, "stars": 2, "moves": 5, "time": 30.0, "ghost": "x"},
				"m77": {"completed": true, "stars": 1, "moves": 9, "time": 90.0},
			},
		},
		"settings": {"master_volume": 0.5, "reduced_motion": false, "future": "y"},
	})
	var state := _new_state()
	state.reset_progress()
	var data := _read_saved()
	assert_dict(data["progress"]["missions"]).is_empty()
	assert_int(int(data["progress"]["streak"])).is_equal(4)
	assert_dict(data["cloud"]).is_equal({"id": 3.0})
	assert_str(data["settings"]["future"]).is_equal("y")
	assert_int(_new_state().progress.get_completed_count()).is_equal(0)


# --- reset_mission --------------------------------------------------------------

func test_reset_mission_clears_only_that_record() -> void:
	_complete([&"m01", &"m02"])
	_state.reset_mission(&"m02")
	assert_bool(_state.progress.is_completed(&"m02")).is_false()
	assert_int(_state.progress.get_best_stars(&"m02")).is_equal(0)
	assert_bool(_state.progress.is_completed(&"m01")).is_true()
	# m02 stays playable (m01 is completed); m03 locks again (it was only unlocked by m02).
	assert_bool(_state.is_unlocked(&"m02")).is_true()
	assert_bool(_state.is_unlocked(&"m03")).is_false()


func test_reset_mission_keeps_later_completed_missions_unlocked() -> void:
	_complete([&"m01", &"m02", &"m03", &"m04"])
	_state.reset_mission(&"m02")
	assert_bool(_state.is_unlocked(&"m03")).is_true()
	assert_bool(_state.is_unlocked(&"m04")).is_true()
	assert_bool(_state.is_unlocked(&"m05")).is_true()


func test_reset_mission_saves_drops_unknown_keys_and_emits() -> void:
	_write_temp({
		"version": 1,
		"progress": {"missions": {
			"m01": {"completed": true, "stars": 2, "moves": 5, "time": 30.0, "ghost": "x"},
			"m02": {"completed": true, "stars": 3, "moves": 6, "time": 40.0, "ghost": "y"},
		}},
	})
	var state := _new_state()
	var recorder := SignalRecorder.new()
	recorder.watch(state, [&"progress_changed"])
	state.reset_mission(&"m01")
	assert_int(recorder.count(&"progress_changed")).is_equal(1)
	var missions: Dictionary = _read_saved()["progress"]["missions"]
	assert_bool(missions.has("m01")).is_false()
	assert_str(missions["m02"]["ghost"]).is_equal("y")
	assert_bool(_new_state().progress.is_completed(&"m01")).is_false()


func test_reset_mission_ignores_unknown_missions() -> void:
	_complete([&"m01"])
	var recorder := SignalRecorder.new()
	recorder.watch(_state, [&"progress_changed"])
	_state.reset_mission(&"missing")
	assert_int(recorder.count(&"progress_changed")).is_equal(0)
	assert_bool(_state.progress.is_completed(&"m01")).is_true()
