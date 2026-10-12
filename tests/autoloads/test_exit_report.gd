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
		lines.append("line %d" % i)
	var report: String = ExitReportScript.format_report("V", "D", lines)
	assert_str(report).contains("line 99")
	assert_bool(report.contains("line 10\n")).is_false()
