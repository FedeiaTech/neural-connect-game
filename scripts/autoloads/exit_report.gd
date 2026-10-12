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
const HEARTBEAT_SECONDS := 5.0
const TAIL_LINES := 60
const EXIT_MARKER := " EXIT "
const PAUSED_MARKER := " LIFECYCLE paused"
const RESUMED_MARKER := " LIFECYCLE resumed"

var journal_path := JOURNAL_PATH
var report_path := REPORT_PATH

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
	if not previous.is_empty():
		var verdict := verdict_for(previous)
		if not verdict.begins_with("CLEAN"):
			_write_report("PREVIOUS SESSION: " + verdict, previous)
			_show_report.call_deferred(format_report("PREVIOUS SESSION: " + verdict, _device_summary(), previous))
	_file = FileAccess.open(journal_path, FileAccess.WRITE)
	_lines = []
	_logger = _ErrorLogger.new(_log_engine_error)
	OS.add_logger(_logger)
	_log("START", "%s | %s" % [_device_summary(), "debug" if OS.is_debug_build() else "release"])


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


## Pure: report text from a verdict, a device summary and the journal tail.
static func format_report(verdict: String, device: String, lines: PackedStringArray) -> String:
	var tail := lines.slice(maxi(0, lines.size() - TAIL_LINES))
	return "Neural Connect exit report\n%s\n\n%s\n\nLast %d journal lines (oldest first):\n%s\n" \
		% [Time.get_datetime_string_from_system(), "%s\nDevice: %s" % [verdict, device],
			tail.size(), "\n".join(tail)]


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
	_log("HB", "%s | fps=%d" % [_memory_summary(), int(Performance.get_monitor(Performance.TIME_FPS))])


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


func _write_report(verdict: String, lines: PackedStringArray) -> void:
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	if report == null:
		return
	report.store_string(format_report(verdict, _device_summary(), lines))
	report.close()


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
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dir == "":
		return
	var file := FileAccess.open(dir.path_join("neural_connect_exit_report.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _read_lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var text := FileAccess.get_file_as_string(path)
	var result := PackedStringArray()
	for line in text.split("\n", false):
		result.append(line)
	return result


func _device_summary() -> String:
	return "%s %s | model=%s | cpu=%s | gpu=%s | godot=%s | screen=%s | app=%s" % [
		OS.get_name(), OS.get_version(), OS.get_model_name(), OS.get_processor_name(),
		RenderingServer.get_video_adapter_name(), Engine.get_version_info().get("string", "?"),
		DisplayServer.screen_get_size(), ProjectSettings.get_setting("application/config/version", "?")]


func _memory_summary() -> String:
	var info := OS.get_memory_info()
	return "static=%dMB ram_free=%dMB ram_total=%dMB" % [
		OS.get_static_memory_usage() / 1048576, _mb(info.get("free", -1)), _mb(info.get("physical", -1))]


static func _mb(bytes: int) -> int:
	return bytes / 1048576 if bytes >= 0 else -1


## Forwards engine errors/warnings (may arrive from any thread) to a callable.
class _ErrorLogger extends Logger:
	var _sink: Callable

	func _init(sink: Callable) -> void:
		_sink = sink

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_sink.call(function, file, line, code, rationale)
