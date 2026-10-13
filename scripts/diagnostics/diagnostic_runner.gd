class_name DiagnosticRunner
extends Node
## Runs the diagnostic battery (DiagnosticSteps) one step at a time inside a stage Control and keeps
## the DiagnosticState on disk. Before a step starts its BEGIN is flushed to the state file; its END
## is written when it finishes. When the app dies in a step, resume() on the next launch finds the
## step that began and never ended, records it as CRASHED (with how long it ran and the process
## uptime) and goes on with the next one, so a single install can map out every crash.
## Time is driven by _process; tick() is public so tests can drive it.

signal step_started(id: String, index: int, total: int)
signal step_finished(id: String, status: String)
## A relaunch found the step `id` unfinished (status says CRASHED, or PENDING when the player left).
signal recovered(id: String, status: String)
signal run_finished()

enum Phase { IDLE, GAP, RUNNING, DONE }

const WARMUP_SECONDS := 1.0
const SAMPLE_INTERVAL := 0.25
const TICK_INTERVAL := 1.0

var state_path := DiagnosticState.DEFAULT_PATH
## Where the steps build their scenes. Set before start_new() / resume().
var stage: Control
## Defaults to DiagnosticSteps.build_all(); tests inject their own.
var steps: Array[DiagnosticStep] = []
var gap_seconds := 0.5
var headless := DisplayServer.get_name() == "headless"
## Optional: returns {exit, trace} text about the previous process (Android's exit record) so a
## crashed step carries what the system said about it.
var crash_info := Callable()

var _state: DiagnosticState
var _phase := Phase.IDLE
var _step: DiagnosticStep
var _step_index := 0
var _elapsed := 0.0
var _gap := 0.0
var _sample_clock := 0.0
var _tick_clock := 0.0
var _fps_sum := 0.0
var _fps_count := 0
var _fps_min := INF
var _memory_start := {}


func _process(delta: float) -> void:
	tick(delta)


func _notification(what: int) -> void:
	# Leaving by the back button is the player's choice, not a crash: the step is retried.
	if (what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST) \
			and _phase == Phase.RUNNING and _state != null:
		_state.mark_user_exit()
		_state.save(state_path)


func _exit_tree() -> void:
	if _phase == Phase.RUNNING and _step != null:
		_step.end()
		_step = null


## Begins a fresh run (replacing any saved one).
func start_new() -> void:
	_ensure_steps()
	var ids := PackedStringArray()
	for step in steps:
		ids.append(String(step.id))
	_state = DiagnosticState.create(ids, Time.get_datetime_string_from_system(), _flags_text())
	_state.device = DiagnosticDevice.describe()
	_state.save(state_path)
	_enter_gap()


## Continues the saved run after a relaunch. False when there is none in progress.
func resume() -> bool:
	var saved := DiagnosticState.load_from(state_path)
	if saved == null or not saved.is_active():
		return false
	_ensure_steps()
	_state = saved
	var affected := _state.recover_after_restart()
	if affected != "":
		_attach_crash_info(affected)
		recovered.emit(affected, _state.status_of(affected))
	_state.save(state_path)
	if _state.finished:
		_finish_run()
	else:
		_enter_gap()
	return true


## Stops the current step and forgets the run (the state file is deleted).
func cancel() -> void:
	if _step != null:
		_step.end()
		_step = null
	_clear_stage()
	DiagnosticState.clear(state_path)
	_state = null
	_phase = Phase.IDLE


func is_running() -> bool:
	return _phase == Phase.GAP or _phase == Phase.RUNNING


func get_state() -> DiagnosticState:
	return _state


func get_current_step() -> DiagnosticStep:
	return _step


func get_step_index() -> int:
	return _step_index


func get_step_elapsed() -> float:
	return _elapsed


## {step id: English title}, for the report.
func get_titles() -> Dictionary:
	_ensure_steps()
	var titles := {}
	for step in steps:
		titles[String(step.id)] = step.title
	return titles


func tick(delta: float) -> void:
	match _phase:
		Phase.GAP:
			_gap -= delta
			if _gap <= 0.0:
				_begin_next()
		Phase.RUNNING:
			_run(delta)


# --- Internals ---------------------------------------------------------------

func _ensure_steps() -> void:
	if steps.is_empty():
		steps = DiagnosticSteps.build_all()


func _enter_gap() -> void:
	_phase = Phase.GAP
	_gap = gap_seconds


func _find_step(id: String) -> DiagnosticStep:
	for step in steps:
		if String(step.id) == id:
			return step
	return null


func _begin_next() -> void:
	while true:
		var id := _state.next_pending()
		if id == "":
			_finish_run()
			return
		var step := _find_step(id)
		if step == null:
			_state.skip_step(id, "unknown step")
		elif step.requires_window and headless:
			_state.skip_step(id, "needs a window (headless run)")
			step_finished.emit(id, DiagnosticState.SKIPPED)
		else:
			_start_step(step)
			return
		_state.save(state_path)


func _start_step(step: DiagnosticStep) -> void:
	_step = step
	_step_index = _state.step_ids.find(String(step.id))
	_elapsed = 0.0
	_sample_clock = 0.0
	_tick_clock = 0.0
	_fps_sum = 0.0
	_fps_count = 0
	_fps_min = INF
	_memory_start = _sample_memory()
	# Written and flushed before the step touches anything: if it kills the app, this is the proof.
	_state.begin_step(String(step.id), _uptime(), _flags_text(), step.manual)
	_state.save(state_path)
	_phase = Phase.RUNNING
	step_started.emit(String(step.id), _step_index + 1, _state.step_ids.size())
	step.begin(stage)


func _run(delta: float) -> void:
	_elapsed += delta
	_step.update(delta, _elapsed)
	_sample_clock += delta
	if _sample_clock >= SAMPLE_INTERVAL:
		_sample_clock = 0.0
		if _elapsed >= WARMUP_SECONDS:
			var fps := Performance.get_monitor(Performance.TIME_FPS)
			_fps_sum += fps
			_fps_count += 1
			_fps_min = minf(_fps_min, fps)
	_tick_clock += delta
	if _tick_clock >= TICK_INTERVAL:
		_tick_clock = 0.0
		_state.note_tick(_elapsed, _uptime(), Performance.get_monitor(Performance.TIME_FPS))
		_state.save(state_path)
	if _elapsed >= _step.duration:
		_complete_step()


func _complete_step() -> void:
	var step := _step
	_step = null
	step.end()
	_clear_stage()
	var memory := _sample_memory()
	var metrics := {
		"duration_s": _elapsed,
		"fps_min": 0.0 if _fps_count == 0 else _fps_min,
		"fps_avg": 0.0 if _fps_count == 0 else _fps_sum / _fps_count,
		"static_mb_start": _memory_start["static_mb"], "static_mb_end": memory["static_mb"],
		"vram_mb_start": _memory_start["vram_mb"], "vram_mb_end": memory["vram_mb"],
		"nodes_end": memory["nodes"],
	}
	_state.finish_step(String(step.id), metrics)
	_state.save(state_path)
	step_finished.emit(String(step.id), DiagnosticState.OK)
	if _state.finished:
		_finish_run()
	else:
		_enter_gap()


func _finish_run() -> void:
	_phase = Phase.DONE
	_state.finished = true
	_state.save(state_path)
	run_finished.emit()


func _clear_stage() -> void:
	if stage == null:
		return
	for child in stage.get_children():
		stage.remove_child(child)
		child.queue_free()


func _attach_crash_info(id: String) -> void:
	if not crash_info.is_valid() or _state.status_of(id) != DiagnosticState.CRASHED:
		return
	var info: Variant = crash_info.call()
	if not info is Dictionary:
		return
	var entry: Dictionary = _state.results[id]
	entry["system_exit"] = String(info.get("exit", ""))
	entry["trace"] = String(info.get("trace", ""))


func _flags_text() -> String:
	return "%s | renderer=%s/%s" % [
		ExitReport.visual_flags_summary(GameState.low_memory_mode, VisualTuning.is_low_quality(),
			GameState.reduced_motion),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()]


static func _uptime() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _sample_memory() -> Dictionary:
	return {
		"static_mb": int(OS.get_static_memory_usage() / 1048576.0),
		"vram_mb": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}
