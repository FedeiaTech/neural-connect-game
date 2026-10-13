class_name DiagnosticState
extends RefCounted
## The persisted record of an on-device diagnostic run (see DiagnosticRunner). A step is written as
## RUNNING (with its start time) before it begins and as OK when it ends. If the app dies in
## between, the next launch finds a step that began and never ended: recover_after_restart() marks
## it CRASHED (with how long it ran and the process uptime of its last tick), skips it and the run
## goes on with the next one. Pure data plus a flushed JSON file, so it survives a native crash.

const DEFAULT_PATH := "user://diagnostics_state.json"

const PENDING := "pending"
const RUNNING := "running"
const OK := "ok"
const CRASHED := "crashed"
const SKIPPED := "skipped"

var step_ids := PackedStringArray()
## Step id -> Dictionary (status, manual, flags, uptime_start_s, last_elapsed_s, last_uptime_s,
## last_fps, crash_elapsed_s, crash_uptime_s, note and the metrics of finish_step()).
var results: Dictionary = {}
## The step that began and has not ended yet ("" when none).
var current := ""
var finished := false
## Process launches seen during the run (1 + one per recovery).
var launches := 1
var started_at := ""
## Visual flags (low memory, quality, reduced motion) when the run started.
var flags := ""
## Device capability block, captured once when the run starts.
var device := ""
## Set when the player closed the app on purpose (back button), so the step is retried, not blamed.
var user_exit := false


static func create(ids: PackedStringArray, started := "", flags_text := "") -> DiagnosticState:
	var state := DiagnosticState.new()
	state.step_ids = ids
	state.started_at = started
	state.flags = flags_text
	return state


## A run exists and has steps left.
func is_active() -> bool:
	return not step_ids.is_empty() and not finished


func status_of(id: String) -> String:
	if not results.has(id):
		return PENDING
	return String(results[id].get("status", PENDING))


func next_pending() -> String:
	for id in step_ids:
		if status_of(id) == PENDING:
			return id
	return ""


func count_by_status(status: String) -> int:
	var count := 0
	for id in step_ids:
		if status_of(id) == status:
			count += 1
	return count


func begin_step(id: String, uptime_s: float, flags_text: String, manual: bool) -> void:
	results[id] = {"status": RUNNING, "manual": manual, "flags": flags_text,
		"uptime_start_s": uptime_s, "last_elapsed_s": 0.0, "last_uptime_s": uptime_s, "last_fps": 0.0}
	current = id


## Progress of the running step, saved about once a second: if the app dies, these numbers say how
## far into the step (and how long after the process started) it got.
func note_tick(elapsed_s: float, uptime_s: float, fps: float) -> void:
	if current == "" or not results.has(current):
		return
	var entry: Dictionary = results[current]
	entry["last_elapsed_s"] = elapsed_s
	entry["last_uptime_s"] = uptime_s
	entry["last_fps"] = fps


func finish_step(id: String, metrics: Dictionary) -> void:
	var entry: Dictionary = results.get(id, {})
	entry["status"] = OK
	entry.merge(metrics, true)
	results[id] = entry
	if current == id:
		current = ""
	_check_finished()


func skip_step(id: String, reason: String) -> void:
	results[id] = {"status": SKIPPED, "note": reason, "manual": false}
	_check_finished()


## The player closed the app on purpose while a step ran (back button).
func mark_user_exit() -> void:
	user_exit = true


## Called on every relaunch of a run in progress. A step left RUNNING is a crash (or, after
## mark_user_exit(), a step to repeat). Returns that step's id, "" when none was running.
func recover_after_restart() -> String:
	launches += 1
	var id := current
	current = ""
	if id == "":
		user_exit = false
		return ""
	if user_exit:
		results.erase(id)
	else:
		var entry: Dictionary = results.get(id, {})
		entry["status"] = CRASHED
		entry["crash_elapsed_s"] = float(entry.get("last_elapsed_s", 0.0))
		entry["crash_uptime_s"] = float(entry.get("last_uptime_s", 0.0))
		results[id] = entry
	user_exit = false
	_check_finished()
	return id


func to_dict() -> Dictionary:
	return {"step_ids": Array(step_ids), "results": results, "current": current, "finished": finished,
		"launches": launches, "started_at": started_at, "flags": flags, "device": device,
		"user_exit": user_exit}


static func from_dict(data: Variant) -> DiagnosticState:
	if not data is Dictionary:
		return null
	var state := DiagnosticState.new()
	var ids: Variant = data.get("step_ids")
	if ids is Array:
		for id in ids:
			state.step_ids.append(String(id))
	var saved: Variant = data.get("results")
	if saved is Dictionary:
		state.results = saved
	state.current = String(data.get("current", ""))
	state.finished = bool(data.get("finished", false))
	state.launches = int(data.get("launches", 1))
	state.started_at = String(data.get("started_at", ""))
	state.flags = String(data.get("flags", ""))
	state.device = String(data.get("device", ""))
	state.user_exit = bool(data.get("user_exit", false))
	return state


## Writes the state and flushes it so it is on disk even if the app dies a moment later.
func save(path := DEFAULT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict()))
	file.flush()
	file.close()
	return true


## The state saved at path, or null when there is none or it is unreadable.
static func load_from(path := DEFAULT_PATH) -> DiagnosticState:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != Error.OK:
		return null
	return from_dict(json.data)


static func is_active_on_disk(path := DEFAULT_PATH) -> bool:
	var state := load_from(path)
	return state != null and state.is_active()


static func clear(path := DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_finished() -> void:
	if not step_ids.is_empty() and next_pending() == "" and current == "":
		finished = true
