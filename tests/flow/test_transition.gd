extends GdUnitTestSuite
## T3.1: Transition fades a full-screen ColorRect (SDD 5.5); reduced motion makes it instant.

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const MainScene := preload("res://scenes/main.tscn")

var _sandbox: Sandbox
var _transition: Transition


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	var main: Node = auto_free(MainScene.instantiate())
	add_child(main)
	_transition = main.get_node("Transition")


func after_test() -> void:
	_sandbox.exit()


func test_reduced_motion_is_instant() -> void:
	assert_float(_transition.get_alpha()).is_equal(0.0)
	_transition.cover()
	assert_float(_transition.get_alpha()).is_equal(1.0)
	assert_bool(_transition.is_blocking_input()).is_true()
	_transition.reveal()
	assert_float(_transition.get_alpha()).is_equal(0.0)
	assert_bool(_transition.is_blocking_input()).is_false()


func test_fade_is_animated_without_reduced_motion() -> void:
	GameState.reduced_motion = false
	_transition.cover()
	assert_float(_transition.get_alpha()).is_less(1.0)
	assert_bool(_transition.is_animating()).is_true()
	await await_millis(int(Transition.FADE_DURATION * 1000.0) + 100)
	assert_float(_transition.get_alpha()).is_equal_approx(1.0, 0.001)
	assert_bool(_transition.is_animating()).is_false()
	await _transition.reveal()
	assert_float(_transition.get_alpha()).is_equal_approx(0.0, 0.001)


func test_transition_keeps_running_while_the_tree_is_paused() -> void:
	assert_int(_transition.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
