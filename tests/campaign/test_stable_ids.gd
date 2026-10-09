extends GdUnitTestSuite
## T8.4: the campaign was reorganized (nine chapters, bosses, new missions m31..m48) WITHOUT
## renumbering: mission ids are stable and never encode the position, so saved progress keeps its
## meaning and the save format stays at v2 (no migration needed). These tests pin that promise.

const GameStateScript := preload("res://scripts/autoloads/game_state.gd")
const TEMP_PATH := "user://test_stable_ids.json"


func after_test() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		for file in dir.get_files():
			if file.begins_with(TEMP_PATH.get_file()):
				dir.remove(file)
	GameState.apply_settings()


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


## A v2 save as the previous game version wrote it: m01..m30 all completed.
static func _old_v2_save() -> Dictionary:
	var missions := {}
	for i in range(1, 31):
		missions["m%02d" % i] = _entry(2, 10 + i, 40.0 + i)
	return {"version": 2, "progress": {"missions": missions},
		"settings": {"language": "en", "master_volume": 0.5}, "future_field": {"keep": [1, 2, 3]}}


func test_save_format_stays_v2() -> void:
	assert_int(GameStateScript.SAVE_VERSION).is_equal(2)


func test_every_legacy_id_is_still_in_the_campaign() -> void:
	for i in range(1, 31):
		assert_object(GameState.campaign.get_level(StringName("m%02d" % i))).override_failure_message(
			"m%02d vanished" % i).is_not_null()


func test_an_old_v2_save_keeps_every_record() -> void:
	var state := _load(_old_v2_save())
	for i in range(1, 31):
		var id := StringName("m%02d" % i)
		assert_bool(state.progress.is_completed(id)).override_failure_message(String(id)).is_true()
		assert_int(state.progress.get_best_moves(id)).is_equal(10 + i)
		assert_int(state.progress.get_best_stars(id)).is_equal(2)
	for i in range(31, 49):
		assert_bool(state.progress.is_completed(StringName("m%02d" % i))).is_false()


func test_completed_missions_stay_playable_wherever_they_moved() -> void:
	var state := _load(_old_v2_save())
	for i in range(1, 31):
		assert_bool(state.is_unlocked(StringName("m%02d" % i))).override_failure_message("m%02d" % i).is_true()
	# New missions open only when the one before them (in the new order) is completed: the boss
	# of each old chapter is open (its predecessor is done), the first mission of a new chapter
	# (m35 Pruning, m43 Contagion) waits for the boss in front of it.
	for id in ["m31", "m32", "m33", "m34", "m40", "m42", "m48"]:
		assert_bool(state.is_unlocked(StringName(id))).override_failure_message(id).is_true()
	for id in ["m35", "m41", "m43"]:
		assert_bool(state.is_unlocked(StringName(id))).override_failure_message(id).is_false()


func test_saving_keeps_unknown_fields_and_the_version() -> void:
	var state := _load(_old_v2_save())
	state.record_result(&"m31", LevelResult.create(10, 30.0, 12, 60.0))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH))
	assert_int(int(data["version"])).is_equal(2)
	assert_array(data["future_field"]["keep"]).is_equal([1.0, 2.0, 3.0])
	assert_bool(data["progress"]["missions"].has("m31")).is_true()
	assert_bool(data["progress"]["missions"].has("m30")).is_true()


func test_a_player_midway_meets_the_boss_before_the_next_chapter() -> void:
	var missions := {}
	for id in ["m01", "m02", "m03", "m04", "m05"]:
		missions[id] = _entry(3, 5, 20.0)
	var state := _load({"version": 2, "progress": {"missions": missions}})
	assert_str(String(state.next_mission_after(&"m05"))).is_equal("m31")
	assert_bool(state.is_unlocked(&"m31")).is_true()
	assert_bool(state.is_unlocked(&"m06")).is_false()
	state.record_result(&"m31", LevelResult.create(10, 30.0, 12, 60.0))
	assert_bool(state.is_unlocked(&"m06")).is_true()


func test_the_displayed_number_is_the_campaign_position_not_the_id() -> void:
	var campaign := GameState.campaign
	assert_int(campaign.get_mission_number(&"m31")).is_equal(6)
	assert_int(campaign.get_mission_number(&"m06")).is_equal(7)
	assert_int(campaign.get_mission_number(&"m48")).is_equal(48)
	assert_str(String(campaign.next_mission_after(&"m39"))).is_equal("m19")
	assert_str(String(campaign.next_mission_after(&"m47"))).is_equal("m26")


func test_a_v1_save_still_migrates_to_the_stable_ids() -> void:
	var missions := {}
	for i in range(1, 22):
		missions["m%02d" % i] = _entry(3, 10 + i, 30.0)
	var state := _load({"version": 1, "progress": {"missions": missions}})
	for id in ["m26", "m28", "m30", "m18"]:
		assert_bool(state.progress.is_completed(StringName(id))).override_failure_message(id).is_true()
	assert_bool(state.progress.is_completed(&"m19")).is_false()
