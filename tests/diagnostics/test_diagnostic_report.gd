extends GdUnitTestSuite
## DiagnosticReport: the matrix and the hints derived from a run. Pure text from a DiagnosticState.


func _run(ids: Array) -> DiagnosticState:
	return DiagnosticState.create(PackedStringArray(ids), "2026-10-13T10:00:00", "visuals: low_memory=off")


func _ok(state: DiagnosticState, id: String, manual := false) -> void:
	state.begin_step(id, 5.0, "flags", manual)
	state.finish_step(id, {"fps_min": 31.0, "fps_avg": 58.4, "duration_s": 10.0,
		"static_mb_start": 80, "static_mb_end": 83, "vram_mb_start": 40, "vram_mb_end": 44})


func _crash(state: DiagnosticState, id: String, uptime: float, manual := false) -> void:
	state.begin_step(id, uptime - 5.0, "flags", manual)
	state.note_tick(5.0, uptime, 50.0)
	state.recover_after_restart()


func test_the_matrix_has_one_line_per_step_with_its_status() -> void:
	var state := _run(["a", "b", "c", "d"])
	_ok(state, "a")
	_crash(state, "b", 20.0)
	state.skip_step("c", "no window")
	var text := DiagnosticReport.format(state)
	assert_str(text).contains("OK")
	assert_str(text).contains("CRASHED")
	assert_str(text).contains("SKIPPED")
	assert_str(text).contains("PENDING")
	assert_int(DiagnosticReport.matrix_lines(state, {}).size()).is_equal(4)


func test_an_ok_line_shows_fps_and_memory_deltas() -> void:
	var state := _run(["a"])
	_ok(state, "a")
	var line := DiagnosticReport.matrix_lines(state, {})[0]
	assert_str(line).contains("min 31")
	assert_str(line).contains("avg 58")
	assert_str(line).contains("mem +3MB")
	assert_str(line).contains("vram +4MB")


func test_a_crashed_line_says_when_the_app_died() -> void:
	var state := _run(["a"])
	_crash(state, "a", 21.5)
	var line := DiagnosticReport.matrix_lines(state, {})[0]
	assert_str(line).contains("died 5.0 s into the step")
	assert_str(line).contains("uptime 21.5 s")


func test_titles_are_shown_when_given() -> void:
	var state := _run(["a"])
	_ok(state, "a")
	var line := DiagnosticReport.matrix_lines(state, {"a": "Idle menu"})[0]
	assert_str(line).contains("Idle menu")


func test_crashes_at_the_same_uptime_point_to_a_time_based_cause() -> void:
	var state := _run(["a", "b", "c"])
	_crash(state, "a", 19.0)
	_crash(state, "b", 21.0)
	_ok(state, "c")
	var hints := "\n".join(DiagnosticReport.analyze(state))
	assert_str(hints).contains("time-based")


func test_crashes_at_very_different_uptimes_do_not_claim_a_time_pattern() -> void:
	var state := _run(["a", "b", "c"])
	_crash(state, "a", 12.0)
	_crash(state, "b", 41.0)
	_ok(state, "c")
	assert_str("\n".join(DiagnosticReport.analyze(state))).not_contains("time-based")


func test_only_manual_steps_crashing_points_to_touch_input() -> void:
	var state := _run(["a", "m"])
	_ok(state, "a")
	_crash(state, "m", 40.0, true)
	assert_str("\n".join(DiagnosticReport.analyze(state))).contains("touch")


func test_no_crash_is_reported_plainly() -> void:
	var state := _run(["a", "b"])
	_ok(state, "a")
	_ok(state, "b")
	assert_str("\n".join(DiagnosticReport.analyze(state))).contains("No step crashed")


func test_the_summary_counts_statuses_and_launches() -> void:
	var state := _run(["a", "b"])
	_ok(state, "a")
	_crash(state, "b", 20.0)
	assert_str("\n".join(DiagnosticReport.analyze(state))).contains("2 launches")


func test_the_report_includes_the_extra_sections_when_given() -> void:
	var state := _run(["a"])
	_ok(state, "a")
	var text := DiagnosticReport.format(state, {
		"device": "renderer=mobile/vulkan",
		"trace": "libGLES_mali.so",
		"exit": "CRASH_NATIVE signal=11",
		"generated": "2026-10-13T10:05:00"})
	assert_str(text).contains("renderer=mobile/vulkan")
	assert_str(text).contains("Native crash trace")
	assert_str(text).contains("libGLES_mali.so")
	assert_str(text).contains("CRASH_NATIVE signal=11")
	assert_str(text).contains("2026-10-13T10:05:00")
	assert_str(text).contains("visuals: low_memory=off")


func test_crash_details_list_what_the_system_recorded_per_crashed_step() -> void:
	var state := _run(["a", "b"])
	_crash(state, "a", 20.0)
	state.results["a"]["system_exit"] = "CRASH_NATIVE (code 5) | signal=11 SIGSEGV"
	state.results["a"]["trace"] = "Native crash trace:\n  libGLES_mali.so"
	_ok(state, "b")
	var text := DiagnosticReport.format(state)
	assert_str(text).contains("Crash details")
	assert_str(text).contains("- a:")
	assert_str(text).contains("signal=11 SIGSEGV")
	assert_str(text).contains("libGLES_mali.so")
	assert_str(DiagnosticReport.crash_details(_run(["x"]))).is_empty()


func test_sections_without_data_are_left_out() -> void:
	var state := _run(["a"])
	_ok(state, "a")
	var text := DiagnosticReport.format(state)
	assert_str(text).not_contains("Native crash trace")
