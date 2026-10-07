class_name Transition
extends CanvasLayer
## Full-screen fade between screens (SDD 5.5: never a hard cut). ScreenHost calls cover(),
## swaps the screen, then reveal(). Honors GameState.reduced_motion (instant fades).
## The Fade rect draws assets/shaders/iris_fade.gdshader: its color alpha is the progress, shown as
## a soft iris closing from the edges (cover) and opening from the center (reveal).
## Runs with PROCESS_MODE_ALWAYS so it also works while the tree is paused.

## One full transition (cover + reveal) lasts about this long.
const FADE_DURATION := 0.35

@onready var _fade: ColorRect = $Fade

var _tween: Tween


## Starts covered so the first screen fades in from black.
func _ready() -> void:
	set_alpha(1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP


## Fades to opaque and blocks input. Await it before swapping screens.
func cover() -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0)


## Fades back to transparent and lets input through again.
func reveal() -> void:
	await _fade_to(0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func get_alpha() -> float:
	return _fade.color.a


func set_alpha(alpha: float) -> void:
	_fade.color.a = alpha


func is_animating() -> bool:
	return _tween != null and _tween.is_running()


func is_blocking_input() -> bool:
	return _fade.mouse_filter == Control.MOUSE_FILTER_STOP


func _fade_to(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	var distance := absf(alpha - get_alpha())
	if GameState.reduced_motion or is_zero_approx(distance):
		set_alpha(alpha)
		return
	_tween = create_tween()
	_tween.tween_property(_fade, ^"color:a", alpha, FADE_DURATION * 0.5 * distance) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
