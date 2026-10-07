extends GdUnitTestSuite
## T1.5: win condition (zero crossings on release) and move counting.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")

## In x_level, moving neuron 3 here makes edge 2-3 horizontal at y = 100: zero crossings.
const UNTANGLED := Vector2(900, 100)

var _recorder: SignalRecorder
var _model: PuzzleModel


func before_test() -> void:
	_recorder = SignalRecorder.new()
	_model = PuzzleModel.from_level(LevelFactory.x_level())
	_recorder.watch(_model, [&"solved"])


func test_new_model_is_not_solved() -> void:
	assert_bool(_model.is_solved()).is_false()
	assert_int(_model.get_move_count()).is_equal(0)


func test_grab_and_release_without_moving_is_not_a_move() -> void:
	_model.grab(3)
	_model.release()
	assert_int(_model.get_move_count()).is_equal(0)


func test_full_drag_counts_one_move() -> void:
	_model.grab(3)
	_model.drag_to(Vector2(150, 550))
	_model.drag_to(Vector2(200, 600))
	_model.release()
	assert_int(_model.get_move_count()).is_equal(1)


func test_each_drag_counts_a_move() -> void:
	for target: Vector2 in [Vector2(150, 550), Vector2(200, 600), Vector2(150, 550)]:
		_model.grab(3)
		_model.drag_to(target)
		_model.release()
	assert_int(_model.get_move_count()).is_equal(3)


func test_drag_fully_blocked_is_not_a_move() -> void:
	_model.grab(0)
	_model.drag_to(Vector2(-100, 100))
	_model.drag_to(Vector2(-200, 100))
	_model.release()
	# Neuron 0 starts at (100, 100), so it does move to the wall once: that is one move.
	assert_int(_model.get_move_count()).is_equal(1)
	_model.grab(0)
	_model.drag_to(Vector2(-200, 100))
	_model.release()
	assert_int(_model.get_move_count()).is_equal(1)


func test_release_with_crossings_does_not_solve() -> void:
	_model.grab(3)
	_model.drag_to(Vector2(150, 550))
	_model.release()
	assert_bool(_model.is_solved()).is_false()
	assert_int(_recorder.count(&"solved")).is_equal(0)


func test_release_with_zero_crossings_solves() -> void:
	_model.grab(3)
	_model.drag_to(UNTANGLED)
	_model.release()
	assert_bool(_model.is_solved()).is_true()
	assert_int(_recorder.count(&"solved")).is_equal(1)


func test_solved_via_monitor() -> void:
	var monitor := monitor_signals(_model, false)
	_model.grab(3)
	_model.drag_to(UNTANGLED)
	_model.release()
	await assert_signal(monitor).is_emitted("solved")


func test_zero_crossings_while_dragging_does_not_solve_before_release() -> void:
	_model.grab(3)
	_model.drag_to(UNTANGLED)
	assert_bool(_model.is_solved()).is_false()
	assert_int(_recorder.count(&"solved")).is_equal(0)


func test_solved_is_emitted_only_once() -> void:
	_model.grab(3)
	_model.drag_to(UNTANGLED)
	_model.release()
	_model.grab(3)
	_model.drag_to(UNTANGLED + Vector2(0, 50))
	_model.release()
	assert_int(_recorder.count(&"solved")).is_equal(1)
