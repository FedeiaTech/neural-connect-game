extends GdUnitTestSuite
## T5.1/T5.2: tuning checks for the hand-designed campaign (SDD 6, 7, 7.1). The human playtest
## comes later, so these guard structure, solvability through the real rules and the
## difficulty curve of every authored mission.

const SolutionPlanner := preload("res://tests/content/solution_planner.gd")
const CAMPAIGN_PATH := "res://data/campaign.tres"
const LEVELS_DIR := "res://data/levels"
const CHAPTER_COUNT := 5
## Chapter ids by mechanic (SDD 7.1).
const CHAPTER_BASICS := 1
const CHAPTER_SHAPES := 2
const CHAPTER_FIXED := 3
const CHAPTER_TENSION := 4
const CHAPTER_COMBINED := 5
const MIN_PAR_TIME := 45.0
const MAX_PAR_TIME := 300.0
## A tension dendrite is "close to its limit" at this fraction of max_length.
const NEAR_LIMIT := 0.8
## Story text on roughly every 2nd-3rd mission: at most this many missions in a row without.
const MAX_MISSIONS_WITHOUT_STORY := 2
const MIN_SOLUTION_SPACING_RADII := 3.0
## Same threshold as tools/build_levels.gd.
const MIN_START_CLEARANCE := 40.0

## mission_id -> planner result, computed once for the suite.
var _plans: Dictionary[StringName, Dictionary] = {}


func before() -> void:
	for level in _levels():
		_plans[level.mission_id] = SolutionPlanner.new().plan(level)


func _campaign() -> Campaign:
	return load(CAMPAIGN_PATH)


func _levels() -> Array[LevelData]:
	var levels: Array[LevelData] = []
	for chapter in _campaign().chapters:
		levels.append_array(chapter.missions)
	return levels


func _fail(message: String) -> void:
	assert_bool(false).override_failure_message(message).is_true()


func test_campaign_has_the_five_chapters_in_order() -> void:
	var chapters := _campaign().chapters
	assert_int(chapters.size()).is_equal(CHAPTER_COUNT)
	for i in chapters.size():
		var chapter := chapters[i]
		assert_object(chapter).is_not_null()
		assert_int(chapter.chapter_id).is_equal(i + 1)
		assert_str(chapter.title).is_not_empty()
		assert_str(chapter.subtitle).is_not_empty()
		assert_int(chapter.missions.size()).override_failure_message(
			"chapter %d has %d missions" % [chapter.chapter_id, chapter.missions.size()]).is_greater_equal(2)
		for level in chapter.missions:
			assert_object(level).is_not_null()
			assert_int(level.chapter_id).override_failure_message(String(level.mission_id)) \
				.is_equal(chapter.chapter_id)


func test_campaign_order_matches_file_numbering() -> void:
	var levels := _levels()
	assert_int(levels.size()).is_greater_equal(18)
	var seen: Dictionary[StringName, bool] = {}
	for i in levels.size():
		var level := levels[i]
		var expected := "m%02d" % (i + 1)
		assert_str(String(level.mission_id)).is_equal(expected)
		assert_str(level.resource_path).is_equal("%s/%s.tres" % [LEVELS_DIR, expected])
		assert_bool(seen.has(level.mission_id)).override_failure_message(
			"duplicate mission id %s" % level.mission_id).is_false()
		seen[level.mission_id] = true


func test_every_level_file_is_in_the_campaign() -> void:
	var ids := _campaign().get_mission_ids()
	for file_name in DirAccess.get_files_at(LEVELS_DIR):
		if file_name.ends_with(".tres"):
			assert_bool(ids.has(StringName(file_name.get_basename()))).override_failure_message(
				"%s is not listed in the campaign" % file_name).is_true()


func test_every_campaign_mission_is_valid_and_named() -> void:
	var names: Dictionary[String, bool] = {}
	for level in _levels():
		var errors := PuzzleModel.validate_level(level)
		assert_array(errors).override_failure_message("%s: %s" % [level.mission_id, errors]).is_empty()
		assert_str(level.mission_name).is_not_empty()
		assert_bool(names.has(level.mission_name)).override_failure_message(
			"duplicate mission name %s" % level.mission_name).is_false()
		names[level.mission_name] = true


## The proof: the planned drags, replayed on the real PuzzleModel (collisions and tension),
## leave every mission solved without breaking a dendrite.
func test_every_mission_is_solvable_through_the_model_rules() -> void:
	for level in _levels():
		var result := _plans[level.mission_id]
		if not result["ok"]:
			_fail("%s: planner failed: %s" % [level.mission_id, result["reason"]])
			continue
		var replay := SolutionPlanner.replay(level, result["moves"])
		var model: PuzzleModel = replay["model"]
		assert_str(replay["error"]).override_failure_message(
			"%s: %s" % [level.mission_id, replay["error"]]).is_empty()
		assert_bool(model.is_broken()).override_failure_message(String(level.mission_id)).is_false()
		assert_bool(model.is_solved()).override_failure_message(
			"%s: not solved after the plan" % level.mission_id).is_true()
		assert_int(model.get_move_count()).is_equal(result["moves"].size())


func test_pars_are_generous_but_bounded() -> void:
	for level in _levels():
		var moves: int = _plans[level.mission_id]["moves"].size()
		assert_int(level.par_moves).override_failure_message(
			"%s: par_moves %d < planned %d" % [level.mission_id, level.par_moves, moves]) \
			.is_greater_equal(moves)
		assert_int(level.par_moves).override_failure_message(String(level.mission_id)) \
			.is_less_equal(4 * level.neurons.size())
		assert_float(level.par_time).override_failure_message(String(level.mission_id)) \
			.is_between(MIN_PAR_TIME, MAX_PAR_TIME)


func test_starts_are_meaningfully_tangled() -> void:
	for level in _levels():
		var crossings := PuzzleModel.from_level(level).get_crossing_count()
		var minimum := 1 if level.chapter_id == CHAPTER_BASICS else 3
		assert_int(crossings).override_failure_message(
			"%s: %d start crossings < %d" % [level.mission_id, crossings, minimum]).is_greater_equal(minimum)


func test_neuron_count_grows_chapter_by_chapter() -> void:
	var previous_mean := 0.0
	for chapter in _campaign().chapters:
		var total := 0
		for level in chapter.missions:
			total += level.neurons.size()
		var mean := float(total) / chapter.missions.size()
		assert_float(mean).override_failure_message(
			"chapter %d mean %.2f < previous %.2f" % [chapter.chapter_id, mean, previous_mean]) \
			.is_greater_equal(previous_mean)
		previous_mean = mean
	for level in _levels():
		assert_int(level.neurons.size()).override_failure_message(String(level.mission_id)).is_between(4, 14)


func test_each_chapter_teaches_its_mechanic() -> void:
	for level in _levels():
		var id := String(level.mission_id)
		var shaped := level.play_area.size() != 4 or not level.obstacles.is_empty()
		var fixed := _fixed_count(level)
		var near_limit := _near_limit_tension_count(level)
		match level.chapter_id:
			CHAPTER_BASICS:
				assert_bool(shaped or fixed > 0 or _tension_count(level) > 0).override_failure_message(
					"%s: chapter 1 is plain basics" % id).is_false()
			CHAPTER_SHAPES:
				assert_bool(shaped).override_failure_message("%s: needs a shaped area or obstacles" % id).is_true()
			CHAPTER_FIXED:
				assert_int(fixed).override_failure_message("%s: needs fixed neurons" % id).is_greater_equal(1)
			CHAPTER_TENSION:
				assert_int(near_limit).override_failure_message(
					"%s: needs a tension dendrite close to its limit" % id).is_greater_equal(1)
			CHAPTER_COMBINED:
				var mechanics := int(shaped) + int(fixed > 0) + int(near_limit > 0)
				assert_int(mechanics).override_failure_message("%s: combines mechanics" % id).is_greater_equal(2)


## Readability: solution neurons at least 3 radii apart, and no dendrite running through or
## grazing a neuron it does not connect (start and solution layouts).
func test_layouts_stay_readable() -> void:
	for level in _levels():
		var id := String(level.mission_id)
		var radius := level.neuron_radius
		for i in level.neurons.size():
			for j in range(i + 1, level.neurons.size()):
				var spacing := level.neurons[i].solution_position.distance_to(level.neurons[j].solution_position)
				assert_float(spacing).override_failure_message(
					"%s: solution neurons %d and %d only %.0f apart" % [id, i, j, spacing]) \
					.is_greater_equal(MIN_SOLUTION_SPACING_RADII * radius)
		assert_float(_edge_clearance(level, false)).override_failure_message(
			"%s: a start dendrite grazes a neuron" % id).is_greater_equal(MIN_START_CLEARANCE)
		assert_float(_edge_clearance(level, true)).override_failure_message(
			"%s: a solution dendrite grazes a neuron" % id).is_greater_equal(2.0 * radius)


func test_story_text_appears_every_two_or_three_missions() -> void:
	var levels := _levels()
	var without := 0
	var with_story := 0
	for level in levels:
		if level.story_text.is_empty():
			without += 1
			assert_int(without).override_failure_message(
				"%s: too many missions without story" % level.mission_id).is_less_equal(MAX_MISSIONS_WITHOUT_STORY)
		else:
			without = 0
			with_story += 1
			assert_int(level.story_text.split("\n").size()).is_less_equal(2)
	assert_str(levels[0].story_text).is_not_empty()
	assert_int(with_story).is_less(levels.size())


func _fixed_count(level: LevelData) -> int:
	var count := 0
	for neuron in level.neurons:
		if neuron.fixed:
			count += 1
	return count


func _tension_count(level: LevelData) -> int:
	var count := 0
	for dendrite in level.dendrites:
		if dendrite.is_tension():
			count += 1
	return count


## Smallest distance from a neuron center to a dendrite that does not end at it.
func _edge_clearance(level: LevelData, use_solution: bool) -> float:
	var best := INF
	for dendrite in level.dendrites:
		var a := level.find_neuron(dendrite.a)
		var b := level.find_neuron(dendrite.b)
		var from := a.solution_position if use_solution else a.position
		var to := b.solution_position if use_solution else b.position
		for neuron in level.neurons:
			if neuron.id != dendrite.a and neuron.id != dendrite.b:
				var center := neuron.solution_position if use_solution else neuron.position
				best = minf(best, center.distance_to(Geometry2D.get_closest_point_to_segment(center, from, to)))
	return best


## Tension dendrites whose start or solution length reaches NEAR_LIMIT of max_length.
func _near_limit_tension_count(level: LevelData) -> int:
	var count := 0
	for dendrite in level.dendrites:
		if not dendrite.is_tension():
			continue
		var a := level.find_neuron(dendrite.a)
		var b := level.find_neuron(dendrite.b)
		var longest := maxf(a.position.distance_to(b.position), a.solution_position.distance_to(b.solution_position))
		if longest >= NEAR_LIMIT * dendrite.max_length:
			count += 1
	return count
