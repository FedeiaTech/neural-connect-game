extends GdUnitTestSuite
## DiagnosticRunner: runs the steps one after another, persists each BEGIN/END and carries on after
## the app died in the middle of one. Steps here are fakes; time is driven by tick().

const TEMP_PATH := "user://test_diag_runner.json"


class FakeStep extends DiagnosticStep:
	var begun := 0
	var ended := 0
	var updates := 0

	func _init(step_id: StringName, seconds := 0.3, needs_window := false, is_manual := false) -> void:
		id = step_id
		title = "fake %s" % step_id
		duration = seconds
		requires_window = needs_window
		manual = is_manual

	func begin(_stage: Control) -> void:
		begun += 1

	func update(_delta: float, _elapsed: float) -> void:
		updates += 1

	func end() -> void:
		ended += 1


func after_test() -> void:
	DiagnosticState.clear(TEMP_PATH)


func _runner(steps: Array[DiagnosticStep]) -> DiagnosticRunner:
	var runner: DiagnosticRunner = auto_free(DiagnosticRunner.new())
	runner.state_path = TEMP_PATH
	runner.stage = auto_free(Control.new())
	runner.steps = steps
	runner.gap_seconds = 0.0
	add_child(runner)
	runner.set_process(false)
	return runner


func _drive(runner: DiagnosticRunner, max_ticks := 400) -> void:
	for i in max_ticks:
		if not runner.is_running():
			return
		runner.tick(0.1)


func test_a_new_run_goes_through_every_step_once_and_finishes() -> void:
	var a := FakeStep.new(&"a")
	var b := FakeStep.new(&"b")
	var runner := _runner([a, b])
	runner.start_new()
	_drive(runner)
	assert_bool(runner.is_running()).is_false()
	assert_bool(runner.get_state().finished).is_true()
	assert_str(runner.get_state().status_of("a")).is_equal(DiagnosticState.OK)
	assert_str(runner.get_state().status_of("b")).is_equal(DiagnosticState.OK)
	assert_int(a.begun).is_equal(1)
	assert_int(a.ended).is_equal(1)
	assert_int(b.begun).is_equal(1)
	assert_int(a.updates).is_greater(0)


func test_it_reports_progress_through_signals() -> void:
	var runner := _runner([FakeStep.new(&"a"), FakeStep.new(&"b")])
	var started: Array[String] = []
	var finished_runs := [0]
	runner.step_started.connect(func(id: String, _i: int, _n: int) -> void: started.append(id))
	runner.run_finished.connect(func() -> void: finished_runs[0] += 1)
	runner.start_new()
	_drive(runner)
	assert_array(started).is_equal(["a", "b"])
	assert_int(finished_runs[0]).is_equal(1)


func test_the_step_is_on_disk_as_running_before_it_ends() -> void:
	var runner := _runner([FakeStep.new(&"a", 1.0)])
	runner.start_new()
	runner.tick(0.0)
	var saved := DiagnosticState.load_from(TEMP_PATH)
	assert_str(saved.current).is_equal("a")
	assert_str(saved.status_of("a")).is_equal(DiagnosticState.RUNNING)


func test_metrics_are_recorded_for_a_finished_step() -> void:
	var runner := _runner([FakeStep.new(&"a")])
	runner.start_new()
	_drive(runner)
	var entry: Dictionary = runner.get_state().results["a"]
	assert_bool(entry.has("duration_s")).is_true()
	assert_bool(entry.has("static_mb_end")).is_true()
	assert_bool(entry.has("fps_min")).is_true()


func test_a_step_that_never_ended_is_marked_crashed_and_the_run_continues() -> void:
	var state := DiagnosticState.create(PackedStringArray(["a", "b", "c"]))
	state.begin_step("a", 1.0, "", false)
	state.finish_step("a", {})
	state.begin_step("b", 9.0, "", false)
	state.note_tick(4.0, 17.0, 50.0)
	state.save(TEMP_PATH)
	var a := FakeStep.new(&"a")
	var b := FakeStep.new(&"b")
	var c := FakeStep.new(&"c")
	var runner := _runner([a, b, c])
	assert_bool(runner.resume()).is_true()
	_drive(runner)
	var result := runner.get_state()
	assert_str(result.status_of("a")).is_equal(DiagnosticState.OK)
	assert_str(result.status_of("b")).is_equal(DiagnosticState.CRASHED)
	assert_str(result.status_of("c")).is_equal(DiagnosticState.OK)
	assert_int(result.launches).is_equal(2)
	assert_int(a.begun).is_equal(0)
	assert_int(b.begun).is_equal(0)
	assert_int(c.begun).is_equal(1)


func test_crash_info_from_the_system_is_attached_to_the_crashed_step() -> void:
	var state := DiagnosticState.create(PackedStringArray(["a", "b"]))
	state.begin_step("a", 1.0, "", false)
	state.save(TEMP_PATH)
	var runner := _runner([FakeStep.new(&"a"), FakeStep.new(&"b")])
	runner.crash_info = func() -> Dictionary: return {"exit": "CRASH_NATIVE signal=11", "trace": "libGLES_mali.so"}
	runner.resume()
	var entry: Dictionary = runner.get_state().results["a"]
	assert_str(String(entry["system_exit"])).is_equal("CRASH_NATIVE signal=11")
	assert_str(String(entry["trace"])).is_equal("libGLES_mali.so")


func test_resume_without_a_run_in_progress_does_nothing() -> void:
	var runner := _runner([FakeStep.new(&"a")])
	assert_bool(runner.resume()).is_false()
	assert_bool(runner.is_running()).is_false()


func test_steps_that_need_a_window_are_skipped_when_headless() -> void:
	var needs_window := FakeStep.new(&"window", 0.3, true)
	var runner := _runner([needs_window, FakeStep.new(&"plain")])
	runner.headless = true
	runner.start_new()
	_drive(runner)
	assert_str(runner.get_state().status_of("window")).is_equal(DiagnosticState.SKIPPED)
	assert_str(runner.get_state().status_of("plain")).is_equal(DiagnosticState.OK)
	assert_int(needs_window.begun).is_equal(0)


func test_cancel_stops_the_step_and_forgets_the_run() -> void:
	var step := FakeStep.new(&"a", 5.0)
	var runner := _runner([step])
	runner.start_new()
	runner.tick(0.0)
	runner.tick(0.5)
	runner.cancel()
	assert_int(step.ended).is_equal(1)
	assert_bool(runner.is_running()).is_false()
	assert_bool(FileAccess.file_exists(TEMP_PATH)).is_false()


func test_closing_the_app_by_hand_marks_the_step_to_be_retried() -> void:
	var runner := _runner([FakeStep.new(&"a", 5.0)])
	runner.start_new()
	runner.tick(0.0)
	runner.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var saved := DiagnosticState.load_from(TEMP_PATH)
	assert_bool(saved.user_exit).is_true()
	assert_str(saved.recover_after_restart()).is_equal("a")
	assert_str(saved.status_of("a")).is_equal(DiagnosticState.PENDING)


func test_the_titles_come_from_the_steps() -> void:
	var runner := _runner([FakeStep.new(&"a")])
	assert_str(runner.get_titles()["a"]).is_equal("fake a")


func test_the_default_battery_has_unique_ids_titles_and_two_manual_steps() -> void:
	var steps := DiagnosticSteps.build_all()
	var seen := {}
	var manual := 0
	for step in steps:
		assert_bool(seen.has(step.id)).override_failure_message("duplicate id %s" % step.id).is_false()
		seen[step.id] = true
		assert_str(step.title).is_not_empty()
		assert_float(step.duration).is_greater(0.0)
		if step.manual:
			manual += 1
			assert_str(step.hint_key).is_not_empty()
	assert_int(manual).is_equal(2)
	assert_bool(steps[steps.size() - 1].manual).is_true()
	assert_int(steps.size()).is_greater_equal(15)
