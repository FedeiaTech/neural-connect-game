extends GdUnitTestSuite
## T2.3: LevelController owns the model, builds views, runs the state machine, timer,
## move counter, restart and scoring. Built on a minimal node tree (no HUD).

const LevelFactory := preload("res://tests/model/level_factory.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const BoundaryScene := preload("res://scenes/views/boundary.tscn")

var _controller: LevelController
var _input: InputController
var _playfield: Node2D
var _recorder: SignalRecorder


func before_test() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	_playfield = Node2D.new()
	root.add_child(_playfield)
	var boundary: BoundaryView = BoundaryScene.instantiate()
	_playfield.add_child(boundary)
	var containers: Array[Node2D] = []
	for container_name in ["Obstacles", "Dendrites", "Neurons"]:
		var container := Node2D.new()
		container.name = container_name
		_playfield.add_child(container)
		containers.append(container)
	_input = InputController.new()
	_input.playfield = _playfield
	root.add_child(_input)
	_controller = LevelController.new()
	_controller.playfield = _playfield
	_controller.boundary = boundary
	_controller.obstacles_root = containers[0]
	_controller.dendrites_root = containers[1]
	_controller.neurons_root = containers[2]
	_controller.input_controller = _input
	root.add_child(_controller)
	_recorder = SignalRecorder.new()
	_recorder.watch(_controller, [
		&"move_count_changed", &"time_changed", &"level_completed", &"level_restart_requested"])


func _x_level(story := "") -> LevelData:
	var level := LevelFactory.x_level()
	level.story_text = story
	level.obstacles = [LevelFactory.rect(Vector2(700, 700), Vector2(100, 100))]
	return level


## Edge 0 TENSION 0-1 (rest 100, max 300), edge 1 NORMAL 2-3 crossing edge 2 NORMAL 4-5.
func _tension_level() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.neuron(0, Vector2(100, 500)),
		LevelFactory.neuron(1, Vector2(200, 500)),
		LevelFactory.neuron(2, Vector2(500, 100), Vector2(500, 100)),
		LevelFactory.neuron(3, Vector2(900, 400), Vector2(900, 100)),
		LevelFactory.neuron(4, Vector2(500, 400), Vector2(500, 300)),
		LevelFactory.neuron(5, Vector2(900, 100), Vector2(900, 300)),
	]
	var dendrites: Array[DendriteData] = [
		LevelFactory.tension_edge(0, 1, 100.0, 300.0),
		LevelFactory.edge(2, 3),
		LevelFactory.edge(4, 5),
	]
	return LevelFactory.level(neurons, dendrites)


func _screen(local: Vector2) -> Vector2:
	return _playfield.get_global_transform_with_canvas() * local


func _pointer(local: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = _screen(local)
	_input._unhandled_input(event)


func _move(local: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _screen(local)
	_input._unhandled_input(event)


## Solves the X level in one drag: neuron 1 to the same side of edge 2-3 as neuron 0.
func _solve_x_level() -> void:
	_pointer(Vector2(500, 500), true)
	_move(Vector2(300, 180))
	_pointer(Vector2(300, 180), false)


func test_level_with_story_starts_in_intro() -> void:
	_controller.load_level(_x_level("Once upon a synapse."))
	assert_int(_controller.get_state()).is_equal(LevelController.State.INTRO)
	assert_bool(_input.is_enabled()).is_false()


func test_level_without_story_starts_playing() -> void:
	_controller.load_level(_x_level())
	assert_int(_controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_bool(_input.is_enabled()).is_true()


func test_start_playing_leaves_intro() -> void:
	_controller.load_level(_x_level("Story."))
	_controller.start_playing()
	assert_int(_controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_bool(_input.is_enabled()).is_true()


func test_timer_counts_only_while_playing() -> void:
	_controller.load_level(_x_level("Story."))
	_controller.tick(5.0)
	assert_float(_controller.get_elapsed_time()).is_equal(0.0)
	_controller.start_playing()
	_controller.tick(1.5)
	_controller.tick(1.0)
	assert_float(_controller.get_elapsed_time()).is_equal_approx(2.5, 0.0001)
	assert_float(_recorder.last_args(&"time_changed")[0]).is_equal_approx(2.5, 0.0001)


func test_load_builds_one_view_per_element() -> void:
	_controller.load_level(_x_level())
	assert_int(_controller.neurons_root.get_child_count()).is_equal(4)
	assert_int(_controller.dendrites_root.get_child_count()).is_equal(2)
	assert_int(_controller.obstacles_root.get_child_count()).is_equal(1)
	assert_int(_controller.boundary.get_outline().size()).is_equal(5)
	assert_object(_controller.get_neuron_view(2)).is_not_null()


func test_load_resets_counters() -> void:
	_controller.load_level(_x_level())
	assert_array(_recorder.last_args(&"move_count_changed")).is_equal([0])
	assert_array(_recorder.last_args(&"time_changed")).is_equal([0.0])


func test_playfield_is_fitted_into_the_viewport() -> void:
	_controller.load_level(_x_level())
	var area := LevelController.get_fit_area()
	var top_left := _playfield.transform * Vector2(0, 0)
	var bottom_right := _playfield.transform * Vector2(1000, 1000)
	assert_bool(area.grow(0.01).has_point(top_left)).is_true()
	assert_bool(area.grow(0.01).has_point(bottom_right)).is_true()


func test_fit_centers_and_never_upscales() -> void:
	var fit := LevelController.compute_fit(Rect2(0, 0, 100, 50), Rect2(0, 0, 1000, 500))
	assert_float(fit.get_scale().x).is_equal(1.0)
	assert_vector(fit * Vector2(50, 25)).is_equal(Vector2(500, 250))


func test_fit_downscales_large_play_areas() -> void:
	var fit := LevelController.compute_fit(Rect2(0, 0, 2000, 1000), Rect2(0, 0, 1000, 1000))
	assert_float(fit.get_scale().x).is_equal_approx(0.5, 0.0001)
	assert_vector(fit * Vector2(1000, 500)).is_equal_approx(Vector2(500, 500), Vector2(0.001, 0.001))


func test_grab_marks_neuron_view_grabbed() -> void:
	_controller.load_level(_x_level())
	_pointer(Vector2(500, 500), true)
	assert_bool(_controller.get_neuron_view(1).is_grabbed()).is_true()
	_pointer(Vector2(500, 500), false)
	assert_bool(_controller.get_neuron_view(1).is_grabbed()).is_false()


func test_a_drag_counts_a_move() -> void:
	_controller.load_level(_x_level())
	_recorder.clear()
	_pointer(Vector2(500, 500), true)
	_move(Vector2(450, 300))
	_pointer(Vector2(450, 300), false)
	assert_int(_controller.get_move_count()).is_equal(1)
	assert_array(_recorder.last_args(&"move_count_changed")).is_equal([1])


func test_solving_completes_the_level_with_stars() -> void:
	_controller.load_level(_x_level())
	_controller.tick(10.0)
	_solve_x_level()
	assert_int(_controller.get_state()).is_equal(LevelController.State.COMPLETE)
	assert_bool(_input.is_enabled()).is_false()
	assert_int(_recorder.count(&"level_completed")).is_equal(1)
	var result: LevelResult = _recorder.last_args(&"level_completed")[0]
	assert_int(result.moves).is_equal(1)
	assert_float(result.time).is_equal_approx(10.0, 0.0001)
	assert_int(result.stars).is_equal(3)


func test_timer_stops_when_complete() -> void:
	_controller.load_level(_x_level())
	_solve_x_level()
	_controller.tick(5.0)
	assert_float(_controller.get_elapsed_time()).is_equal(0.0)


func test_restart_rebuilds_model_and_resets_counters() -> void:
	_controller.load_level(_x_level())
	var first_model := _controller.get_model()
	_solve_x_level()
	_controller.tick(3.0)
	_recorder.clear()
	_controller.restart()
	assert_int(_controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_object(_controller.get_model()).is_not_same(first_model)
	assert_vector(_controller.get_model().get_neuron_position(1)).is_equal(Vector2(500, 500))
	assert_int(_controller.get_move_count()).is_equal(0)
	assert_float(_controller.get_elapsed_time()).is_equal(0.0)
	assert_array(_recorder.last_args(&"move_count_changed")).is_equal([0])
	assert_array(_recorder.last_args(&"time_changed")).is_equal([0.0])
	assert_int(_recorder.count(&"level_restart_requested")).is_equal(1)
	assert_int(_controller.neurons_root.get_child_count()).is_equal(4)
	assert_int(_controller.dendrites_root.get_child_count()).is_equal(2)
	assert_int(_controller.obstacles_root.get_child_count()).is_equal(1)


func test_restart_rewires_views_to_the_new_model() -> void:
	_controller.load_level(_x_level())
	_controller.restart()
	_pointer(Vector2(500, 500), true)
	_move(Vector2(450, 300))
	# Pointer positions round-trip through the fitted (scaled) playfield transform.
	assert_vector(_controller.get_neuron_view(1).position).is_equal_approx(
		Vector2(450, 300), Vector2(0.01, 0.01))


func test_restart_key_restarts_while_playing() -> void:
	_controller.load_level(_x_level())
	_input.restart_requested.emit()
	assert_int(_recorder.count(&"level_restart_requested")).is_equal(1)


func test_restart_key_is_ignored_during_intro() -> void:
	_controller.load_level(_x_level("Story."))
	_input.restart_requested.emit()
	assert_int(_recorder.count(&"level_restart_requested")).is_equal(0)
	assert_int(_controller.get_state()).is_equal(LevelController.State.INTRO)


func test_broken_dendrite_restarts_after_a_delay() -> void:
	_controller.load_level(_tension_level())
	_pointer(Vector2(200, 500), true)
	_move(Vector2(450, 500))
	assert_int(_controller.get_state()).is_equal(LevelController.State.RESTARTING)
	assert_bool(_input.is_enabled()).is_false()
	_controller.tick(LevelController.BREAK_RESTART_DELAY * 0.5)
	assert_int(_controller.get_state()).is_equal(LevelController.State.RESTARTING)
	assert_float(_controller.get_elapsed_time()).is_equal(0.0)
	_controller.tick(LevelController.BREAK_RESTART_DELAY)
	assert_int(_controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_bool(_controller.get_model().is_broken()).is_false()
	assert_int(_recorder.count(&"level_restart_requested")).is_equal(1)


func test_break_reports_a_tension_loss() -> void:
	_recorder.watch(_controller, [&"level_lost"])
	_controller.load_level(_tension_level())
	_pointer(Vector2(200, 500), true)
	_move(Vector2(450, 500))
	assert_array(_recorder.last_args(&"level_lost")).is_equal([LevelController.LossReason.TENSION_BREAK])
	assert_int(_controller.get_loss_reason()).is_equal(LevelController.LossReason.TENSION_BREAK)


## T7.2: touching a lethal wall loses the level (overload) and restarts after a longer delay
## that leaves time for the explosion.
func test_destroyed_neuron_loses_and_restarts_after_the_explosion() -> void:
	_recorder.watch(_controller, [&"level_lost"])
	var level := _x_level()
	# Right side of the play area (x = 1000) is lethal.
	level.lethal_edges = PackedInt32Array([1])
	_controller.load_level(level)
	_pointer(Vector2(500, 500), true)
	_move(Vector2(1100, 500))
	assert_bool(_controller.get_model().is_destroyed()).is_true()
	assert_int(_controller.get_state()).is_equal(LevelController.State.RESTARTING)
	assert_bool(_input.is_enabled()).is_false()
	assert_array(_recorder.last_args(&"level_lost")).is_equal([LevelController.LossReason.OVERLOAD])
	assert_float(LevelController.DESTROY_RESTART_DELAY).is_greater(LevelController.BREAK_RESTART_DELAY)
	_controller.tick(LevelController.DESTROY_RESTART_DELAY * 0.8)
	assert_int(_controller.get_state()).is_equal(LevelController.State.RESTARTING)
	_controller.tick(LevelController.DESTROY_RESTART_DELAY)
	assert_int(_controller.get_state()).is_equal(LevelController.State.PLAYING)
	assert_bool(_controller.get_model().is_lost()).is_false()
	assert_int(_controller.get_loss_reason()).is_equal(LevelController.LossReason.NONE)
