extends GdUnitTestSuite
## T3.2: Progress keeps the best stars, moves and time per mission and round-trips to a Dictionary.


func test_fresh_progress_has_no_records() -> void:
	var progress := Progress.new()
	assert_bool(progress.is_completed(&"m01")).is_false()
	assert_int(progress.get_best_stars(&"m01")).is_equal(0)
	assert_int(progress.get_best_moves(&"m01")).is_equal(Progress.NO_MOVES)
	assert_float(progress.get_best_time(&"m01")).is_equal(Progress.NO_TIME)
	assert_int(progress.get_completed_count()).is_equal(0)


func test_first_record_completes_the_mission() -> void:
	var progress := Progress.new()
	progress.record(&"m01", 2, 9, 70.5)
	assert_bool(progress.is_completed(&"m01")).is_true()
	assert_int(progress.get_best_stars(&"m01")).is_equal(2)
	assert_int(progress.get_best_moves(&"m01")).is_equal(9)
	assert_float(progress.get_best_time(&"m01")).is_equal(70.5)
	assert_int(progress.get_completed_count()).is_equal(1)


func test_best_values_are_kept_independently() -> void:
	var progress := Progress.new()
	progress.record(&"m01", 2, 9, 40.0)
	# Fewer moves but slower and fewer stars: only moves improve.
	progress.record(&"m01", 1, 6, 95.0)
	assert_int(progress.get_best_stars(&"m01")).is_equal(2)
	assert_int(progress.get_best_moves(&"m01")).is_equal(6)
	assert_float(progress.get_best_time(&"m01")).is_equal(40.0)
	progress.record(&"m01", 3, 7, 30.0)
	assert_int(progress.get_best_stars(&"m01")).is_equal(3)
	assert_int(progress.get_best_moves(&"m01")).is_equal(6)
	assert_float(progress.get_best_time(&"m01")).is_equal(30.0)


func test_stars_are_clamped_to_one_to_three_on_record() -> void:
	var progress := Progress.new()
	progress.record(&"m01", 7, 1, 1.0)
	assert_int(progress.get_best_stars(&"m01")).is_equal(3)
	progress.record(&"m02", 0, 1, 1.0)
	assert_int(progress.get_best_stars(&"m02")).is_equal(1)


func test_dictionary_round_trip() -> void:
	var progress := Progress.new()
	progress.record(&"m01", 3, 5, 31.25)
	progress.record(&"m02", 1, 20, 300.0)
	var copy := Progress.from_dict(progress.to_dict())
	assert_bool(copy.is_completed(&"m01")).is_true()
	assert_int(copy.get_best_stars(&"m01")).is_equal(3)
	assert_int(copy.get_best_moves(&"m01")).is_equal(5)
	assert_float(copy.get_best_time(&"m01")).is_equal(31.25)
	assert_int(copy.get_best_moves(&"m02")).is_equal(20)
	assert_int(copy.get_completed_count()).is_equal(2)


func test_json_numbers_survive_a_text_round_trip() -> void:
	var progress := Progress.new()
	progress.record(&"m01", 3, 5, 31.25)
	# JSON turns ints into floats; from_dict must convert them back.
	var copy := Progress.from_dict(JSON.parse_string(JSON.stringify(progress.to_dict())))
	assert_int(copy.get_best_moves(&"m01")).is_equal(5)
	assert_int(copy.get_best_stars(&"m01")).is_equal(3)


func test_from_dict_ignores_garbage() -> void:
	assert_int(Progress.from_dict(null).get_completed_count()).is_equal(0)
	assert_int(Progress.from_dict("nope").get_completed_count()).is_equal(0)
	assert_int(Progress.from_dict({"missions": 4}).get_completed_count()).is_equal(0)
	var mixed := Progress.from_dict({"missions": {
		"m01": {"completed": true, "stars": 2, "moves": 4, "time": 12.0},
		"m02": "broken",
		"m03": {"completed": "yes", "stars": "many"},
	}})
	assert_bool(mixed.is_completed(&"m01")).is_true()
	assert_bool(mixed.is_completed(&"m02")).is_false()
	assert_bool(mixed.is_completed(&"m03")).is_false()
	assert_int(mixed.get_best_stars(&"m03")).is_equal(0)
