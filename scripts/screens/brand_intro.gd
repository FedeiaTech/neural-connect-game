class_name BrandIntro
extends Control
## Studio splash shown right after the Godot boot splash: the Chainsaw Games logo fades in on
## white, holds, and fades out; then finished is emitted (ScreenHost goes to the main menu).
## A tap, click or key press skips it. Reduced motion: no fades, only the hold.

signal finished()

const FADE_IN := 0.7
const HOLD := 1.3
const FADE_OUT := 0.5

@onready var _logo: TextureRect = $Logo

var _tween: Tween
var _done := false


func _ready() -> void:
	if VisualTuning.is_motion_enabled():
		_logo.modulate.a = 0.0
	_tween = create_tween()
	if VisualTuning.is_motion_enabled():
		_tween.tween_property(_logo, ^"modulate:a", 1.0, FADE_IN) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD)
	if VisualTuning.is_motion_enabled():
		_tween.tween_property(_logo, ^"modulate:a", 0.0, FADE_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish)


func _unhandled_input(event: InputEvent) -> void:
	var skip := event.is_pressed() and not event.is_echo() \
		and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch)
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _tween != null:
		_tween.kill()
	finished.emit()
