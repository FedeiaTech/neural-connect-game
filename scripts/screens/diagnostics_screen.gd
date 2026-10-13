class_name DiagnosticsScreen
extends Control
## On-device diagnostic battery (SDD-free tooling, see DiagnosticRunner): shows what the runner is
## doing, offers Start / Cancel, and at the end the report to copy. Entered from Settings, and
## entered by itself at launch when a run is in progress (main.gd), so after a crash a single tap on
## the app icon continues with the next step. The steps draw into the Stage; the controls live in
## their own CanvasLayer so a step's transition can never cover them.
## The AudioDirector is silenced while a run is in progress so only the steps make sound.

signal back_pressed()

const REPORT_PATH := "user://diagnostics_report.txt"
const DOWNLOADS_NAME := "neural_connect_diagnostics.txt"
const OVERLAY := "Overlay/"
const COLUMN := OVERLAY + "ResultPanel/Column/"

## Set before the screen enters the tree (tests use their own files).
var state_path := DiagnosticState.DEFAULT_PATH
var report_path := REPORT_PATH

@onready var _stage: Control = $Stage
@onready var _status_box: Control = get_node(OVERLAY + "StatusBox")
@onready var _status_label: Label = get_node(OVERLAY + "StatusBox/StatusLabel")
@onready var _hint_label: Label = get_node(OVERLAY + "StatusBox/HintLabel")
@onready var _cancel_button: Button = get_node(OVERLAY + "StatusBox/CancelButton")
@onready var _result_panel: Control = get_node(OVERLAY + "ResultPanel")
@onready var _report_text: TextEdit = get_node(COLUMN + "ReportText")
@onready var _message_label: Label = get_node(COLUMN + "MessageLabel")
@onready var _start_button: Button = get_node(COLUMN + "ButtonRow/StartButton")
@onready var _copy_button: Button = get_node(COLUMN + "ButtonRow/CopyButton")
@onready var _reset_button: Button = get_node(COLUMN + "ButtonRow/ResetButton")
@onready var _back_button: Button = get_node(COLUMN + "ButtonRow/BackButton")

var _runner: DiagnosticRunner
var _audio: AudioDirector
var _report := ""
var _notice := ""


func _ready() -> void:
	_runner = DiagnosticRunner.new()
	_runner.state_path = state_path
	_runner.stage = _stage
	_runner.crash_info = _crash_info
	add_child(_runner)
	_runner.recovered.connect(_on_recovered)
	_runner.run_finished.connect(_on_run_finished)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_start_button.pressed.connect(_begin.bind(false))
	_copy_button.pressed.connect(_on_copy_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	if DiagnosticState.is_active_on_disk(state_path):
		_begin(true)
	else:
		_show_idle()


func _exit_tree() -> void:
	_restore_audio()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _result_panel.visible:
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _process(_delta: float) -> void:
	var step := _runner.get_current_step()
	if step == null:
		return
	var state := _runner.get_state()
	var line := tr(&"DIAG_STEP") % [_runner.get_step_index() + 1, state.step_ids.size(), String(step.id),
		int(_runner.get_step_elapsed()), int(step.duration)]
	_status_label.text = line if _notice == "" else _notice + "\n" + line
	_hint_label.text = tr(step.hint_key) if step.hint_key != "" else ""


func get_runner() -> DiagnosticRunner:
	return _runner


func get_start_button() -> Button:
	return _start_button


func get_cancel_button() -> Button:
	return _cancel_button


func get_back_button() -> Button:
	return _back_button


func get_copy_button() -> Button:
	return _copy_button


func get_reset_button() -> Button:
	return _reset_button


func get_report_text() -> String:
	return _report_text.text


func is_result_visible() -> bool:
	return _result_panel.visible


func _begin(resume: bool) -> void:
	_notice = ""
	_message_label.text = ""
	_silence_audio()
	_result_panel.hide()
	_status_box.show()
	if resume:
		if not _runner.resume():
			_restore_audio()
			_show_idle()
	else:
		_runner.start_new()


## Result panel with the intro (nothing run yet) or the last finished report.
func _show_idle() -> void:
	_status_box.hide()
	_hint_label.text = ""
	var saved := DiagnosticState.load_from(state_path)
	var has_results := saved != null and not saved.results.is_empty()
	_report = _format_report(saved) if has_results else ""
	_report_text.text = _report if has_results else tr(&"DIAG_INTRO")
	_start_button.text = "DIAG_RERUN" if has_results else "DIAG_START"
	_copy_button.visible = has_results
	_reset_button.visible = has_results
	_message_label.text = ""
	_result_panel.show()
	_start_button.grab_focus()


func _on_recovered(_id: String, _status: String) -> void:
	_notice = tr(&"DIAG_RESUMED")


func _on_run_finished() -> void:
	_report = _format_report(_runner.get_state())
	_write_report(_report)
	_restore_audio()
	_status_box.hide()
	_report_text.text = _report
	_start_button.text = "DIAG_RERUN"
	_copy_button.show()
	_reset_button.show()
	_message_label.text = tr(&"DIAG_DONE")
	_result_panel.show()
	_start_button.grab_focus()


func _on_cancel_pressed() -> void:
	_runner.cancel()
	_restore_audio()
	_show_idle()


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_report)
	_message_label.text = tr(&"EXIT_REPORT_COPIED")


func _on_reset_pressed() -> void:
	DiagnosticState.clear(state_path)
	_show_idle()


func _on_back_pressed() -> void:
	_restore_audio()
	back_pressed.emit()


func _format_report(state: DiagnosticState) -> String:
	return DiagnosticReport.format(state, {"titles": _runner.get_titles(), "device": state.device,
		"generated": Time.get_datetime_string_from_system()})


func _write_report(text: String) -> void:
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
	ExitReport.write_to_downloads(text, DOWNLOADS_NAME)


## What the system recorded about the previous process: ExitReport read it at startup.
func _crash_info() -> Dictionary:
	return {"exit": ExitReport.last_exit_text, "trace": ExitReport.last_trace_text}


func _silence_audio() -> void:
	if _audio != null or not is_inside_tree():
		return
	_audio = get_tree().root.find_child("AudioDirector", true, false) as AudioDirector
	if _audio != null:
		_audio.silence()


func _restore_audio() -> void:
	if _audio != null and is_instance_valid(_audio):
		_audio.restore()
	_audio = null
