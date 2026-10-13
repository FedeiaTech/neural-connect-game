extends Node
## Diagnostics autoload: explains why the app closed.
##
## Two files in user:// (on Android: Android/data/<package>/files/):
##   session_journal.log  breadcrumbs of the running session, flushed line by line (survives a kill)
##   exit_report.txt      human-readable report, rewritten on every exit event and at the next
##                        start when the previous session left no exit marker
## A native crash or an OS kill (low memory) cannot be caught from script. It is detected on the
## next launch: the previous journal has no EXIT line, and its last lines (memory heartbeat,
## lifecycle events, engine errors) show what happened right before.

const JOURNAL_PATH := "user://session_journal.log"
const REPORT_PATH := "user://exit_report.txt"
const HEARTBEAT_SECONDS := 1.0
const TAIL_LINES := 60
## Non-heartbeat lines (START, lifecycle, errors) listed apart so a 1 s heartbeat cannot push them out.
const EVENT_LINES := 40
const ENGINE_LOG_LINES := 30
const HEARTBEAT_TAG := " HB "
const LOG_DIR := "user://logs"
const PROC_STATUS_PATH := "/proc/self/status"
const PROC_MEMINFO_PATH := "/proc/meminfo"
const PROC_MAX_LINES := 200
const EXIT_MARKER := " EXIT "
const PAUSED_MARKER := " LIFECYCLE paused"
const RESUMED_MARKER := " LIFECYCLE resumed"
## Android's own record of why the previous process died (ApplicationExitInfo, API 30+).
const EXIT_QUERY_MAX := 5
const TRACE_MAX_BYTES := 262144
const EXIT_SHOWN := 3
const FALLBACK_PACKAGE := "com.fedeiatech.neuralconnect"
const SAFE_VISUALS_NOTE := "Safe visuals were enabled automatically after an abnormal close; " \
	+ "turn them off in Settings."
## ApplicationExitInfo.REASON_* codes.
const EXIT_REASON_NAMES := {
	0: "UNKNOWN", 1: "EXIT_SELF", 2: "SIGNALED", 3: "LOW_MEMORY", 4: "CRASH", 5: "CRASH_NATIVE", 6: "ANR",
	7: "INITIALIZATION_FAILURE", 8: "PERMISSION_CHANGE", 9: "EXCESSIVE_RESOURCE_USAGE",
	10: "USER_REQUESTED", 11: "USER_STOPPED", 12: "DEPENDENCY_DIED", 13: "OTHER", 14: "FREEZER",
	15: "PACKAGE_STATE_CHANGE", 16: "PACKAGE_UPDATED",
}
const REASON_SIGNALED := 2
const REASON_CRASH_NATIVE := 5
const SIGNAL_NAMES := {
	1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGBUS",
	8: "SIGFPE", 9: "SIGKILL", 10: "SIGUSR1", 11: "SIGSEGV", 12: "SIGUSR2", 13: "SIGPIPE",
	14: "SIGALRM", 15: "SIGTERM",
}
## ActivityManager.RunningAppProcessInfo.IMPORTANCE_*.
const IMPORTANCE_NAMES := {
	100: "FOREGROUND", 125: "FOREGROUND_SERVICE", 200: "VISIBLE", 230: "PERCEPTIBLE", 300: "SERVICE",
	325: "TOP_SLEEPING", 350: "CANT_SAVE_STATE", 400: "CACHED", 1000: "GONE",
}

var journal_path := JOURNAL_PATH
var report_path := REPORT_PATH
## What the system said about the previous process (the "Android exit reasons" section, and the
## readable part of its native crash tombstone). Empty when there was nothing to say. The diagnostics
## battery attaches them to the step the app died in.
var last_exit_text := ""
var last_trace_text := ""
## Where the battery keeps its run; while one is in progress a close is expected and not reported
## on its own (the battery shows it in its matrix) and the safe visuals stay off.
var diagnostics_state_path := DiagnosticState.DEFAULT_PATH

var _file: FileAccess
var _lines: PackedStringArray = []
var _mutex := Mutex.new()
var _logger: Logger
var _exit_written := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	begin_session()
	var timer := Timer.new()
	timer.wait_time = HEARTBEAT_SECONDS
	timer.autostart = true
	timer.timeout.connect(_heartbeat)
	add_child(timer)


## Judges the previous journal (writing the report when it ended abnormally) and starts a new one.
func begin_session() -> void:
	var previous := _read_lines(journal_path)
	var system_exit := _query_system_exit_reasons()
	var exit_text := ""
	if system_exit["supported"]:
		exit_text = format_exit_reasons(system_exit["entries"], system_exit["note"])
	last_exit_text = exit_text
	last_trace_text = NativeTrace.format_section(system_exit["trace_lines"], system_exit["trace_note"])
	if not previous.is_empty():
		var verdict := verdict_for(previous)
		if not verdict.begins_with("CLEAN"):
			var diagnosing := DiagnosticState.is_active_on_disk(diagnostics_state_path)
			var safe_note := "" if diagnosing else _enable_safe_visuals(verdict)
			var engine_log := _previous_engine_log()
			_write_report("PREVIOUS SESSION: " + verdict, previous, engine_log, exit_text, safe_note,
				last_trace_text)
			if not diagnosing:
				_show_report.call_deferred(format_report("PREVIOUS SESSION: " + verdict, _device_summary(),
					previous, engine_log, exit_text, safe_note, last_trace_text))
	_file = FileAccess.open(journal_path, FileAccess.WRITE)
	_lines = []
	_logger = _ErrorLogger.new(_log_engine_error)
	OS.add_logger(_logger)
	_log("START", "%s | %s | %s" % [_device_summary(), "debug" if OS.is_debug_build() else "release",
		_visual_flags()])
	_log_system_exit(system_exit)


## Pure: classifies a journal. Starts with "CLEAN" or "ABNORMAL".
static func verdict_for(lines: PackedStringArray) -> String:
	var last_exit := ""
	var in_background := false
	for line in lines:
		if line.contains(EXIT_MARKER):
			last_exit = line
		elif line.contains(PAUSED_MARKER):
			in_background = true
		elif line.contains(RESUMED_MARKER):
			in_background = false
	if last_exit != "":
		return "CLEAN, " + last_exit.get_slice(EXIT_MARKER, 1).strip_edges()
	if in_background:
		return "ABNORMAL, no exit event. The app was in the background: Android killed it " \
			+ "(low memory) or it was swiped away from recent apps."
	return "ABNORMAL, no exit event while the app was in the foreground: native crash, " \
		+ "freeze killed by the system (ANR) or out-of-memory."


## Pure: report text from a verdict, a device summary, the journal and (optionally) the engine log
## tail of the same session, Android's exit-reason section and a note about safe visuals.
static func format_report(verdict: String, device: String, lines: PackedStringArray,
		engine_log: PackedStringArray = PackedStringArray(), exit_reasons: String = "",
		safe_note: String = "", trace_section: String = "") -> String:
	var tail := lines.slice(maxi(0, lines.size() - TAIL_LINES))
	var events := key_events(lines)
	var engine_section := "Engine log: not available"
	if not engine_log.is_empty():
		engine_section = "Engine log, last %d lines:\n%s" % [engine_log.size(), "\n".join(engine_log)]
	var head := "Neural Connect exit report\n%s\n\n%s\nDevice: %s\n" % [
		Time.get_datetime_string_from_system(), verdict, device]
	if safe_note != "":
		head += "Safe visuals: %s\n" % safe_note
	if exit_reasons != "":
		head += "\n%s\n" % exit_reasons
	if trace_section != "":
		head += "\n%s\n" % trace_section
	return head + "\nKey events (%d):\n%s\n\n" % [events.size(), "\n".join(events)] \
		+ "Last %d journal lines (oldest first):\n%s\n\n%s\n" % [tail.size(), "\n".join(tail), engine_section]


## Pure: name of an ApplicationExitInfo.REASON_* code.
static func exit_reason_name(code: int) -> String:
	return EXIT_REASON_NAMES.get(code, "UNKNOWN(%d)" % code)


## Pure: one ApplicationExitInfo as a line. Keys: reason, status, description, importance, rss and
## pss (kB), timestamp (ms since the epoch); missing keys are skipped.
static func format_exit_info(entry: Dictionary) -> String:
	var reason := int(entry.get("reason", 0))
	var status := int(entry.get("status", 0))
	var parts := PackedStringArray(["%s (code %d)" % [exit_reason_name(reason), reason]])
	if reason == REASON_SIGNALED or reason == REASON_CRASH_NATIVE:
		parts.append("signal=%d %s" % [status, SIGNAL_NAMES.get(status, "?")])
	else:
		parts.append("status=%d" % status)
	if entry.has("importance"):
		var importance := int(entry["importance"])
		parts.append("importance=%s" % IMPORTANCE_NAMES.get(importance, str(importance)))
	var rss := int(entry.get("rss", 0))
	var pss := int(entry.get("pss", 0))
	if rss > 0 or pss > 0:
		parts.append("rss=%dMB pss=%dMB" % [int(rss / 1024.0), int(pss / 1024.0)])
	var timestamp := int(entry.get("timestamp", 0))
	if timestamp > 0:
		parts.append("at %s UTC" % Time.get_datetime_string_from_unix_time(int(timestamp / 1000.0), true))
	var description := str(entry.get("description", ""))
	if description != "":
		parts.append("description=\"%s\"" % description)
	return " | ".join(parts)


## Pure: the report section for Android's exit reasons (newest first, EXIT_SHOWN entries).
## `note` says why there are none (shown when entries is empty).
static func format_exit_reasons(entries: Array, note: String) -> String:
	if entries.is_empty():
		return "Android exit reasons (system record): not available (%s)" % (note if note != "" else "no entries")
	var lines := PackedStringArray(["Android exit reasons (system record), newest first:"])
	for i in mini(EXIT_SHOWN, entries.size()):
		lines.append("  %d. %s" % [i + 1, format_exit_info(entries[i])])
	return "\n".join(lines)


## Pure: crash-loop protection. After an abnormal close on a device the next launch runs with the
## trimmed visuals (low memory mode) unless they are already on. Desktop is left alone: killing the
## debugger there is routine.
static func should_enable_safe_visuals(verdict: String, mobile: bool, already_on: bool) -> bool:
	return mobile and not already_on and verdict.begins_with("ABNORMAL")


## Pure: the visual flags of a session, recorded in the journal START line.
static func visual_flags_summary(low_memory: bool, low_quality: bool, reduced_motion: bool) -> String:
	return "visuals: low_memory=%s low_quality=%s reduced_motion=%s" % [
		_on_off(low_memory), _on_off(low_quality), _on_off(reduced_motion)]


static func _on_off(value: bool) -> String:
	return "on" if value else "off"


## Pure: the most recent lines that are not heartbeats (start, lifecycle, memory warnings, errors).
static func key_events(lines: PackedStringArray) -> PackedStringArray:
	var events := PackedStringArray()
	for line in lines:
		if not line.contains(HEARTBEAT_TAG):
			events.append(line)
	return events.slice(maxi(0, events.size() - EVENT_LINES))


## Pure: the last `count` non-empty lines of a text.
static func last_lines(text: String, count: int) -> PackedStringArray:
	var lines := text.split("\n", false)
	return lines.slice(maxi(0, lines.size() - count))


## Pure: parses "Key:   123 kB" style lines (/proc/self/status, /proc/meminfo) into {key: first number}.
## Lines without a leading number are skipped.
static func parse_kv(text: String) -> Dictionary:
	var values := {}
	for line in text.split("\n", false):
		var key := line.get_slice(":", 0).strip_edges()
		var number := line.get_slice(":", 1).strip_edges().get_slice(" ", 0)
		if key != "" and line.contains(":") and number.is_valid_int():
			values[key] = number.to_int()
	return values


## Pure: process memory in MB from parsed /proc values (kB). Unknown values are left out.
static func format_process_memory(status: Dictionary, meminfo: Dictionary) -> String:
	var parts := PackedStringArray()
	for pair in [["rss", "VmRSS"], ["hwm", "VmHWM"], ["vsz", "VmSize"]]:
		if status.has(pair[1]):
			parts.append("%s=%dMB" % [pair[0], status[pair[1]] / 1024])
	if status.has("Threads"):
		parts.append("threads=%d" % status["Threads"])
	if meminfo.has("MemAvailable"):
		parts.append("avail=%dMB/%dMB" % [meminfo["MemAvailable"] / 1024, meminfo.get("MemTotal", 0) / 1024])
	return " ".join(parts)


## Pure: the newest rotated engine log ("godot<timestamp>.log"), ignoring the live "godot.log".
## Godot renames the previous session's log to that name when file logging starts, and the
## timestamp sorts chronologically.
static func latest_rotated_log(files: PackedStringArray) -> String:
	var latest := ""
	for file in files:
		if file.begins_with("godot") and file.ends_with(".log") and file != "godot.log" and file > latest:
			latest = file
	return latest


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_log("LIFECYCLE", "close request")
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_log("LIFECYCLE", "android back button")
		NOTIFICATION_APPLICATION_PAUSED:
			_log("LIFECYCLE", "paused")
		NOTIFICATION_APPLICATION_RESUMED:
			_log("LIFECYCLE", "resumed")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_log("LIFECYCLE", "focus out")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_log("LIFECYCLE", "focus in")
		NOTIFICATION_OS_MEMORY_WARNING:
			_log("MEMORY_WARNING", "the OS asked the app to free memory | " + _memory_summary())
		NOTIFICATION_CRASH:
			_exit("engine crash handler fired (native crash)")
		NOTIFICATION_EXIT_TREE:
			_exit("normal quit (scene tree exiting)")


func _exit(reason: String) -> void:
	if _exit_written:
		return
	_exit_written = true
	_log("EXIT", reason)
	_write_report("THIS SESSION: CLEAN, " + reason if not reason.contains("crash") \
		else "THIS SESSION: CRASH, " + reason, _lines)
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


func _heartbeat() -> void:
	_log("HB", "%s fps=%d" % [_memory_summary(), int(Performance.get_monitor(Performance.TIME_FPS))])


func _log_engine_error(function: String, file: String, line: int, code: String, rationale: String) -> void:
	_log("ENGINE_ERROR", "%s (%s:%d %s) %s" % [rationale if rationale != "" else code, file, line, function, code])


func _log(tag: String, detail: String) -> void:
	_mutex.lock()
	var entry := "[%7.1fs] %s %s" % [Time.get_ticks_msec() / 1000.0, tag, detail]
	# Keep the leading space so the markers (" EXIT ", " LIFECYCLE paused") match.
	_lines.append(entry)
	if _file != null:
		_file.store_line(entry)
		_file.flush()
	_mutex.unlock()


func _write_report(verdict: String, lines: PackedStringArray,
		engine_log: PackedStringArray = PackedStringArray(), exit_reasons: String = "",
		safe_note: String = "", trace_section: String = "") -> void:
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	if report == null:
		return
	report.store_string(format_report(verdict, _device_summary(), lines, engine_log, exit_reasons, safe_note,
		trace_section))
	report.close()


## Crash-loop protection (see should_enable_safe_visuals). GameState is reached by path so this
## autoload stays independent of it; it must load before this one (project.godot order). Returns the
## note for the report, "" when nothing changed.
func _enable_safe_visuals(verdict: String) -> String:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return ""
	if not should_enable_safe_visuals(verdict, PlatformProfile.is_mobile(), state.low_memory_mode):
		return ""
	state.set_low_memory_mode(true)
	return SAFE_VISUALS_NOTE


func _visual_flags() -> String:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return "visuals: unknown"
	return visual_flags_summary(state.low_memory_mode, VisualTuning.is_low_quality(), state.reduced_motion)


## Android only: asks the system why the previous processes of this app died. {supported, entries
## (newest first, one Dictionary per ApplicationExitInfo), note (why there are no entries)}. Every
## step is guarded: a missing singleton or an unexpected return type only fills `note`.
func _query_system_exit_reasons() -> Dictionary:
	var result := {"supported": false, "entries": [], "note": "", "trace_lines": PackedStringArray(),
		"trace_note": ""}
	if not OS.has_feature("android"):
		return result
	result["supported"] = true
	if not Engine.has_singleton("AndroidRuntime"):
		result["note"] = "AndroidRuntime singleton missing"
		return result
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	var activity: Variant = runtime.call(&"getActivity")
	if not activity is Object:
		result["note"] = "getActivity() returned no object"
		return result
	var manager: Variant = (activity as Object).call(&"getSystemService", "activity")
	if not manager is Object:
		result["note"] = "ActivityManager unavailable"
		return result
	var package_name: Variant = _java_call(activity, &"getPackageName", FALLBACK_PACKAGE)
	var list: Variant = (manager as Object).call(&"getHistoricalProcessExitReasons",
		package_name if package_name is String and package_name != "" else FALLBACK_PACKAGE, 0, EXIT_QUERY_MAX)
	if not list is Object:
		result["note"] = "getHistoricalProcessExitReasons returned no list (needs Android 11+)"
		return result
	var count := int(_java_call(list, &"size", 0))
	var entries: Array = result["entries"]
	for i in mini(count, EXIT_QUERY_MAX):
		var info: Variant = (list as Object).call(&"get", i)
		if info is Object:
			var entry := _read_exit_info(info)
			entries.append(entry)
			# Only the newest native crash: its tombstone names the library and function that failed.
			if int(entry["reason"]) == REASON_CRASH_NATIVE and result["trace_lines"].is_empty() \
					and result["trace_note"] == "":
				var trace := _read_trace(info)
				result["trace_lines"] = trace["lines"]
				result["trace_note"] = trace["note"]
	if entries.is_empty():
		result["note"] = "the system holds no exit record for this app yet (%d entries)" % count
	return result


func _read_exit_info(info: Object) -> Dictionary:
	return {
		"reason": int(_java_call(info, &"getReason", 0)),
		"status": int(_java_call(info, &"getStatus", 0)),
		"description": str(_java_call(info, &"getDescription", "")),
		"importance": int(_java_call(info, &"getImportance", 0)),
		"rss": int(_java_call(info, &"getRss", 0)),
		"pss": int(_java_call(info, &"getPss", 0)),
		"timestamp": int(_java_call(info, &"getTimestamp", 0)),
	}


## The readable text of the tombstone Android keeps for a native crash (ApplicationExitInfo
## .getTraceInputStream(), API 31+, read whole with InputStream.readAllBytes() on API 33+ and byte by
## byte before that). {lines, note}; every step is guarded and `note` says why there are no lines.
func _read_trace(info: Object) -> Dictionary:
	var out := {"lines": PackedStringArray(), "note": ""}
	var stream: Variant = info.call(&"getTraceInputStream")
	if not stream is Object:
		out["note"] = "the system keeps no trace for this crash"
		return out
	var data: Variant = (stream as Object).call(&"readAllBytes")
	var bytes := PackedByteArray()
	if data is PackedByteArray:
		bytes = data
	else:
		bytes = _read_stream_bytes(stream as Object)
	_java_call(stream, &"close", null)
	out["lines"] = NativeTrace.relevant_lines(bytes)
	if out["lines"].is_empty():
		out["note"] = "the tombstone has no readable library or function names (%d bytes read)" % bytes.size()
	return out


## Reads an InputStream one byte at a time (slow, but only a fallback), up to TRACE_MAX_BYTES.
func _read_stream_bytes(stream: Object) -> PackedByteArray:
	var bytes := PackedByteArray()
	while bytes.size() < TRACE_MAX_BYTES:
		var value: Variant = stream.call(&"read")
		if not value is int or int(value) < 0:
			break
		bytes.append(int(value))
	return bytes


## Calls a Java method through the wrapper; `fallback` when the call returns null.
static func _java_call(object: Variant, method: StringName, fallback: Variant) -> Variant:
	if not object is Object:
		return fallback
	var value: Variant = (object as Object).call(method)
	return fallback if value == null else value


## Writes the system's exit reasons into the journal so they survive with the session.
func _log_system_exit(system_exit: Dictionary) -> void:
	if not system_exit["supported"]:
		return
	var entries: Array = system_exit["entries"]
	if entries.is_empty():
		_log("SYSTEM_EXIT_REASON", "not available (%s)" % system_exit["note"])
		return
	for i in mini(EXIT_SHOWN, entries.size()):
		_log("SYSTEM_EXIT_REASON", "%d. %s" % [i + 1, format_exit_info(entries[i])])


## Overlay shown after an abnormal exit: the report text, a button that copies it to the clipboard
## (paste it in any chat to send it) and a best-effort copy into the public Downloads folder.
func _show_report(text: String) -> void:
	_copy_to_downloads(text)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "EXIT_REPORT_TITLE"
	box.add_child(title)
	var body := TextEdit.new()
	body.text = text
	body.editable = false
	body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var status := Label.new()
	box.add_child(status)
	var copy := Button.new()
	copy.text = "EXIT_REPORT_COPY"
	copy.custom_minimum_size.y = 64
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(text)
		status.text = "EXIT_REPORT_COPIED")
	box.add_child(copy)
	var close := Button.new()
	close.text = "EXIT_REPORT_CLOSE"
	close.custom_minimum_size.y = 64
	close.pressed.connect(layer.queue_free)
	box.add_child(close)


func _copy_to_downloads(text: String) -> void:
	write_to_downloads(text, "neural_connect_exit_report.txt")


## Best effort: writes text into the public Downloads folder (where the player can find it without
## a cable). False when the folder is unknown or not writable.
static func write_to_downloads(text: String, file_name: String) -> bool:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dir == "":
		return false
	var file := FileAccess.open(dir.path_join(file_name), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _read_lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var text := FileAccess.get_file_as_string(path)
	var result := PackedStringArray()
	for line in text.split("\n", false):
		result.append(line)
	return result


func _device_summary() -> String:
	return "%s | model=%s | cpu=%s | gpu=%s | renderer=%s/%s | godot=%s | screen=%s | app=%s" % [
		_os_summary(), OS.get_model_name(), OS.get_processor_name(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), Engine.get_version_info().get("string", "?"),
		DisplayServer.screen_get_size(), ProjectSettings.get_setting("application/config/version", "?")]


## "Android 15 (raw 35.9536e5)": the alias is the readable release, OS.get_version() the raw build value.
func _os_summary() -> String:
	var alias := OS.get_version_alias()
	var raw := OS.get_version()
	if alias == "" or alias == OS.get_name():
		return "%s %s" % [OS.get_name(), raw]
	return "%s (raw %s)" % [alias, raw]


## One heartbeat's numbers: process memory from /proc (Android/Linux), engine memory and render
## counters. Values the platform does not provide are left out instead of printing -1.
func _memory_summary() -> String:
	var parts := PackedStringArray()
	var process := format_process_memory(
		parse_kv(_read_proc(PROC_STATUS_PATH)), parse_kv(_read_proc(PROC_MEMINFO_PATH)))
	if process != "":
		parts.append(process)
	else:
		var info := OS.get_memory_info()
		if info.get("physical", -1) > 0:
			parts.append("ram_free=%dMB ram_total=%dMB" % [info.get("free", 0) / 1048576, info["physical"] / 1048576])
	parts.append("static=%dMB" % (OS.get_static_memory_usage() / 1048576))
	parts.append("tex=%dMB buf=%dMB vram=%dMB" % [
		_monitor_mb(Performance.RENDER_TEXTURE_MEM_USED), _monitor_mb(Performance.RENDER_BUFFER_MEM_USED),
		_monitor_mb(Performance.RENDER_VIDEO_MEM_USED)])
	parts.append("obj=%d nodes=%d draws=%d" % [
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	return " ".join(parts)


static func _monitor_mb(monitor: Performance.Monitor) -> int:
	return int(Performance.get_monitor(monitor) / 1048576.0)


## Reads a /proc file line by line (their reported size is 0, so a whole-file read returns nothing).
## Empty when the file does not exist (desktop) or cannot be read.
func _read_proc(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var lines := PackedStringArray()
	while not file.eof_reached() and lines.size() < PROC_MAX_LINES:
		lines.append(file.get_line())
	return "\n".join(lines)


## Tail of the previous session's engine log (Godot rotates it to godot<timestamp>.log when file
## logging starts; see debug/file_logging). Best effort: empty when logging is off or the file is gone.
func _previous_engine_log() -> PackedStringArray:
	var name := latest_rotated_log(DirAccess.get_files_at(LOG_DIR))
	if name == "":
		return PackedStringArray()
	var file := FileAccess.open(LOG_DIR.path_join(name), FileAccess.READ)
	if file == null:
		return PackedStringArray()
	return last_lines(file.get_as_text(), ENGINE_LOG_LINES)


## Forwards engine errors/warnings (may arrive from any thread) to a callable.
class _ErrorLogger extends Logger:
	var _sink: Callable

	func _init(sink: Callable) -> void:
		_sink = sink

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_sink.call(function, file, line, code, rationale)
