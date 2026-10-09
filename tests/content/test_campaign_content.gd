extends GdUnitTestSuite
## T5.1/T5.2/T8.4-T8.6: tuning checks for the hand-designed campaign (SDD 6, 7, 7.1). The human
## playtest comes later, so these guard structure, solvability through the real rules, the order in
## which mechanics are taught, bosses, organic arenas and the difficulty curve of every mission.

const SolutionPlanner := preload("res://tests/content/solution_planner.gd")
const Csv := preload("res://tests/localization/translation_table.gd")
const CAMPAIGN_PATH := "res://data/campaign.tres"
const LEVELS_DIR := "res://data/levels"
const CHAPTER_COUNT := 9
## Chapter ids by the mechanic they teach (SDD 7.1). Chapter id = position in the campaign.
const CHAPTER_BASICS := 1
const CHAPTER_SHAPES := 2
const CHAPTER_FIXED := 3
const CHAPTER_TENSION := 4
const CHAPTER_DISEASED := 5
const CHAPTER_LETHAL := 6
const CHAPTER_RECEPTORS := 7
const CHAPTER_TOXIC := 8
const CHAPTER_COMBINED := 9
## The documented campaign (docs/SDD.md 7.1): stable mission ids in play order, boss last. The 30
## original ids never moved; m31..m48 are the new missions.
const EXPECTED_ORDER := {
	1: ["m01", "m02", "m03", "m04", "m05", "m31"],
	2: ["m06", "m07", "m08", "m09", "m10", "m32"],
	3: ["m11", "m12", "m13", "m14", "m33"],
	4: ["m15", "m16", "m17", "m18", "m34"],
	5: ["m35", "m36", "m37", "m38", "m39"],
	6: ["m19", "m20", "m21", "m40", "m41"],
	7: ["m22", "m23", "m24", "m25", "m42"],
	8: ["m43", "m44", "m45", "m46", "m47"],
	9: ["m26", "m27", "m28", "m29", "m30", "m48"],
}
## The chapter that teaches each mechanic: no mission may use one before it.
const MECHANIC_CHAPTER := {
	"shaped": CHAPTER_SHAPES, "fixed": CHAPTER_FIXED, "tension": CHAPTER_TENSION,
	"diseased": CHAPTER_DISEASED, "lethal": CHAPTER_LETHAL, "receptors": CHAPTER_RECEPTORS,
	"toxic": CHAPTER_TOXIC,
}
## Chapters that introduce a new mechanic may restart with smaller networks (T7.4).
const INTRO_CHAPTERS: Array[int] = [CHAPTER_DISEASED, CHAPTER_LETHAL, CHAPTER_RECEPTORS, CHAPTER_TOXIC]
const MIN_MISSIONS := 48
const MAX_NEURONS := 16
const MAX_BOSS_NEURONS := 18
## Difficulty curve (T7.4): a mission may start with at most this many crossings more than the
## hardest of the three missions before it, and the first mission of a new-mechanic chapter
## starts gently.
const MAX_CROSSING_SPIKE := 14
const MAX_INTRO_CROSSINGS := 6
const MIN_PAR_TIME := 45.0
const MAX_PAR_TIME := 300.0
## A tension dendrite is "close to its limit" at this fraction of max_length.
const NEAR_LIMIT := 0.8
## Story text on roughly every 2nd-3rd mission: at most this many missions in a row without.
const MAX_MISSIONS_WITHOUT_STORY := 2
const MIN_SOLUTION_SPACING_RADII := 3.0
## Same threshold as tools/build_levels.gd.
const MIN_START_CLEARANCE := 40.0
## T8.5: organic arenas (chapter 2 on, and every boss) are many-vertex outlines that fit the view.
const MIN_ORGANIC_VERTICES := 32
const MIN_BOSS_VERTICES := 100
const MAX_VERTICES := 400
## The view fits the arena into 1824 x 936 (LevelController.get_fit_area()).
const MAX_ARENA_SIZE := Vector2(1624.0, 924.0)
## T6.3: content texts are translation keys of locale/translations.csv.
const LOCALES: Array[String] = ["en", "es"]

## mission_id -> planner result, computed once for the suite.
var _plans: Dictionary[StringName, Dictionary] = {}
var _table: Dictionary = {}


func before() -> void:
	_table = Csv.load_table()
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


# --- Structure and stable ids --------------------------------------------------------

func test_campaign_has_the_nine_chapters_in_order() -> void:
	var chapters := _campaign().chapters
	assert_int(chapters.size()).is_equal(CHAPTER_COUNT)
	for i in chapters.size():
		var chapter := chapters[i]
		assert_object(chapter).is_not_null()
		assert_int(chapter.chapter_id).is_equal(i + 1)
		assert_str(chapter.title).is_not_empty()
		assert_str(chapter.subtitle).is_not_empty()
		assert_int(chapter.missions.size()).override_failure_message(
			"chapter %d has %d missions" % [chapter.chapter_id, chapter.missions.size()]).is_between(5, 6)
		for level in chapter.missions:
			assert_object(level).is_not_null()
			assert_int(level.chapter_id).override_failure_message(String(level.mission_id)) \
				.is_equal(chapter.chapter_id)


## The documented order, pinned: reordering the campaign is a deliberate, documented change.
func test_campaign_order_is_the_documented_table() -> void:
	var chapters := _campaign().chapters
	for chapter in chapters:
		var ids: Array[String] = []
		for level in chapter.missions:
			ids.append(String(level.mission_id))
		assert_array(ids).override_failure_message("chapter %d" % chapter.chapter_id) \
			.is_equal(EXPECTED_ORDER[chapter.chapter_id])


## Mission ids are stable: they never encode the position. The 30 original ids still exist (saved
## progress keeps working), new ids are unique, and every id names its resource file.
func test_mission_ids_are_stable_and_unique() -> void:
	var levels := _levels()
	assert_int(levels.size()).is_greater_equal(MIN_MISSIONS)
	var seen: Dictionary[StringName, bool] = {}
	for level in levels:
		assert_bool(seen.has(level.mission_id)).override_failure_message(
			"duplicate mission id %s" % level.mission_id).is_false()
		seen[level.mission_id] = true
		assert_str(level.resource_path).is_equal("%s/%s.tres" % [LEVELS_DIR, level.mission_id])
	for number in range(1, 49):
		assert_bool(seen.has(StringName("m%02d" % number))).override_failure_message(
			"m%02d is missing" % number).is_true()


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
		var english := _english(level.mission_name)
		assert_str(english).override_failure_message(String(level.mission_id)).is_not_empty()
		assert_bool(names.has(english)).override_failure_message(
			"duplicate mission name %s" % english).is_false()
		names[english] = true


## The proof: the planned drags, replayed on the real PuzzleModel (collisions, tension, diseased
## breaks, links, contamination and lethal walls), leave every mission solved without a loss.
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
		assert_bool(model.is_lost()).override_failure_message(String(level.mission_id)).is_false()
		assert_bool(model.is_solved()).override_failure_message(
			"%s: not solved after the plan" % level.mission_id).is_true()
		assert_int(model.get_move_count()).is_equal(result["moves"].size())


func test_pars_are_generous_but_bounded() -> void:
	for level in _levels():
		# Planned moves are an upper bound on what a human needs: measured human minimums (T8.1
		# streaks) can be lower, so the floor is just 1 move.
		assert_int(level.par_moves).override_failure_message(
			"%s: par_moves %d < 1" % [level.mission_id, level.par_moves]) \
			.is_greater_equal(1)
		assert_int(level.par_moves).override_failure_message(String(level.mission_id)) \
			.is_less_equal(4 * level.neurons.size())
		assert_float(level.par_time).override_failure_message(String(level.mission_id)) \
			.is_between(MIN_PAR_TIME, MAX_PAR_TIME)


## The new missions (m31 and up) start with the generous default: twice the planned moves. The
## human retunes them from the measurement mode.
func test_new_missions_have_the_default_generous_par() -> void:
	for level in _levels():
		if int(String(level.mission_id).substr(1)) < 31:
			continue
		var moves: int = _plans[level.mission_id]["moves"].size()
		assert_int(level.par_moves).override_failure_message(String(level.mission_id)) \
			.is_equal(maxi(2 * moves, 4))


func test_starts_are_meaningfully_tangled() -> void:
	for level in _levels():
		var model := PuzzleModel.from_level(level)
		var crossings := model.get_crossing_count()
		var minimum := 1 if level.chapter_id == CHAPTER_BASICS else 3
		assert_int(crossings).override_failure_message(
			"%s: %d start crossings < %d" % [level.mission_id, crossings, minimum]).is_greater_equal(minimum)


# --- Bosses (T8.6) ---------------------------------------------------------------------

func test_the_last_mission_of_every_chapter_is_its_boss_and_only_that_one() -> void:
	for chapter in _campaign().chapters:
		for i in chapter.missions.size():
			var level := chapter.missions[i]
			assert_bool(level.is_boss).override_failure_message(String(level.mission_id)) \
				.is_equal(i == chapter.missions.size() - 1)


func test_bosses_are_larger_than_their_chapter_and_story_driven() -> void:
	for chapter in _campaign().chapters:
		var boss := chapter.missions[chapter.missions.size() - 1]
		var biggest := 0
		for i in chapter.missions.size() - 1:
			biggest = maxi(biggest, chapter.missions[i].neurons.size())
		assert_int(boss.neurons.size()).override_failure_message(
			"%s is not larger than its chapter" % boss.mission_id).is_greater_equal(biggest)
		assert_int(boss.neurons.size()).is_less_equal(MAX_BOSS_NEURONS)
		assert_str(boss.story_text).override_failure_message("%s has no story" % boss.mission_id).is_not_empty()
		assert_int(boss.play_area.size()).override_failure_message(
			"%s: a boss arena needs %d vertices" % [boss.mission_id, MIN_BOSS_VERTICES]) \
			.is_greater_equal(MIN_BOSS_VERTICES)
		if chapter.chapter_id >= CHAPTER_FIXED:
			assert_int(_mechanics(boss).size()).override_failure_message(
				"%s combines too few mechanics" % boss.mission_id).is_greater_equal(2)


## The HARD toxic rule belongs to the boss missions of Contagion and later.
func test_hard_toxic_is_for_late_bosses_with_toxic_neurons() -> void:
	var hard := 0
	for level in _levels():
		if level.hard_toxic:
			hard += 1
			assert_bool(level.is_boss).override_failure_message(String(level.mission_id)).is_true()
			assert_int(level.chapter_id).is_greater_equal(CHAPTER_TOXIC)
			assert_bool(_mechanics(level).has("toxic")).is_true()
		elif level.is_boss and level.chapter_id >= CHAPTER_TOXIC:
			assert_bool(_mechanics(level).has("toxic")).override_failure_message(
				"%s: the late bosses use toxic neurons" % level.mission_id).is_true()
	assert_int(hard).is_equal(2)


# --- Organic arenas (T8.5) ------------------------------------------------------------

func test_advanced_missions_use_organic_arenas() -> void:
	for level in _levels():
		var id := String(level.mission_id)
		if level.chapter_id >= CHAPTER_SHAPES:
			assert_int(level.play_area.size()).override_failure_message(
				"%s: arena has %d vertices" % [id, level.play_area.size()]).is_greater_equal(MIN_ORGANIC_VERTICES)
		assert_int(level.play_area.size()).override_failure_message(id).is_less_equal(MAX_VERTICES)
		assert_bool(_is_rectangle(level.play_area) and level.chapter_id >= CHAPTER_SHAPES).override_failure_message(
			"%s: a plain rectangle past chapter 1" % id).is_false()
		var bounds := Rect2(level.play_area[0], Vector2.ZERO)
		for point in level.play_area:
			bounds = bounds.expand(point)
		assert_float(bounds.size.x).override_failure_message(id).is_less_equal(MAX_ARENA_SIZE.x)
		assert_float(bounds.size.y).override_failure_message(id).is_less_equal(MAX_ARENA_SIZE.y)


## Not just rounded blobs: many arenas have bays, necks, rings or lobes (their area is clearly
## smaller than the area of their convex hull).
func test_many_arenas_are_concave() -> void:
	var concave := 0
	for level in _levels():
		if level.chapter_id < CHAPTER_SHAPES:
			continue
		var hull := Geometry2D.convex_hull(level.play_area)
		if _area(level.play_area) < 0.97 * _area(hull):
			concave += 1
	assert_int(concave).is_greater_equal(20)


# --- Teaching order (T8.4) -------------------------------------------------------------

## No mission may use a mechanic that its chapter or an earlier one has not taught.
func test_no_mission_uses_a_mechanic_before_it_is_taught() -> void:
	for level in _levels():
		for mechanic: String in _mechanics(level):
			assert_int(level.chapter_id).override_failure_message(
				"%s uses %s before chapter %d" % [level.mission_id, mechanic, MECHANIC_CHAPTER[mechanic]]) \
				.is_greater_equal(MECHANIC_CHAPTER[mechanic])


## Every mechanic is introduced by the first mission of its chapter: the first mission that uses
## it in campaign order opens the chapter, and the new-mechanic chapters start gently.
func test_each_mechanic_is_introduced_by_the_opening_mission_of_its_chapter() -> void:
	var first_use: Dictionary[String, StringName] = {}
	for level in _levels():
		for mechanic: String in _mechanics(level):
			if not first_use.has(mechanic):
				first_use[mechanic] = level.mission_id
	for mechanic: String in MECHANIC_CHAPTER:
		var chapter := _campaign().chapters[MECHANIC_CHAPTER[mechanic] - 1]
		assert_str(String(first_use.get(mechanic, &""))).override_failure_message(
			"%s first appears in %s, not in the opening of chapter %d" % [
				mechanic, first_use.get(mechanic, &""), chapter.chapter_id]) \
			.is_equal(String(chapter.missions[0].mission_id))
	for chapter in _campaign().chapters:
		if INTRO_CHAPTERS.has(chapter.chapter_id):
			var first := chapter.missions[0]
			assert_int(PuzzleModel.from_level(first).get_crossing_count()).override_failure_message(
				"%s opens a new mechanic too tangled" % first.mission_id).is_less_equal(MAX_INTRO_CROSSINGS)


## Mean network size grows chapter by chapter (bosses excluded). A chapter that introduces a new
## mechanic may restart smaller, but never below Shaped Minds, and the final Convergence chapter
## holds the largest networks.
func test_neuron_count_grows_chapter_by_chapter() -> void:
	var previous_mean := 0.0
	var means: Dictionary[int, float] = {}
	for chapter in _campaign().chapters:
		var total := 0
		var count := 0
		for level in chapter.missions:
			if not level.is_boss:
				total += level.neurons.size()
				count += 1
		var mean := float(total) / count
		means[chapter.chapter_id] = mean
		var floor_mean := previous_mean
		if INTRO_CHAPTERS.has(chapter.chapter_id):
			floor_mean = means[CHAPTER_SHAPES]
		assert_float(mean).override_failure_message(
			"chapter %d mean %.2f < %.2f" % [chapter.chapter_id, mean, floor_mean]).is_greater_equal(floor_mean)
		if not INTRO_CHAPTERS.has(chapter.chapter_id):
			previous_mean = mean
	for chapter_id: int in means:
		assert_float(means[CHAPTER_COMBINED]).is_greater_equal(means[chapter_id])
	for level in _levels():
		var cap := MAX_BOSS_NEURONS if level.is_boss else MAX_NEURONS
		assert_int(level.neurons.size()).override_failure_message(String(level.mission_id)).is_between(4, cap)


## T7.4 difficulty curve: no sudden spikes in the start tangle, and the most tangled start in the
## final chapter. Neurons per mission never jump by more than a third either.
func test_difficulty_curve_has_no_spikes() -> void:
	var levels := _levels()
	var crossings: Array[int] = []
	var hardest := 0
	var hardest_chapter := 0
	for i in levels.size():
		var count := PuzzleModel.from_level(levels[i]).get_crossing_count()
		crossings.append(count)
		if i > 0:
			var recent := 0
			for k in range(maxi(0, i - 3), i):
				recent = maxi(recent, crossings[k])
			assert_int(count).override_failure_message("%s: %d start crossings spike after %d" % [
				levels[i].mission_id, count, recent]).is_less_equal(recent + MAX_CROSSING_SPIKE)
		if count >= hardest:
			hardest = count
			hardest_chapter = levels[i].chapter_id
	assert_int(hardest_chapter).is_equal(CHAPTER_COMBINED)


func test_each_chapter_teaches_its_mechanic() -> void:
	for level in _levels():
		var id := String(level.mission_id)
		var mechanics := _mechanics(level)
		match level.chapter_id:
			CHAPTER_BASICS:
				if not level.is_boss:
					assert_array(mechanics).override_failure_message(
						"%s: chapter 1 is plain basics" % id).is_empty()
			CHAPTER_SHAPES:
				assert_bool(mechanics.has("shaped")).override_failure_message(
					"%s: needs a shaped area or obstacles" % id).is_true()
			CHAPTER_FIXED:
				assert_bool(mechanics.has("fixed")).override_failure_message("%s: needs fixed neurons" % id).is_true()
			CHAPTER_TENSION:
				assert_int(_near_limit_tension_count(level)).override_failure_message(
					"%s: needs a tension dendrite close to its limit" % id).is_greater_equal(1)
			CHAPTER_DISEASED:
				assert_bool(mechanics.has("diseased")).override_failure_message(
					"%s: needs diseased dendrites" % id).is_true()
			CHAPTER_LETHAL:
				assert_bool(mechanics.has("lethal")).override_failure_message("%s: needs lethal walls" % id).is_true()
			CHAPTER_RECEPTORS:
				assert_bool(mechanics.has("receptors")).override_failure_message("%s: needs receptors" % id).is_true()
			CHAPTER_TOXIC:
				assert_bool(mechanics.has("toxic")).override_failure_message("%s: needs toxic neurons" % id).is_true()
				assert_bool(mechanics.has("receptors")).override_failure_message(
					"%s: toxic neurons only matter near receptors" % id).is_true()
			CHAPTER_COMBINED:
				assert_int(mechanics.size()).override_failure_message("%s: combines mechanics" % id) \
					.is_greater_equal(3)


## Diseased missions: every diseased dendrite starts intact and the solution layout breaks it.
func test_diseased_dendrites_start_intact_and_break_in_the_solution() -> void:
	var seen := 0
	for level in _levels():
		var start := PuzzleModel.from_level(level)
		var solution := PuzzleModel.from_level(level, true)
		assert_int(start.get_diseased_broken_count()).override_failure_message(String(level.mission_id)).is_equal(0)
		assert_int(solution.get_diseased_broken_count()).override_failure_message(String(level.mission_id)) \
			.is_equal(solution.get_diseased_count())
		seen += int(start.get_diseased_count() > 0)
	assert_int(seen).is_greater_equal(6)


## Synapses: the receptors start without their links and the new mechanic grows on itself
## (a two-link receptor appears in the chapter). Contagion: nothing starts contaminated.
func test_receptor_missions_start_unlinked_and_clean() -> void:
	var two_link := false
	for level in _levels():
		var model := PuzzleModel.from_level(level)
		assert_bool(model.is_contaminated()).override_failure_message(String(level.mission_id)).is_false()
		for receptor_id in model.get_receptor_ids():
			assert_bool(model.is_receptor_satisfied(receptor_id)).override_failure_message(
				"%s: receptor %d starts linked" % [level.mission_id, receptor_id]).is_false()
			if level.chapter_id == CHAPTER_RECEPTORS and model.get_required_links(receptor_id) == 2:
				two_link = true
	assert_bool(two_link).is_true()


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
			for locale in LOCALES:
				var story := Csv.text(_table, level.story_text, locale)
				assert_int(story.split("\n").size()).override_failure_message(
					"%s (%s): story longer than 2 lines" % [level.mission_id, locale]).is_less_equal(2)
	assert_str(levels[0].story_text).is_not_empty()
	assert_int(with_story).is_less(levels.size())


## Every text the campaign shows is a key with the expected name and an English and a Spanish
## text: MISSION_MXX_NAME / MISSION_MXX_STORY and CHAPTER_N_TITLE / CHAPTER_N_SUBTITLE.
func test_campaign_texts_are_translated_keys() -> void:
	var used: Array[String] = []
	for chapter in _campaign().chapters:
		assert_str(chapter.title).is_equal("CHAPTER_%d_TITLE" % chapter.chapter_id)
		assert_str(chapter.subtitle).is_equal("CHAPTER_%d_SUBTITLE" % chapter.chapter_id)
		used.append_array([chapter.title, chapter.subtitle])
	for level in _levels():
		var prefix := "MISSION_%s_" % String(level.mission_id).to_upper()
		assert_str(level.mission_name).is_equal(prefix + "NAME")
		used.append(level.mission_name)
		if not level.story_text.is_empty():
			assert_str(level.story_text).is_equal(prefix + "STORY")
			used.append(level.story_text)
	for key in used:
		for locale in LOCALES:
			assert_str(Csv.text(_table, key, locale).strip_edges()).override_failure_message(
				"%s has no %s text" % [key, locale]).is_not_empty()


## The runtime translation (imported CSV) shows Spanish content in the es locale.
func test_content_translates_at_runtime() -> void:
	var level := _levels()[0]
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var spanish := tr(level.mission_name)
	TranslationServer.set_locale(previous)
	assert_str(spanish).is_equal(Csv.text(_table, level.mission_name, "es"))
	assert_str(spanish).is_not_equal(level.mission_name)


# --- Helpers -----------------------------------------------------------------------------

func _english(key: String) -> String:
	return Csv.text(_table, key, "en")


## Mechanics a mission uses: shaped (organic arena or obstacles), fixed, tension, diseased,
## lethal, receptors, toxic.
func _mechanics(level: LevelData) -> Array[String]:
	var result: Array[String] = []
	# Chapter 1 stays plain: only its boss wears an organic arena (no obstacles), which does not
	# count as the "shaped" mechanic of chapter 2.
	if not level.obstacles.is_empty() or (level.chapter_id >= CHAPTER_SHAPES and not _is_rectangle(level.play_area)):
		result.append("shaped")
	if _fixed_count(level) > 0:
		result.append("fixed")
	if _tension_count(level) > 0:
		result.append("tension")
	if _diseased_count(level) > 0:
		result.append("diseased")
	if level.lethal_edges.size() + level.lethal_obstacles.size() > 0:
		result.append("lethal")
	if _receptor_count(level) > 0:
		result.append("receptors")
	if _toxic_count(level) > 0:
		result.append("toxic")
	return result


static func _area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		total += a.x * b.y - b.x * a.y
	return absf(total) * 0.5


func _is_rectangle(area: PackedVector2Array) -> bool:
	return area.size() == 4


func _fixed_count(level: LevelData) -> int:
	var count := 0
	for neuron in level.neurons:
		if neuron.fixed and not neuron.is_receptor():
			count += 1
	return count


func _receptor_count(level: LevelData) -> int:
	var count := 0
	for neuron in level.neurons:
		if neuron.is_receptor():
			count += 1
	return count


func _toxic_count(level: LevelData) -> int:
	var count := 0
	for neuron in level.neurons:
		if neuron.is_toxic():
			count += 1
	return count


func _tension_count(level: LevelData) -> int:
	var count := 0
	for dendrite in level.dendrites:
		if dendrite.is_tension():
			count += 1
	return count


func _diseased_count(level: LevelData) -> int:
	var count := 0
	for dendrite in level.dendrites:
		if dendrite.is_diseased():
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
