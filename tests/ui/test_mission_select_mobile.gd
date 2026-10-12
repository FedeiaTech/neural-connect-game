extends GdUnitTestSuite
## Mobile mission select: no scrollbar, one chapter per page, locked chapters stay hidden.

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")

var _sandbox: Sandbox


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()


func after_test() -> void:
	_sandbox.exit()


func _add(mobile: bool) -> MissionSelect:
	var select: MissionSelect = auto_free(MissionSelectScene.instantiate())
	select.mobile_layout = mobile
	add_child(select)
	return select


func test_revealed_chapters_stops_at_the_last_unlocked_one() -> void:
	assert_int(MissionSelect.revealed_chapters([true, false, false] as Array[bool])).is_equal(1)
	assert_int(MissionSelect.revealed_chapters([true, true, false] as Array[bool])).is_equal(2)
	assert_int(MissionSelect.revealed_chapters([false, false] as Array[bool])).is_equal(1)
	assert_int(MissionSelect.revealed_chapters([] as Array[bool])).is_equal(1)


func test_mobile_hides_chapters_that_are_still_locked() -> void:
	var select := _add(true)
	assert_int(select.get_chapter_headers().size()).is_equal(1)
	assert_object(select.get_mission_node(&"m01")).is_not_null()
	assert_object(select.get_mission_node(&"m30")).is_null()


func test_desktop_keeps_every_chapter() -> void:
	var select := _add(false)
	assert_int(select.get_chapter_headers().size()).is_greater(1)
	assert_object(select.get_mission_node(&"m30")).is_not_null()


func test_mobile_hides_the_scrollbar_but_keeps_scrolling() -> void:
	var select := _add(true)
	assert_int(select.get_scroll().vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_SHOW_NEVER)


func test_mobile_reveals_the_next_chapter_once_its_first_mission_unlocks() -> void:
	var last_of_first: StringName = GameState.campaign.chapters[0].missions.back().mission_id
	var result := LevelResult.new()
	result.moves = 4
	result.time = 20.0
	result.stars = 1
	for level in GameState.campaign.chapters[0].missions:
		GameState.record_result(level.mission_id, result)
	assert_bool(GameState.is_unlocked(last_of_first)).is_true()
	var select := _add(true)
	assert_int(select.get_chapter_headers().size()).is_equal(2)
