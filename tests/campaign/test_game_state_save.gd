extends GdUnitTestSuite
## T3.2: GameState records results, unlocks missions in campaign order and persists progress and
## settings as versioned JSON. Uses a fresh GameState instance with a temp save path, so neither
## the autoload nor the real user://progress.json is touched.

const GameStateScript := preload("res://scripts/autoloads/game_state.gd")
const TEMP_PATH := "user://test_progress.json"

var _state: Node


func before_test() -> void:
	_delete_temp()
	_state = _new_state()


func after_test() -> void:
	_delete_temp()
	# Settings are applied to the master bus; put the autoload's values back.
	GameState.apply_settings()


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


func _read_saved() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH))


func _write_temp(text: String) -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _result(moves: int, time: float, stars: int) -> LevelResult:
	var result := LevelResult.new()
	result.moves = moves
	result.time = time
	result.stars = stars
	return result


func test_exposes_the_campaign_and_levels() -> void:
	assert_object(_state.campaign).is_not_null()
	assert_str(String(_state.get_level(&"m01").mission_id)).is_equal("m01")
	assert_object(_state.get_level(&"missing")).is_null()
	assert_str(String(_state.next_mission_after(&"m01"))).is_equal("m02")
	assert_str(String(_state.next_mission_after(&"m02"))).is_empty()


func test_only_the_first_mission_starts_unlocked() -> void:
	assert_bool(_state.is_unlocked(&"m01")).is_true()
	assert_bool(_state.is_unlocked(&"m02")).is_false()
	assert_bool(_state.is_unlocked(&"missing")).is_false()


func test_completing_a_mission_unlocks_the_next_one() -> void:
	_state.record_result(&"m01", _result(5, 30.0, 3))
	assert_bool(_state.progress.is_completed(&"m01")).is_true()
	assert_bool(_state.is_unlocked(&"m02")).is_true()


func test_record_result_keeps_best_values_and_saves() -> void:
	_state.record_result(&"m01", _result(5, 50.0, 2))
	_state.record_result(&"m01", _result(9, 20.0, 1))
	assert_bool(FileAccess.file_exists(TEMP_PATH)).is_true()
	var reloaded := _new_state()
	assert_int(reloaded.progress.get_best_stars(&"m01")).is_equal(2)
	assert_int(reloaded.progress.get_best_moves(&"m01")).is_equal(5)
	assert_float(reloaded.progress.get_best_time(&"m01")).is_equal(20.0)
	assert_bool(reloaded.is_unlocked(&"m02")).is_true()


func test_record_result_ignores_unknown_missions() -> void:
	_state.record_result(&"missing", _result(1, 1.0, 3))
	assert_int(_state.progress.get_completed_count()).is_equal(0)


func test_save_file_is_versioned_json() -> void:
	_state.record_result(&"m01", _result(5, 30.0, 3))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH))
	assert_bool(data is Dictionary).is_true()
	assert_int(int(data["version"])).is_equal(GameStateScript.SAVE_VERSION)
	assert_bool(data["progress"]["missions"].has("m01")).is_true()
	assert_bool(data.has("settings")).is_true()
	assert_bool(FileAccess.file_exists(TEMP_PATH + ".tmp")).is_false()


func test_missing_file_gives_fresh_progress() -> void:
	assert_int(_state.progress.get_completed_count()).is_equal(0)
	assert_float(_state.master_volume).is_equal(1.0)
	assert_bool(_state.reduced_motion).is_false()


func test_corrupt_file_gives_fresh_progress() -> void:
	for text in ["{ not json", "[1, 2, 3]", "", "{\"version\": \"x\", \"progress\": 5}"]:
		_write_temp(text)
		var state := _new_state()
		assert_int(state.progress.get_completed_count()).override_failure_message(text).is_equal(0)
		assert_bool(state.is_unlocked(&"m01")).is_true()


func test_unusable_save_is_backed_up_before_it_can_be_overwritten() -> void:
	for text in ["{ not json", "{\"no_version\": true}"]:
		_delete_temp()
		_write_temp(text)
		var state := _new_state()
		assert_str(FileAccess.get_file_as_string(TEMP_PATH + ".bak")).override_failure_message(text) \
			.is_equal(text)
		state.record_result(&"m01", _result(5, 30.0, 3))
		assert_str(FileAccess.get_file_as_string(TEMP_PATH + ".bak")).is_equal(text)


func test_missing_save_creates_no_backup() -> void:
	assert_bool(FileAccess.file_exists(TEMP_PATH + ".bak")).is_false()


func test_newer_save_keeps_its_version_and_unknown_fields() -> void:
	_write_temp(JSON.stringify({
		"version": 99,
		"cloud": {"id": 3},
		"progress": {
			"streak": 4,
			"missions": {
				"m01": {"completed": true, "stars": 2, "moves": 5, "time": 30.0, "ghost": "x"},
				"m77": {"completed": true, "stars": 1, "moves": 9, "time": 90.0},
			},
		},
		"settings": {"master_volume": 0.5, "reduced_motion": false, "future": "y"},
	}))
	var state := _new_state()
	assert_int(state.progress.get_best_stars(&"m01")).is_equal(2)
	state.record_result(&"m01", _result(4, 20.0, 3))
	var data := _read_saved()
	assert_int(int(data["version"])).is_equal(99)
	assert_dict(data["cloud"]).is_equal({"id": 3.0})
	assert_int(int(data["progress"]["streak"])).is_equal(4)
	var m01: Dictionary = data["progress"]["missions"]["m01"]
	assert_str(m01["ghost"]).is_equal("x")
	assert_int(int(m01["stars"])).is_equal(3)
	assert_bool(data["progress"]["missions"].has("m77")).is_true()
	assert_str(data["settings"]["future"]).is_equal("y")
	assert_float(float(data["settings"]["master_volume"])).is_equal_approx(0.5, 0.0001)


func test_current_save_never_downgrades_below_save_version() -> void:
	_write_temp(JSON.stringify({"version": 1, "progress": {"missions": {}}, "extra": 1}))
	var state := _new_state()
	state.set_reduced_motion(true)
	var data := _read_saved()
	assert_int(int(data["version"])).is_equal(GameStateScript.SAVE_VERSION)
	assert_int(int(data["extra"])).is_equal(1)


func test_settings_persist_and_are_clamped() -> void:
	_state.set_master_volume(0.4)
	_state.set_reduced_motion(true)
	var reloaded := _new_state()
	assert_float(reloaded.master_volume).is_equal_approx(0.4, 0.0001)
	assert_bool(reloaded.reduced_motion).is_true()
	_state.set_master_volume(3.0)
	assert_float(_state.master_volume).is_equal(1.0)
	_state.set_master_volume(-1.0)
	assert_float(_state.master_volume).is_equal(0.0)


func test_master_volume_drives_the_master_bus() -> void:
	_state.set_master_volume(0.5)
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal_approx(linear_to_db(0.5), 0.01)
	assert_bool(AudioServer.is_bus_mute(0)).is_false()
	_state.set_master_volume(0.0)
	assert_bool(AudioServer.is_bus_mute(0)).is_true()


func test_settings_survive_while_progress_is_recorded() -> void:
	_state.set_reduced_motion(true)
	_state.record_result(&"m01", _result(5, 30.0, 3))
	assert_bool(_new_state().reduced_motion).is_true()
