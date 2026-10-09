extends GdUnitTestSuite
## T8.1: offline analysis of user://measurements.csv (per-mission stats and proposed pars).

const Analysis := preload("res://tools/measurement_analysis.gd")

const CSV := """timestamp,mission_id,result,seconds_to_first_move,total_seconds,moves,restarts_before,stars
t1,m01,completed,2.0,40.00,6,0,3
t2,m01,restarted,1.0,10.00,2,0,0
t3,m01,completed,3.0,60.00,8,1,2
t4,m01,completed,2.5,50.00,7,1,3
t5,m02,lost_tension,,5.00,1,0,0
t6,m03,completed,1.0,100.00,10,0,1
garbage line
t7,m03,completed,x,120.00,12,0,1
"""

const SPECS := """		{
			"id": "m01", "name": "MISSION_M01_NAME", "chapter": 1, "par_moves": 6, "par_time": 60.0,
			"story": "",
		},
		{
			"id": "m03", "name": "MISSION_M03_NAME", "chapter": 1, "par_time": 60.0,
		},
		{
			"id": "m04", "name": "MISSION_M04_NAME", "chapter": 1, "par_time": 90.0,
		},
"""


func test_parse_skips_header_and_malformed_rows() -> void:
	var rows := Analysis.parse_csv(CSV)
	assert_int(rows.size()).is_equal(7)
	assert_str(rows[0]["mission_id"]).is_equal("m01")
	assert_float(rows[0]["total_seconds"]).is_equal(40.0)


func test_stats_use_completed_runs_only() -> void:
	var stats := Analysis.analyze(Analysis.parse_csv(CSV))
	assert_int(stats["m01"]["runs"]).is_equal(3)
	assert_int(stats["m01"]["best_moves"]).is_equal(6)
	assert_float(stats["m01"]["median_moves"]).is_equal(7.0)
	assert_float(stats["m01"]["best_time"]).is_equal(40.0)
	assert_float(stats["m01"]["median_time"]).is_equal(50.0)
	# Even number of runs: the median is the mean of the two middle values.
	assert_float(stats["m03"]["median_moves"]).is_equal(11.0)


func test_a_mission_without_completed_runs_has_no_data() -> void:
	var stats := Analysis.analyze(Analysis.parse_csv(CSV))
	assert_int(stats["m02"]["runs"]).is_equal(0)
	assert_bool(Analysis.propose(stats["m02"]).is_empty()).is_true()


func test_proposed_pars_are_best_times_1_15_rounded_up() -> void:
	var stats := Analysis.analyze(Analysis.parse_csv(CSV))
	var proposal := Analysis.propose(stats["m01"])
	# 6 * 1.15 = 6.9 -> 7 ; 40 * 1.15 = 46 -> 46
	assert_int(proposal["par_moves"]).is_equal(7)
	assert_float(proposal["par_time"]).is_equal(46.0)
	# Existing star rule: 2 stars up to 1.5 x par.
	assert_float(proposal["two_star_moves"]).is_equal(10.5)
	assert_float(proposal["two_star_time"]).is_equal(69.0)


func test_proposal_never_goes_below_one_move() -> void:
	var proposal := Analysis.propose({"runs": 1, "best_moves": 0, "best_time": 0.0})
	assert_int(proposal["par_moves"]).is_equal(1)
	assert_float(proposal["par_time"]).is_equal(1.0)


func test_apply_rewrites_only_the_missions_with_data() -> void:
	var proposals := {"m01": {"par_moves": 7, "par_time": 46.0}, "m03": {"par_moves": 12, "par_time": 118.0}}
	var out := Analysis.apply_to_specs(SPECS, proposals)
	assert_str(out).contains('"id": "m01", "name": "MISSION_M01_NAME", "chapter": 1, "par_moves": 7, "par_time": 46.0,')
	# A mission without par_moves gets one inserted before par_time.
	assert_str(out).contains('"chapter": 1, "par_moves": 12, "par_time": 118.0,')
	# m04 has no data: untouched.
	assert_str(out).contains('"id": "m04", "name": "MISSION_M04_NAME", "chapter": 1, "par_time": 90.0,')


func test_apply_is_deterministic_and_idempotent() -> void:
	var proposals := {"m01": {"par_moves": 7, "par_time": 46.0}}
	var once := Analysis.apply_to_specs(SPECS, proposals)
	assert_str(Analysis.apply_to_specs(once, proposals)).is_equal(once)
