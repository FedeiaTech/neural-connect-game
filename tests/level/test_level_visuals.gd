extends GdUnitTestSuite
## T4.1-T4.4: the Level scene builds its visuals and runs frames (motion on and off) without
## runtime errors. Rendering itself is checked by tests/visual/capture_level.tscn.

const LevelScene := preload("res://scenes/level/level.tscn")
const M01_PATH := "res://data/levels/m01.tres"
const M02_PATH := "res://data/levels/m02.tres"
const FRAMES := 60

var _level: Level
var _saved_reduced_motion := false


func before_test() -> void:
	_saved_reduced_motion = GameState.reduced_motion
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)


func after_test() -> void:
	GameState.reduced_motion = _saved_reduced_motion
	get_tree().paused = false


func _run_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _play(path: String) -> LevelController:
	_level.load_level(load(path))
	_level.get_hud().hide_story()
	_level.get_controller().start_playing()
	return _level.get_controller()


func test_m01_runs_frames_with_motion() -> void:
	GameState.reduced_motion = false
	var controller := _play(M01_PATH)
	await _run_frames(FRAMES)
	assert_int(controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_int(controller.dendrites_root.get_child_count()).is_greater(0)


func test_m02_runs_frames_with_reduced_motion() -> void:
	GameState.reduced_motion = true
	var controller := _play(M02_PATH)
	await _run_frames(FRAMES)
	var view := controller.get_neuron_view(controller.get_model().get_neuron_ids()[0])
	assert_float(view.get_shader_param(&"motion")).is_equal(0.0)


func test_dragging_and_grabbing_while_frames_run() -> void:
	GameState.reduced_motion = false
	var controller := _play(M01_PATH)
	var model := controller.get_model()
	var id: int = model.get_neuron_ids()[0]
	model.grab(id)
	controller.get_neuron_view(id).set_grabbed(true)
	for step in 20:
		model.drag_to(model.get_neuron_position(id) + Vector2(-40, 0))
		await get_tree().process_frame
	controller.get_neuron_view(id).set_grabbed(false)
	model.release()
	# Headless frames are much shorter than the grab tween: wait by time.
	await await_millis(int(VisualTuning.GRAB_TWEEN_TIME * 1000.0) + 200)
	await _run_frames(2)
	assert_float(controller.get_neuron_view(id).get_shader_param(&"radius_px")) \
		.is_equal_approx(controller.get_neuron_view(id).get_radius(), 0.01)
