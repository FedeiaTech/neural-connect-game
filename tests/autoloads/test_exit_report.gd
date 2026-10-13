extends GdUnitTestSuite

const ExitReportScript := preload("res://scripts/autoloads/exit_report.gd")


func test_exit_line_means_clean() -> void:
	var lines := PackedStringArray(["[1.0s] START x", "[9.0s] EXIT normal quit"])
	assert_str(ExitReportScript.verdict_for(lines)).starts_with("CLEAN")


func test_no_exit_while_paused_means_background_kill() -> void:
	var lines := PackedStringArray(["[1.0s] START x", "[5.0s] LIFECYCLE paused"])
	assert_str(ExitReportScript.verdict_for(lines)).contains("background")


func test_resume_after_pause_means_foreground_death() -> void:
	var lines := PackedStringArray(["[5.0s] LIFECYCLE paused", "[6.0s] LIFECYCLE resumed", "[7.0s] HB x"])
	var verdict: String = ExitReportScript.verdict_for(lines)
	assert_str(verdict).starts_with("ABNORMAL")
	assert_str(verdict).contains("foreground")


func test_report_keeps_only_the_tail() -> void:
	var lines := PackedStringArray()
	for i in 100:
		lines.append("[%d.0s] HB line %d" % [i, i])
	var report: String = ExitReportScript.format_report("V", "D", lines)
	assert_str(report).contains("HB line 99")
	assert_bool(report.contains("HB line 10\n")).is_false()


func test_report_lists_key_events_even_when_heartbeats_fill_the_tail() -> void:
	var lines := PackedStringArray(["[1.0s] START device", "[2.0s] LIFECYCLE paused"])
	for i in 200:
		lines.append("[%d.0s] HB rss=1MB" % (3 + i))
	var report: String = ExitReportScript.format_report("V", "D", lines)
	assert_str(report).contains("Key events")
	assert_str(report).contains("LIFECYCLE paused")
	assert_str(report).contains("START device")


func test_key_events_skip_heartbeats_and_keep_the_most_recent() -> void:
	var lines := PackedStringArray()
	for i in 100:
		lines.append("[%d.0s] ENGINE_ERROR e%d" % [i, i])
		lines.append("[%d.5s] HB x" % i)
	var events: PackedStringArray = ExitReportScript.key_events(lines)
	assert_int(events.size()).is_equal(ExitReportScript.EVENT_LINES)
	assert_str(events[events.size() - 1]).contains("e99")
	for event in events:
		assert_bool(event.contains(" HB ")).is_false()


func test_report_appends_the_engine_log_tail() -> void:
	var engine_log := PackedStringArray(["USER ERROR: boom", "at: somewhere"])
	var report: String = ExitReportScript.format_report("V", "D", PackedStringArray(["[1.0s] START"]), engine_log)
	assert_str(report).contains("Engine log")
	assert_str(report).contains("USER ERROR: boom")


func test_report_says_when_there_is_no_engine_log() -> void:
	var report: String = ExitReportScript.format_report("V", "D", PackedStringArray(["[1.0s] START"]))
	assert_str(report).contains("Engine log: not available")


func test_parse_proc_status_reads_memory_and_threads() -> void:
	var text := "Name:\tneural\nVmPeak:\t 4000000 kB\nVmSize:\t 3500000 kB\nVmHWM:\t  250000 kB\n" \
		+ "VmRSS:\t  204800 kB\nThreads:\t31\n"
	var values: Dictionary = ExitReportScript.parse_kv(text)
	assert_int(values.get("VmRSS", -1)).is_equal(204800)
	assert_int(values.get("VmHWM", -1)).is_equal(250000)
	assert_int(values.get("Threads", -1)).is_equal(31)
	assert_bool(values.has("Name")).is_false()


func test_process_memory_line_in_megabytes() -> void:
	var status := {"VmRSS": 204800, "VmHWM": 256000, "VmSize": 3072000, "Threads": 31}
	var meminfo := {"MemAvailable": 1048576, "MemTotal": 3932160}
	var line: String = ExitReportScript.format_process_memory(status, meminfo)
	assert_str(line).contains("rss=200MB")
	assert_str(line).contains("hwm=250MB")
	assert_str(line).contains("vsz=3000MB")
	assert_str(line).contains("threads=31")
	assert_str(line).contains("avail=1024MB/3840MB")


func test_process_memory_line_omits_unknown_values() -> void:
	var line: String = ExitReportScript.format_process_memory({}, {})
	assert_str(line).is_equal("")
	assert_bool(line.contains("-1")).is_false()


func test_latest_rotated_log_ignores_the_current_log() -> void:
	var files := PackedStringArray(["godot.log", "godot2026-10-12T20.01.02.log",
		"godot2026-10-12T22.18.31.log", "notes.txt"])
	assert_str(ExitReportScript.latest_rotated_log(files)).is_equal("godot2026-10-12T22.18.31.log")
	assert_str(ExitReportScript.latest_rotated_log(PackedStringArray(["godot.log"]))).is_equal("")


func test_exit_reason_codes_map_to_android_names() -> void:
	assert_str(ExitReportScript.exit_reason_name(5)).is_equal("CRASH_NATIVE")
	assert_str(ExitReportScript.exit_reason_name(4)).is_equal("CRASH")
	assert_str(ExitReportScript.exit_reason_name(3)).is_equal("LOW_MEMORY")
	assert_str(ExitReportScript.exit_reason_name(6)).is_equal("ANR")
	assert_str(ExitReportScript.exit_reason_name(2)).is_equal("SIGNALED")
	assert_str(ExitReportScript.exit_reason_name(10)).is_equal("USER_REQUESTED")
	assert_str(ExitReportScript.exit_reason_name(16)).is_equal("PACKAGE_UPDATED")
	assert_str(ExitReportScript.exit_reason_name(999)).is_equal("UNKNOWN(999)")


func test_native_crash_entry_shows_the_signal_memory_and_description() -> void:
	var entry := {"reason": 5, "status": 11, "description": "crash_native: signal 11", "importance": 100,
		"rss": 122880, "pss": 102400, "timestamp": 1760310000000}
	var text: String = ExitReportScript.format_exit_info(entry)
	assert_str(text).contains("CRASH_NATIVE (code 5)")
	assert_str(text).contains("SIGSEGV")
	assert_str(text).contains("importance=FOREGROUND")
	assert_str(text).contains("rss=120MB")
	assert_str(text).contains("pss=100MB")
	assert_str(text).contains("crash_native: signal 11")
	assert_str(text).contains("2025-10-12")


func test_non_signal_entry_shows_a_plain_status() -> void:
	var text: String = ExitReportScript.format_exit_info({"reason": 3, "status": 0, "importance": 400})
	assert_str(text).contains("LOW_MEMORY")
	assert_str(text).contains("status=0")
	assert_str(text).contains("importance=CACHED")
	assert_bool(text.contains("SIG")).is_false()


func test_exit_reasons_section_keeps_three_entries_newest_first() -> void:
	var entries: Array = []
	for reason in [5, 3, 6, 4, 2]:
		entries.append({"reason": reason, "status": 0})
	var section: String = ExitReportScript.format_exit_reasons(entries, "")
	assert_str(section).contains("Android exit reasons (system record)")
	assert_str(section).contains("1. CRASH_NATIVE")
	assert_str(section).contains("3. ANR")
	assert_bool(section.contains("4. ")).is_false()


func test_exit_reasons_section_explains_when_unavailable() -> void:
	var section: String = ExitReportScript.format_exit_reasons([], "AndroidRuntime singleton missing")
	assert_str(section).contains("not available")
	assert_str(section).contains("AndroidRuntime singleton missing")


func test_report_includes_the_exit_reasons_and_the_safe_visuals_note() -> void:
	var report: String = ExitReportScript.format_report("V", "D", PackedStringArray(["[1.0s] START"]),
		PackedStringArray(), "Android exit reasons (system record), newest first:\n  1. CRASH_NATIVE", "Safe visuals were enabled")
	assert_str(report).contains("1. CRASH_NATIVE")
	assert_str(report).contains("Safe visuals were enabled")


func test_report_includes_the_native_crash_trace_section() -> void:
	var trace: String = NativeTrace.format_section(PackedStringArray(["/vendor/lib64/libGLES_mali.so"]), "")
	var report: String = ExitReportScript.format_report("V", "D", PackedStringArray(["[1.0s] START"]),
		PackedStringArray(), "", "", trace)
	assert_str(report).contains("Native crash trace")
	assert_str(report).contains("libGLES_mali.so")


func test_report_has_no_trace_section_without_one() -> void:
	var report: String = ExitReportScript.format_report("V", "D", PackedStringArray(["[1.0s] START"]))
	assert_str(report).not_contains("Native crash trace")


func test_safe_visuals_turn_on_only_after_an_abnormal_close_on_a_device() -> void:
	assert_bool(ExitReportScript.should_enable_safe_visuals("ABNORMAL, x", true, false)).is_true()
	assert_bool(ExitReportScript.should_enable_safe_visuals("CLEAN, x", true, false)).is_false()
	assert_bool(ExitReportScript.should_enable_safe_visuals("ABNORMAL, x", false, false)).is_false()
	assert_bool(ExitReportScript.should_enable_safe_visuals("ABNORMAL, x", true, true)).is_false()


func test_visual_flags_summary_names_every_flag() -> void:
	var text: String = ExitReportScript.visual_flags_summary(true, false, true)
	assert_str(text).is_equal("visuals: low_memory=on low_quality=off reduced_motion=on")


func test_last_lines_returns_the_end_of_a_text() -> void:
	var text := "a\nb\nc\nd\n"
	var lines: PackedStringArray = ExitReportScript.last_lines(text, 2)
	assert_array(lines).contains_exactly(["c", "d"])
