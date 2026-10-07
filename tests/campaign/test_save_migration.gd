extends GdUnitTestSuite
## T7.4: save format v2. The campaign gained two chapters before Convergence, so the old
## Convergence missions m19/m20/m21 are now m26/m28/m30. A v1 save is migrated on load so
## players keep their records under the new ids; newer saves are left as they are.

const GameStateScript := preload("res://scripts/autoloads/game_state.gd")
const TEMP_PATH := "user://test_migration.json"

var _state: Node


func before_test() -> void:
	_delete_temp()


func after_test() -> void:
	_delete_temp()
	GameState.apply_settings()


func _delete_temp() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with(TEMP_PATH.get_file()):
			dir.remove(file)


func _load(data: Dictionary) -> Node:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var state: Node = auto_free(GameStateScript.new())
	state.save_path = TEMP_PATH
	state.load_game()
	return state


static func _entry(stars: int, moves: int, time: float) -> Dictionary:
	return {"completed": true, "stars": stars, "moves": moves, "time": time}


## Old ids m01..m21 all completed.
static func _v1_all_completed() -> Dictionary:
	var missions := {}
	for i in range(1, 22):
		missions["m%02d" % i] = _entry(3, 10 + i, 30.0 + i)
	return {"version": 1, "progress": {"missions": missions}, "settings": {"language": "en"}}


func test_save_version_is_two_with_the_documented_id_map() -> void:
	assert_int(GameStateScript.SAVE_VERSION).is_equal(2)
	assert_dict(GameStateScript.V1_MISSION_ID_MAP).is_equal({"m19": "m26", "m20": "m28", "m21": "m30"})


func test_migrate_renames_only_the_moved_missions() -> void:
	var migrated: Dictionary = GameStateScript.migrate_save(_v1_all_completed())
	assert_int(int(migrated["version"])).is_equal(2)
	var missions: Dictionary = migrated["progress"]["missions"]
	assert_bool(missions.has("m18")).is_true()
	assert_bool(missions.has("m19")).is_false()
	assert_bool(missions.has("m20")).is_false()
	assert_bool(missions.has("m21")).is_false()
	assert_dict(missions["m26"]).is_equal(_entry(3, 29, 49.0))
	assert_dict(missions["m28"]).is_equal(_entry(3, 30, 50.0))
	assert_dict(missions["m30"]).is_equal(_entry(3, 31, 51.0))


func test_migrate_keeps_unknown_mission_keys_and_other_fields() -> void:
	var data := {"version": 1, "extra": "x",
		"progress": {"missions": {"m20": {"completed": true, "stars": 2, "moves": 9, "time": 12.0, "note": 7}}}}
	var migrated: Dictionary = GameStateScript.migrate_save(data)
	assert_str(migrated["extra"]).is_equal("x")
	assert_int(migrated["progress"]["missions"]["m28"]["note"]).is_equal(7)


func test_newer_saves_are_not_renamed() -> void:
	var data := {"version": 2, "progress": {"missions": {"m19": _entry(1, 5, 5.0)}}}
	var migrated: Dictionary = GameStateScript.migrate_save(data)
	assert_bool(migrated["progress"]["missions"].has("m19")).is_true()


func test_loading_a_v1_save_keeps_progress_under_the_new_ids() -> void:
	var state := _load(_v1_all_completed())
	var progress: Progress = state.progress
	assert_bool(progress.is_completed(&"m26")).is_true()
	assert_int(progress.get_best_moves(&"m28")).is_equal(30)
	assert_float(progress.get_best_time(&"m30")).is_equal(51.0)
	# The new Live Wires and Synapses missions are not completed...
	for id in [&"m19", &"m20", &"m21", &"m22", &"m25", &"m27", &"m29"]:
		assert_bool(progress.is_completed(id)).override_failure_message(String(id)).is_false()
	# ...but the first one is unlocked (m18 done) and the migrated ones stay playable.
	assert_bool(state.is_unlocked(&"m19")).is_true()
	assert_bool(state.is_unlocked(&"m20")).is_false()
	assert_bool(state.is_unlocked(&"m26")).is_true()
	assert_bool(state.is_unlocked(&"m27")).is_true()


func test_the_migrated_save_is_written_as_v2() -> void:
	var state := _load(_v1_all_completed())
	state.save_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH))
	assert_int(int(data["version"])).is_equal(2)
	assert_bool(data["progress"]["missions"].has("m30")).is_true()
	assert_bool(data["progress"]["missions"].has("m21")).is_false()
