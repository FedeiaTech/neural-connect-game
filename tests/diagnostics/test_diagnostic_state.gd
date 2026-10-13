extends GdUnitTestSuite
## DiagnosticState: the persisted record of a diagnostic run (which step began, which ended, which
## one the app died in). Pure data plus a JSON file; every test uses its own temp path.

const TEMP_PATH := "user://test_diagnostics_state.json"
const IDS := ["alpha", "beta", "gamma"]


func after_test() -> void:
	DiagnosticState.clear(TEMP_PATH)


func _state() -> DiagnosticState:
	return DiagnosticState.create(PackedStringArray(IDS), "2026-10-13T10:00:00", "visuals: test")


func test_a_new_run_is_active_and_starts_with_the_first_step() -> void:
	var state := _state()
	assert_bool(state.is_active()).is_true()
	assert_str(state.next_pending()).is_equal("alpha")
	assert_str(state.status_of("alpha")).is_equal(DiagnosticState.PENDING)


func test_begin_and_finish_walk_through_the_steps_in_order() -> void:
	var state := _state()
	state.begin_step("alpha", 3.0, "flags", false)
	assert_str(state.current).is_equal("alpha")
	assert_str(state.status_of("alpha")).is_equal(DiagnosticState.RUNNING)
	state.finish_step("alpha", {"fps_min": 30.0, "fps_avg": 58.5})
	assert_str(state.current).is_empty()
	assert_str(state.status_of("alpha")).is_equal(DiagnosticState.OK)
	assert_float(float(state.results["alpha"]["fps_avg"])).is_equal(58.5)
	assert_str(state.next_pending()).is_equal("beta")


func test_the_run_finishes_when_no_step_is_pending() -> void:
	var state := _state()
	for id in IDS:
		state.begin_step(id, 1.0, "", false)
		state.finish_step(id, {})
	assert_bool(state.finished).is_true()
	assert_bool(state.is_active()).is_false()
	assert_str(state.next_pending()).is_empty()


func test_a_step_with_begin_and_no_end_is_recorded_as_crashed_after_a_restart() -> void:
	var state := _state()
	state.begin_step("alpha", 3.0, "", false)
	state.finish_step("alpha", {})
	state.begin_step("beta", 12.0, "", false)
	state.note_tick(7.2, 19.3, 55.0)
	var crashed := state.recover_after_restart()
	assert_str(crashed).is_equal("beta")
	assert_str(state.status_of("beta")).is_equal(DiagnosticState.CRASHED)
	assert_float(float(state.results["beta"]["crash_elapsed_s"])).is_equal_approx(7.2, 0.001)
	assert_float(float(state.results["beta"]["crash_uptime_s"])).is_equal_approx(19.3, 0.001)
	assert_str(state.current).is_empty()
	assert_int(state.launches).is_equal(2)
	# The run continues with the next step, the crashed one is not retried.
	assert_str(state.next_pending()).is_equal("gamma")


func test_a_user_exit_retries_the_step_instead_of_calling_it_a_crash() -> void:
	var state := _state()
	state.begin_step("alpha", 3.0, "", false)
	state.mark_user_exit()
	var affected := state.recover_after_restart()
	assert_str(affected).is_equal("alpha")
	assert_str(state.status_of("alpha")).is_equal(DiagnosticState.PENDING)
	assert_str(state.next_pending()).is_equal("alpha")
	assert_bool(state.user_exit).is_false()


func test_recovering_with_no_running_step_only_counts_the_launch() -> void:
	var state := _state()
	assert_str(state.recover_after_restart()).is_empty()
	assert_int(state.launches).is_equal(2)


func test_a_crash_in_the_last_step_finishes_the_run() -> void:
	var state := DiagnosticState.create(PackedStringArray(["only"]))
	state.begin_step("only", 1.0, "", false)
	state.recover_after_restart()
	assert_bool(state.finished).is_true()


func test_skipped_steps_are_not_pending() -> void:
	var state := _state()
	state.skip_step("alpha", "no window")
	assert_str(state.status_of("alpha")).is_equal(DiagnosticState.SKIPPED)
	assert_str(String(state.results["alpha"]["note"])).is_equal("no window")
	assert_str(state.next_pending()).is_equal("beta")


func test_counts_by_status() -> void:
	var state := _state()
	state.begin_step("alpha", 1.0, "", false)
	state.finish_step("alpha", {})
	state.skip_step("beta", "x")
	assert_int(state.count_by_status(DiagnosticState.OK)).is_equal(1)
	assert_int(state.count_by_status(DiagnosticState.SKIPPED)).is_equal(1)
	assert_int(state.count_by_status(DiagnosticState.PENDING)).is_equal(1)


func test_it_survives_a_round_trip_through_a_dictionary() -> void:
	var state := _state()
	state.device = "device block"
	state.begin_step("alpha", 3.0, "flags", true)
	state.finish_step("alpha", {"fps_min": 20.0})
	state.begin_step("beta", 9.0, "flags", false)
	var copy := DiagnosticState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_array(Array(copy.step_ids)).is_equal(IDS)
	assert_str(copy.current).is_equal("beta")
	assert_str(copy.device).is_equal("device block")
	assert_str(copy.status_of("alpha")).is_equal(DiagnosticState.OK)
	assert_bool(bool(copy.results["alpha"]["manual"])).is_true()
	assert_str(copy.started_at).is_equal("2026-10-13T10:00:00")


func test_save_and_load_use_the_file() -> void:
	var state := _state()
	state.begin_step("alpha", 3.0, "", false)
	assert_bool(state.save(TEMP_PATH)).is_true()
	assert_bool(DiagnosticState.is_active_on_disk(TEMP_PATH)).is_true()
	var loaded := DiagnosticState.load_from(TEMP_PATH)
	assert_object(loaded).is_not_null()
	assert_str(loaded.current).is_equal("alpha")
	DiagnosticState.clear(TEMP_PATH)
	assert_bool(DiagnosticState.is_active_on_disk(TEMP_PATH)).is_false()
	assert_object(DiagnosticState.load_from(TEMP_PATH)).is_null()


func test_a_finished_run_on_disk_is_not_active() -> void:
	var state := DiagnosticState.create(PackedStringArray(["only"]))
	state.begin_step("only", 1.0, "", false)
	state.finish_step("only", {})
	state.save(TEMP_PATH)
	assert_bool(DiagnosticState.is_active_on_disk(TEMP_PATH)).is_false()
	assert_object(DiagnosticState.load_from(TEMP_PATH)).is_not_null()


func test_a_corrupt_file_is_ignored() -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	assert_object(DiagnosticState.load_from(TEMP_PATH)).is_null()
	assert_bool(DiagnosticState.is_active_on_disk(TEMP_PATH)).is_false()
