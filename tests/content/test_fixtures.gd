extends GdUnitTestSuite
## T8: the visual-capture fixtures (toxic and diseased) are valid levels and the planner solves them,
## so the captures show mechanics that really work end to end.

const Fixtures := preload("res://tests/visual/fixtures.gd")
const SolutionPlanner := preload("res://tests/content/solution_planner.gd")


func _assert_valid_and_solvable(level: LevelData) -> PuzzleModel:
	assert_array(PuzzleModel.validate_level(level)).is_empty()
	var plan := SolutionPlanner.new().plan(level)
	assert_bool(plan["ok"]).override_failure_message(str(plan["reason"])).is_true()
	var replay := SolutionPlanner.replay(level, plan["moves"])
	assert_str(replay["error"]).is_empty()
	var model: PuzzleModel = replay["model"]
	assert_bool(model.is_solved()).is_true()
	return model


func test_toxic_fixture_is_valid_and_solvable() -> void:
	var model := _assert_valid_and_solvable(Fixtures.toxic_level())
	assert_bool(model.is_contaminated()).is_false()
	assert_array(model.get_links(0)).is_equal([1])


func test_diseased_fixture_is_valid_and_solvable() -> void:
	var model := _assert_valid_and_solvable(Fixtures.diseased_level())
	assert_int(model.get_diseased_broken_count()).is_equal(2)


func test_only_fixture_ids_are_fixtures() -> void:
	assert_bool(Fixtures.is_fixture(&"fixture_toxic")).is_true()
	assert_bool(Fixtures.is_fixture(&"m01")).is_false()
	assert_object(Fixtures.load_fixture(&"m01")).is_null()
