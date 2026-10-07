extends GdUnitTestSuite
## T2.3: star rule (SDD 6). 3 stars: moves <= par AND time <= par. 2 stars: both within 1.5x.
## Otherwise 1 star (completed).


func test_three_stars_at_par() -> void:
	assert_int(LevelResult.compute_stars(6, 60.0, 6, 60.0)).is_equal(3)


func test_three_stars_under_par() -> void:
	assert_int(LevelResult.compute_stars(2, 10.0, 6, 60.0)).is_equal(3)


func test_two_stars_when_moves_over_par_within_one_and_a_half() -> void:
	assert_int(LevelResult.compute_stars(9, 30.0, 6, 60.0)).is_equal(2)


func test_two_stars_when_time_over_par_within_one_and_a_half() -> void:
	assert_int(LevelResult.compute_stars(3, 90.0, 6, 60.0)).is_equal(2)


func test_one_star_when_moves_beyond_one_and_a_half() -> void:
	assert_int(LevelResult.compute_stars(10, 30.0, 6, 60.0)).is_equal(1)


func test_one_star_when_time_beyond_one_and_a_half() -> void:
	assert_int(LevelResult.compute_stars(3, 90.5, 6, 60.0)).is_equal(1)


func test_create_fills_fields() -> void:
	var result := LevelResult.create(4, 12.5, 6, 60.0)
	assert_int(result.moves).is_equal(4)
	assert_float(result.time).is_equal(12.5)
	assert_int(result.stars).is_equal(3)
