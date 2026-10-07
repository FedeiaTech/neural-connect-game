extends GdUnitTestSuite
## T3.2: the campaign catalog lists chapters and missions in play order (SDD 7.1).

const CAMPAIGN_PATH := "res://data/campaign.tres"


func _campaign() -> Campaign:
	return load(CAMPAIGN_PATH)


func test_chapter_one_holds_m01_then_m02() -> void:
	var campaign := _campaign()
	assert_int(campaign.chapters.size()).is_greater_equal(1)
	var chapter: ChapterData = campaign.chapters[0]
	assert_int(chapter.chapter_id).is_equal(1)
	assert_str(chapter.title).is_not_empty()
	assert_str(chapter.subtitle).is_not_empty()
	assert_array(campaign.get_mission_ids()).is_equal([&"m01", &"m02"])


func test_every_mission_belongs_to_its_chapter_and_is_valid() -> void:
	for chapter: ChapterData in _campaign().chapters:
		for level: LevelData in chapter.missions:
			assert_int(level.chapter_id).override_failure_message(String(level.mission_id)) \
				.is_equal(chapter.chapter_id)
			assert_array(PuzzleModel.validate_level(level)).is_empty()


func test_lookup_by_id() -> void:
	var campaign := _campaign()
	assert_str(String(campaign.get_level(&"m02").mission_id)).is_equal("m02")
	assert_object(campaign.get_level(&"missing")).is_null()
	assert_int(campaign.get_mission_number(&"m01")).is_equal(1)
	assert_int(campaign.get_mission_number(&"m02")).is_equal(2)
	assert_int(campaign.get_mission_number(&"missing")).is_equal(0)
	assert_int(campaign.get_chapter_of(&"m02").chapter_id).is_equal(1)
	assert_object(campaign.get_chapter_of(&"missing")).is_null()


func test_next_mission_follows_campaign_order_across_chapters() -> void:
	var first := ChapterData.new()
	first.missions = [_level(&"a"), _level(&"b")]
	var second := ChapterData.new()
	second.missions = [_level(&"c")]
	var campaign := Campaign.new()
	campaign.chapters = [first, second]
	assert_str(String(campaign.first_mission_id())).is_equal("a")
	assert_str(String(campaign.next_mission_after(&"a"))).is_equal("b")
	assert_str(String(campaign.next_mission_after(&"b"))).is_equal("c")
	assert_str(String(campaign.next_mission_after(&"c"))).is_empty()
	assert_str(String(campaign.next_mission_after(&"missing"))).is_empty()
	assert_str(String(campaign.previous_mission_before(&"c"))).is_equal("b")
	assert_str(String(campaign.previous_mission_before(&"a"))).is_empty()


func test_empty_campaign_has_no_first_mission() -> void:
	assert_str(String(Campaign.new().first_mission_id())).is_empty()


func _level(id: StringName) -> LevelData:
	var level := LevelData.new()
	level.mission_id = id
	return level
