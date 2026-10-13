class_name DiagnosticReport
extends RefCounted
## Text of a diagnostic run: the device block, a matrix with one line per step and a few hints
## drawn from it (a time pattern in the crashes, touch input, ...). Pure: it only reads a
## DiagnosticState. Hints say what the numbers suggest, never claim a cause.

const STATUS_LABELS := {
	DiagnosticState.OK: "OK     ", DiagnosticState.CRASHED: "CRASHED", DiagnosticState.SKIPPED: "SKIPPED",
	DiagnosticState.PENDING: "PENDING", DiagnosticState.RUNNING: "RUNNING",
}
## Crashes within this many seconds of process uptime count as the same moment.
const TIME_PATTERN_WINDOW := 6.0


## extras (all optional): titles {id: text}, device, trace, exit (Android's exit record), generated.
static func format(state: DiagnosticState, extras := {}) -> String:
	var parts := PackedStringArray()
	parts.append("Neural Connect diagnostics report")
	parts.append("Run started %s%s" % [state.started_at, "" if extras.get("generated", "") == "" \
		else ", report written %s" % extras["generated"]])
	parts.append(state.flags)
	if state.device != "" or extras.get("device", "") != "":
		parts.append("\nDevice:\n" + (String(extras.get("device", "")) if extras.get("device", "") != "" \
			else state.device))
	parts.append("\nSteps (the app died in a CRASHED step; it may also have been closed by hand):")
	parts.append("\n".join(matrix_lines(state, extras.get("titles", {}))))
	var details := crash_details(state)
	if details != "":
		parts.append("\nCrash details (what Android recorded for each crashed step):\n" + details)
	parts.append("\nSummary:")
	parts.append("\n".join(analyze(state)))
	if extras.get("exit", "") != "":
		parts.append("\n" + String(extras["exit"]))
	var trace := String(extras.get("trace", ""))
	if trace != "":
		parts.append("\nNative crash trace (readable text of the system tombstone):\n" + trace)
	return "\n".join(parts) + "\n"


static func matrix_lines(state: DiagnosticState, titles: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for id in state.step_ids:
		var status := state.status_of(id)
		var entry: Dictionary = state.results.get(id, {})
		var label := String(titles.get(id, ""))
		var line := "%s  %-22s%s" % [STATUS_LABELS.get(status, status), id,
			"" if label == "" else " (%s)" % label]
		match status:
			DiagnosticState.OK:
				line += "  " + _ok_details(entry)
			DiagnosticState.CRASHED:
				line += "  died %.1f s into the step (process uptime %.1f s)" % [
					float(entry.get("crash_elapsed_s", 0.0)), float(entry.get("crash_uptime_s", 0.0))]
			DiagnosticState.SKIPPED:
				line += "  " + String(entry.get("note", ""))
		if bool(entry.get("manual", false)):
			line += "  [manual]"
		lines.append(line)
	return lines


## The system's exit record and native trace attached to each crashed step ("" when none has any).
static func crash_details(state: DiagnosticState) -> String:
	var blocks := PackedStringArray()
	for id in state.step_ids:
		if state.status_of(id) != DiagnosticState.CRASHED:
			continue
		var entry: Dictionary = state.results[id]
		var exit_text := String(entry.get("system_exit", ""))
		var trace := String(entry.get("trace", ""))
		if exit_text == "" and trace == "":
			continue
		var block := "- %s:" % id
		if exit_text != "":
			block += "\n  " + exit_text.replace("\n", "\n  ")
		if trace != "":
			block += "\n  " + trace.replace("\n", "\n  ")
		blocks.append(block)
	return "\n".join(blocks)


static func analyze(state: DiagnosticState) -> PackedStringArray:
	var hints := PackedStringArray()
	hints.append("%d ok, %d crashed, %d skipped, %d pending; %d launches of the app during the run." % [
		state.count_by_status(DiagnosticState.OK), state.count_by_status(DiagnosticState.CRASHED),
		state.count_by_status(DiagnosticState.SKIPPED), state.count_by_status(DiagnosticState.PENDING),
		state.launches])
	var crashed: Array[String] = []
	var uptimes: Array[float] = []
	var manual_crashes := 0
	var automatic_crashes := 0
	for id in state.step_ids:
		if state.status_of(id) != DiagnosticState.CRASHED:
			continue
		crashed.append(id)
		var entry: Dictionary = state.results[id]
		uptimes.append(float(entry.get("crash_uptime_s", 0.0)))
		if bool(entry.get("manual", false)):
			manual_crashes += 1
		else:
			automatic_crashes += 1
	if crashed.is_empty():
		if state.finished:
			hints.append("No step crashed: the crash needs something these steps do not do, or a longer session.")
		return hints
	hints.append("Crashed in: " + ", ".join(crashed) + ".")
	if uptimes.size() >= 2 and uptimes.max() - uptimes.min() <= TIME_PATTERN_WINDOW:
		hints.append(("All crashes came about %d s after the process started (%.0f-%.0f s) whatever the step " \
			+ "was: this points to a time-based cause (a thread, the audio output, the driver) rather " \
			+ "than a screen.") % [int(roundf(uptimes.min())), uptimes.min(), uptimes.max()])
	if manual_crashes > 0 and automatic_crashes == 0 and state.count_by_status(DiagnosticState.OK) > 0:
		hints.append("Only manual steps crashed while the automatic ones ran fine: the touch input path " \
			+ "is the suspect.")
	elif automatic_crashes > 0:
		hints.append("The crashed steps isolate one suspect each; compare them with the OK ones.")
	return hints


static func _ok_details(entry: Dictionary) -> String:
	var parts := PackedStringArray()
	if entry.has("duration_s"):
		parts.append("%.1f s" % float(entry["duration_s"]))
	if entry.has("fps_min"):
		parts.append("fps min %d avg %d" % [int(float(entry["fps_min"])), int(float(entry.get("fps_avg", 0.0)))])
	if entry.has("static_mb_start") and entry.has("static_mb_end"):
		parts.append("mem %+dMB" % (int(entry["static_mb_end"]) - int(entry["static_mb_start"])))
	if entry.has("vram_mb_start") and entry.has("vram_mb_end"):
		parts.append("vram %+dMB" % (int(entry["vram_mb_end"]) - int(entry["vram_mb_start"])))
	return " | ".join(parts)
